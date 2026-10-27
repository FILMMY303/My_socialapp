-- Group staff/moderation, comment media + replies, activity notifications,
-- saved posts. Run after 20261008020000_chat_mutes.sql. Safe to re-run.
--
--   groups         + avatar_url, cover_url
--   group_members  owner can promote member <-> admin ("staff") and kick anyone
--   reports        group owners/staff can read and resolve reports on group posts
--   comments       + parent_id -> comments CASCADE (replies), media_url, media_type
--   notifications  id, user_id (recipient), actor_id -> profiles, type, post_id,
--                  group_id, is_read, created_at   (filled by triggers)
--   saved_posts    user_id, post_id -> posts CASCADE, created_at
--   profiles       + saved_public (others may see my saved posts)

-- ===========================================================================
-- Groups: pictures, staff, kicking
-- ===========================================================================
alter table public.groups
  add column if not exists avatar_url text,
  add column if not exists cover_url text;

drop policy if exists "Owners can change member roles" on public.group_members;
create policy "Owners can change member roles"
  on public.group_members for update to authenticated
  using (public.group_role(group_id) = 'owner' and role <> 'owner')
  with check (public.group_role(group_id) = 'owner' and role in ('admin', 'member'));

drop policy if exists "Members can leave and admins can remove" on public.group_members;
create policy "Members can leave and admins can remove"
  on public.group_members for delete to authenticated
  using (
    (auth.uid() = user_id and role <> 'owner')
    or (public.group_role(group_id) = 'owner' and role <> 'owner')
    or (public.group_role(group_id) = 'admin' and role = 'member')
  );

-- ===========================================================================
-- Reports: group owners/staff review reports on their group's posts
-- ===========================================================================
alter table public.reports
  add column if not exists reviewed_by uuid references auth.users (id) on delete set null,
  add column if not exists reviewed_at timestamptz;

alter table public.reports drop constraint if exists reports_status_check;
alter table public.reports
  add constraint reports_status_check
  check (status in ('pending', 'dismissed', 'removed')) not valid;

create or replace function public.can_moderate_post(pid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.posts p
    where p.id = pid
      and p.group_id is not null
      and public.group_role(p.group_id) in ('owner', 'admin')
  );
$$;

drop policy if exists "Users can see their own reports" on public.reports;
create policy "Users can see their own reports"
  on public.reports for select to authenticated
  using (auth.uid() = reported_by or public.can_moderate_post(post_id));

drop policy if exists "Group staff can review reports" on public.reports;
create policy "Group staff can review reports"
  on public.reports for update to authenticated
  using (public.can_moderate_post(post_id))
  with check (public.can_moderate_post(post_id));

grant update on public.reports to authenticated;

-- ===========================================================================
-- Comments: replies and media
-- ===========================================================================
alter table public.comments
  add column if not exists parent_id uuid,
  add column if not exists media_url text,
  add column if not exists media_type text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'comments_parent_id_fkey'
  ) then
    alter table public.comments
      add constraint comments_parent_id_fkey
      foreign key (parent_id) references public.comments (id) on delete cascade;
  end if;
end;
$$;

create index if not exists comments_parent_idx on public.comments (parent_id);

alter table public.comments drop constraint if exists comments_media_type_check;
alter table public.comments
  add constraint comments_media_type_check
  check (media_type is null or media_type in ('image', 'video'));

alter table public.comments drop constraint if exists comments_content_length;
alter table public.comments
  add constraint comments_content_length
  check (
    char_length(content) <= 1000
    and (char_length(trim(content)) > 0 or media_url is not null)
  ) not valid;

-- ===========================================================================
-- Notifications (follows, follow requests, new posts from people/pages)
-- ===========================================================================
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  type text not null check (type in (
    'follow', 'follow_request', 'follow_accepted', 'friend_post', 'page_post'
  )),
  post_id uuid references public.posts (id) on delete cascade,
  group_id uuid references public.groups (id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;
grant select, update, delete on public.notifications to authenticated;

drop policy if exists "Users read their notifications" on public.notifications;
create policy "Users read their notifications"
  on public.notifications for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users mark their notifications read" on public.notifications;
create policy "Users mark their notifications read"
  on public.notifications for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users delete their notifications" on public.notifications;
create policy "Users delete their notifications"
  on public.notifications for delete to authenticated
  using (auth.uid() = user_id);

-- Follows -> notifications.
create or replace function public.notify_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, actor_id, type)
    values (
      new.following_id,
      new.follower_id,
      case when new.status = 'pending' then 'follow_request' else 'follow' end
    );
  elsif tg_op = 'UPDATE' then
    if old.status = 'pending' and new.status = 'accepted' then
      -- "requested to follow you" becomes "started following you".
      update public.notifications
      set type = 'follow'
      where user_id = new.following_id
        and actor_id = new.follower_id
        and type = 'follow_request';
      insert into public.notifications (user_id, actor_id, type)
      values (new.follower_id, new.following_id, 'follow_accepted');
    end if;
  elsif tg_op = 'DELETE' then
    -- A declined or cancelled request disappears from the list.
    delete from public.notifications
    where user_id = old.following_id
      and actor_id = old.follower_id
      and type = 'follow_request';
  end if;
  return coalesce(new, old);
exception when others then
  -- Never block following because of a notification.
  return coalesce(new, old);
end;
$$;

drop trigger if exists follows_notify on public.follows;
create trigger follows_notify
  after insert or update or delete on public.follows
  for each row execute function public.notify_follow();

-- New posts -> followers (personal posts) or page followers (page posts).
create or replace function public.notify_new_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.group_id is null then
    insert into public.notifications (user_id, actor_id, type, post_id)
    select f.follower_id, new.user_id, 'friend_post', new.id
    from public.follows f
    where f.following_id = new.user_id and f.status = 'accepted';
  elsif exists (
    select 1 from public.groups g where g.id = new.group_id and g.kind = 'page'
  ) then
    insert into public.notifications (user_id, actor_id, type, post_id, group_id)
    select m.user_id, new.user_id, 'page_post', new.id, new.group_id
    from public.group_members m
    where m.group_id = new.group_id and m.user_id <> new.user_id;
  end if;
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists posts_notify on public.posts;
create trigger posts_notify
  after insert on public.posts
  for each row execute function public.notify_new_post();

do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception
  when duplicate_object then null;
  when undefined_object then null;
end;
$$;

-- ===========================================================================
-- Saved posts
-- ===========================================================================
alter table public.profiles
  add column if not exists saved_public boolean not null default false;

create table if not exists public.saved_posts (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  post_id uuid not null references public.posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create index if not exists saved_posts_user_created_idx
  on public.saved_posts (user_id, created_at desc);

alter table public.saved_posts enable row level security;
grant select, insert, delete on public.saved_posts to authenticated;

drop policy if exists "Saved posts follow the owner's choice" on public.saved_posts;
create policy "Saved posts follow the owner's choice"
  on public.saved_posts for select to authenticated
  using (
    auth.uid() = user_id
    or exists (
      select 1 from public.profiles p
      where p.id = user_id and p.saved_public
    )
  );

drop policy if exists "Users save posts as themselves" on public.saved_posts;
create policy "Users save posts as themselves"
  on public.saved_posts for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users unsave their posts" on public.saved_posts;
create policy "Users unsave their posts"
  on public.saved_posts for delete to authenticated
  using (auth.uid() = user_id);

notify pgrst, 'reload schema';
