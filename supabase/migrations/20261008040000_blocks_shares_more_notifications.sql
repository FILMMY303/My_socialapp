-- Blocking, sharing posts, and notifications for comments / replies /
-- reactions / shares. Run after 20261008030000_...sql. Safe to re-run.
--
--   blocks         blocker_id, blocked_id, created_at   PK (blocker_id, blocked_id)
--   posts          + shared_post_id -> posts (ON DELETE SET NULL)
--   notifications  + comment_id -> comments CASCADE, reaction;
--                  types + comment, reply, reaction, share
--
-- A block works both ways: neither person sees the other's posts or
-- comments, and they can't message, follow or notify each other.

-- ===========================================================================
-- Blocks
-- ===========================================================================
create table if not exists public.blocks (
  blocker_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);

alter table public.blocks enable row level security;
grant select, insert, delete on public.blocks to authenticated;

-- Only the blocker sees the block (the blocked person is not told).
drop policy if exists "Users see who they blocked" on public.blocks;
create policy "Users see who they blocked"
  on public.blocks for select to authenticated
  using (auth.uid() = blocker_id);

drop policy if exists "Users block as themselves" on public.blocks;
create policy "Users block as themselves"
  on public.blocks for insert to authenticated
  with check (auth.uid() = blocker_id);

drop policy if exists "Users unblock" on public.blocks;
create policy "Users unblock"
  on public.blocks for delete to authenticated
  using (auth.uid() = blocker_id);

create or replace function public.is_blocked_pair(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

-- Blocking removes follows in both directions.
create or replace function public.apply_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.follows
  where (follower_id = new.blocker_id and following_id = new.blocked_id)
     or (follower_id = new.blocked_id and following_id = new.blocker_id);
  return new;
end;
$$;

drop trigger if exists blocks_apply on public.blocks;
create trigger blocks_apply
  after insert on public.blocks
  for each row execute function public.apply_block();

-- Posts: hidden between blocked people.
drop policy if exists "Posts follow the author's privacy" on public.posts;
create policy "Posts follow the author's privacy"
  on public.posts for select to authenticated
  using (
    public.can_view_user_content(user_id)
    and not public.is_blocked_pair(auth.uid(), user_id)
  );

-- Comments: replace every read policy with one that respects blocks.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'comments'
      and cmd in ('SELECT', 'ALL')
  loop
    execute format('drop policy %I on public.comments', p.policyname);
  end loop;
end;
$$;

create policy "Comments are hidden between blocked people"
  on public.comments for select to authenticated
  using (not public.is_blocked_pair(auth.uid(), user_id));

-- Re-create write policies in case an ALL policy was dropped above.
drop policy if exists "Users can create their own comments" on public.comments;
create policy "Users can create their own comments"
  on public.comments for insert to authenticated
  with check (
    auth.uid() = user_id
    and not exists (
      select 1 from public.posts p
      where p.id = post_id and public.is_blocked_pair(auth.uid(), p.user_id)
    )
  );

drop policy if exists "Users can update their own comments" on public.comments;
create policy "Users can update their own comments"
  on public.comments for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own comments" on public.comments;
create policy "Users can delete their own comments"
  on public.comments for delete to authenticated
  using (auth.uid() = user_id);

-- Messages and follows: not between blocked people.
drop policy if exists "Users send messages as themselves" on public.direct_messages;
create policy "Users send messages as themselves"
  on public.direct_messages for insert to authenticated
  with check (
    auth.uid() = sender_id
    and sender_id <> receiver_id
    and not public.is_blocked_pair(sender_id, receiver_id)
  );

drop policy if exists "Users can follow as themselves" on public.follows;
create policy "Users can follow as themselves"
  on public.follows for insert to authenticated
  with check (
    auth.uid() = follower_id
    and not public.is_blocked_pair(follower_id, following_id)
  );

-- ===========================================================================
-- Sharing posts
-- ===========================================================================
alter table public.posts add column if not exists shared_post_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'posts_shared_post_id_fkey'
  ) then
    alter table public.posts
      add constraint posts_shared_post_id_fkey
      foreign key (shared_post_id) references public.posts (id)
      on delete set null;
  end if;
end;
$$;

