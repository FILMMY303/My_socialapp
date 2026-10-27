-- Full CRUD for posts, comments and reactions.
--
-- Cloud schema (public):
--   profiles        (id PK -> auth.users, username, bio, ...)
--   posts           (id PK, user_id -> profiles, username, content, created_at, updated_at)
--   comments        (id PK, post_id -> posts ON DELETE CASCADE, user_id, username, content, created_at, updated_at)
--   post_reactions  (id PK, post_id -> posts ON DELETE CASCADE, user_id, type 'like'|'dislike',
--                    UNIQUE (post_id, user_id))
--
-- Ids are generated on the client (UUID v4) so a row created offline keeps the
-- same id locally and in the cloud. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Profiles: create one automatically for every new user (and backfill).
-- posts.user_id references profiles.id, so a missing profile blocks posting.
-- ---------------------------------------------------------------------------
create or replace function public.ensure_profile(uid uuid, uname text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    insert into public.profiles (id, username)
    values (uid, uname)
    on conflict (id) do nothing;
  exception when unique_violation then
    -- username already taken: fall back to a unique variant
    insert into public.profiles (id, username)
    values (uid, uname || '_' || left(uid::text, 6))
    on conflict (id) do nothing;
  end;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.ensure_profile(
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'username'), ''),
      split_part(new.email, '@', 1),
      'user'
    )
  );
  return new;
exception when others then
  -- never block sign-up because of the profile row
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

do $$
declare u record;
begin
  for u in
    select id, coalesce(nullif(trim(raw_user_meta_data ->> 'username'), ''),
                        split_part(email, '@', 1), 'user') as uname
    from auth.users
  loop
    perform public.ensure_profile(u.id, u.uname);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared trigger: keep updated_at current on every UPDATE.
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- posts
-- ---------------------------------------------------------------------------
alter table public.posts
  add column if not exists username text not null default 'User',
  add column if not exists updated_at timestamptz;

alter table public.posts drop constraint if exists posts_content_length;
alter table public.posts
  add constraint posts_content_length
  check (char_length(trim(content)) between 1 and 2000) not valid;

drop trigger if exists posts_set_updated_at on public.posts;
create trigger posts_set_updated_at
  before update on public.posts
  for each row execute function public.set_updated_at();

alter table public.posts enable row level security;
grant select, insert, update, delete on public.posts to authenticated;

drop policy if exists "Authenticated users can read posts" on public.posts;
create policy "Authenticated users can read posts"
  on public.posts for select to authenticated
  using (true);

drop policy if exists "Users can create their own posts" on public.posts;
create policy "Users can create their own posts"
  on public.posts for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own posts" on public.posts;
create policy "Users can update their own posts"
  on public.posts for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own posts" on public.posts;
create policy "Users can delete their own posts"
  on public.posts for delete to authenticated
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------
alter table public.comments
  add column if not exists username text not null default 'User',
  add column if not exists updated_at timestamptz;

alter table public.comments drop constraint if exists comments_content_length;
alter table public.comments
  add constraint comments_content_length
  check (char_length(trim(content)) between 1 and 1000) not valid;

-- Re-create the post foreign key with ON DELETE CASCADE.
do $$
declare r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    join pg_attribute a
      on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
    where c.conrelid = 'public.comments'::regclass
      and c.contype = 'f'
      and a.attname = 'post_id'
  loop
    execute format('alter table public.comments drop constraint %I', r.conname);
  end loop;
end;
$$;
alter table public.comments
  add constraint comments_post_id_fkey
  foreign key (post_id) references public.posts (id) on delete cascade;

create index if not exists comments_post_id_created_at_idx
  on public.comments (post_id, created_at);

drop trigger if exists comments_set_updated_at on public.comments;
create trigger comments_set_updated_at
  before update on public.comments
  for each row execute function public.set_updated_at();

alter table public.comments enable row level security;
grant select, insert, update, delete on public.comments to authenticated;

drop policy if exists "Authenticated users can read comments" on public.comments;
create policy "Authenticated users can read comments"
  on public.comments for select to authenticated
  using (true);

drop policy if exists "Users can create their own comments" on public.comments;
create policy "Users can create their own comments"
  on public.comments for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own comments" on public.comments;
create policy "Users can update their own comments"
  on public.comments for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own comments" on public.comments;
create policy "Users can delete their own comments"
  on public.comments for delete to authenticated
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- post_reactions (one reaction per user per post)
-- ---------------------------------------------------------------------------
delete from public.post_reactions where type not in ('like', 'dislike');

alter table public.post_reactions drop constraint if exists post_reactions_type_check;
alter table public.post_reactions
  add constraint post_reactions_type_check check (type in ('like', 'dislike'));

do $$
declare r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    join pg_attribute a
      on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
    where c.conrelid = 'public.post_reactions'::regclass
      and c.contype = 'f'
      and a.attname = 'post_id'
  loop
    execute format('alter table public.post_reactions drop constraint %I', r.conname);
  end loop;
end;
$$;
alter table public.post_reactions
  add constraint post_reactions_post_id_fkey
  foreign key (post_id) references public.posts (id) on delete cascade;

alter table public.post_reactions enable row level security;
grant select, insert, update, delete on public.post_reactions to authenticated;

drop policy if exists "Authenticated users can read reactions" on public.post_reactions;
create policy "Authenticated users can read reactions"
  on public.post_reactions for select to authenticated
  using (true);

drop policy if exists "Users can react as themselves" on public.post_reactions;
create policy "Users can react as themselves"
  on public.post_reactions for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can change their own reactions" on public.post_reactions;
create policy "Users can change their own reactions"
  on public.post_reactions for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can remove their own reactions" on public.post_reactions;
create policy "Users can remove their own reactions"
  on public.post_reactions for delete to authenticated
  using (auth.uid() = user_id);

notify pgrst, 'reload schema';