-- A share may have no caption.
alter table public.posts drop constraint if exists posts_content_length;
alter table public.posts
  add constraint posts_content_length
  check (
    char_length(content) <= 2000
    and (
      char_length(trim(content)) > 0
      or media_url is not null
      or shared_post_id is not null
    )
  ) not valid;

-- ===========================================================================
-- More notifications: comment, reply, reaction, share
-- ===========================================================================
alter table public.notifications
  add column if not exists comment_id uuid
    references public.comments (id) on delete cascade,
  add column if not exists reaction text;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check
  check (type in (
    'follow', 'follow_request', 'follow_accepted', 'friend_post', 'page_post',
    'comment', 'reply', 'reaction', 'share'
  ));

-- Shared rule: never notify yourself or someone who blocked you.
create or replace function public.should_notify(recipient uuid, actor uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select recipient is not null
    and recipient <> actor
    and not public.is_blocked_pair(recipient, actor);
$$;

create or replace function public.notify_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  post_owner uuid;
  parent_owner uuid;
begin
  select user_id into post_owner from public.posts where id = new.post_id;
  if new.parent_id is not null then
    select user_id into parent_owner from public.comments where id = new.parent_id;
    if public.should_notify(parent_owner, new.user_id) then
      insert into public.notifications (user_id, actor_id, type, post_id, comment_id)
      values (parent_owner, new.user_id, 'reply', new.post_id, new.id);
    end if;
  end if;
  -- The post owner hears about every comment (once, if also the parent owner).
  if public.should_notify(post_owner, new.user_id)
     and post_owner is distinct from parent_owner then
    insert into public.notifications (user_id, actor_id, type, post_id, comment_id)
    values (post_owner, new.user_id, 'comment', new.post_id, new.id);
  end if;
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists comments_notify on public.comments;
create trigger comments_notify
  after insert on public.comments
  for each row execute function public.notify_comment();

-- One reaction notification per person per post, kept up to date.
create or replace function public.notify_reaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare post_owner uuid;
begin
  if tg_op = 'DELETE' then
    delete from public.notifications
    where type = 'reaction' and post_id = old.post_id and actor_id = old.user_id;
    return old;
  end if;

  select user_id into post_owner from public.posts where id = new.post_id;
  delete from public.notifications
  where type = 'reaction' and post_id = new.post_id and actor_id = new.user_id;
  -- Dislikes are not announced.
  if new.type <> 'dislike' and public.should_notify(post_owner, new.user_id) then
    insert into public.notifications (user_id, actor_id, type, post_id, reaction)
    values (post_owner, new.user_id, 'reaction', new.post_id, new.type);
  end if;
  return new;
exception when others then
  return coalesce(new, old);
end;
$$;

drop trigger if exists post_reactions_notify on public.post_reactions;
create trigger post_reactions_notify
  after insert or update or delete on public.post_reactions
  for each row execute function public.notify_reaction();

-- New posts: also tell the original author when their post is shared.
create or replace function public.notify_new_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare original_owner uuid;
begin
  if new.group_id is null then
    insert into public.notifications (user_id, actor_id, type, post_id)
    select f.follower_id, new.user_id, 'friend_post', new.id
    from public.follows f
    where f.following_id = new.user_id and f.status = 'accepted'
      and not public.is_blocked_pair(f.follower_id, new.user_id);
  elsif exists (
    select 1 from public.groups g where g.id = new.group_id and g.kind = 'page'
  ) then
    insert into public.notifications (user_id, actor_id, type, post_id, group_id)
    select m.user_id, new.user_id, 'page_post', new.id, new.group_id
    from public.group_members m
    where m.group_id = new.group_id and m.user_id <> new.user_id
      and not public.is_blocked_pair(m.user_id, new.user_id);
  end if;

  if new.shared_post_id is not null then
    select user_id into original_owner
    from public.posts where id = new.shared_post_id;
    if public.should_notify(original_owner, new.user_id) then
      insert into public.notifications (user_id, actor_id, type, post_id)
      values (original_owner, new.user_id, 'share', new.id);
    end if;
  end if;
  return new;
exception when others then
  return new;
end;
$$;

notify pgrst, 'reload schema';
