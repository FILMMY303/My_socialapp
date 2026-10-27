-- Social features: profiles (public/private), follows, media posts, emoji
-- reactions, hashtags, groups/pages, 1-1 chat, reports, storage buckets.
-- Run after 20261007050000_crud_posts_comments_reactions.sql. Safe to re-run.
--
-- Cloud schema after this migration (public):
--   profiles        id PK -> auth.users, username, display_name, bio,
--                   profile_url (avatar), is_private, created_at, updated_at
--   follows         follower_id, following_id, status 'pending'|'accepted', created_at
--   groups          id PK, name, description, kind 'group'|'page', created_by, created_at, updated_at
--   group_members   group_id -> groups CASCADE, user_id, role 'owner'|'admin'|'member', joined_at
--   posts           + group_id -> groups CASCADE, media_url, media_type 'image'|'video', tags text[]
--   post_reactions  type 'like'|'love'|'haha'|'wow'|'sad'|'angry'|'dislike'
--   direct_messages id, sender_id, receiver_id, message, media_url, media_type, is_read, created_at
--   reports         id, post_id -> posts CASCADE, reported_by, reason, details, status, created_at
--
-- Storage buckets: avatars (public), post-media (public), chat-media (private).
-- Every object path starts with the uploader's user id.

-- ===========================================================================
-- Helpers
-- ===========================================================================

-- Drops every foreign key on table.column, so it can be re-created with the
-- ON DELETE behaviour we want regardless of its original name.
create or replace function public._drop_fk(tbl regclass, col text)
returns void
language plpgsql
as $$
declare r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
    where c.conrelid = tbl and c.contype = 'f' and a.attname = col
  loop
    execute format('alter table %s drop constraint %I', tbl, r.conname);
  end loop;
end;
$$;

-- ===========================================================================
-- Profiles
-- ===========================================================================
alter table public.profiles
  add column if not exists display_name text,
  add column if not exists bio text,
  add column if not exists profile_url text,
  add column if not exists is_private boolean not null default false,
  add column if not exists updated_at timestamptz;

alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles
  add constraint profiles_username_format
  check (char_length(trim(username)) between 1 and 30) not valid;

alter table public.profiles drop constraint if exists profiles_bio_length;
alter table public.profiles
  add constraint profiles_bio_length
  check (bio is null or char_length(bio) <= 300) not valid;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
grant select, insert, update on public.profiles to authenticated;

drop policy if exists "Profiles are visible to signed-in users" on public.profiles;
create policy "Profiles are visible to signed-in users"
  on public.profiles for select to authenticated
  using (true);

drop policy if exists "Users can create their own profile" on public.profiles;
create policy "Users can create their own profile"
  on public.profiles for insert to authenticated
  with check (auth.uid() = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Keep the username copied onto posts/comments in step with the profile.
create or replace function public.sync_username()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.username is distinct from old.username then
    update public.posts set username = new.username where user_id = new.id;
    update public.comments set username = new.username where user_id = new.id;
  end if;
  -- Going public accepts every waiting follow request.
  if old.is_private and not new.is_private then
    update public.follows set status = 'accepted'
    where following_id = new.id and status = 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_sync_username on public.profiles;
create trigger profiles_sync_username
  after update on public.profiles
  for each row execute function public.sync_username();

-- ===========================================================================
-- Follows (private profiles need approval)
-- ===========================================================================
alter table public.follows
  add column if not exists status text not null default 'accepted';

alter table public.follows drop constraint if exists follows_status_check;
alter table public.follows
  add constraint follows_status_check check (status in ('pending', 'accepted'));

alter table public.follows drop constraint if exists follows_not_self;
alter table public.follows
  add constraint follows_not_self check (follower_id <> following_id) not valid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.follows'::regclass and contype in ('p', 'u')
  ) then
    alter table public.follows
      add constraint follows_pkey primary key (follower_id, following_id);
  end if;
end;
$$;

create index if not exists follows_following_idx
  on public.follows (following_id, status);

create or replace function public.set_follow_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.status := case
      when exists (select 1 from public.profiles
                   where id = new.following_id and is_private)
      then 'pending' else 'accepted' end;
  else
    -- Only the status may change, and only to 'accepted'.
    new.follower_id := old.follower_id;
    new.following_id := old.following_id;
    new.created_at := old.created_at;
    new.status := 'accepted';
  end if;
  return new;
end;
$$;

drop trigger if exists follows_set_status on public.follows;
create trigger follows_set_status
  before insert or update on public.follows
  for each row execute function public.set_follow_status();

alter table public.follows enable row level security;
grant select, insert, update, delete on public.follows to authenticated;

drop policy if exists "Follows are visible to signed-in users" on public.follows;
create policy "Follows are visible to signed-in users"
  on public.follows for select to authenticated
  using (true);

drop policy if exists "Users can follow as themselves" on public.follows;
create policy "Users can follow as themselves"
  on public.follows for insert to authenticated
  with check (auth.uid() = follower_id);

drop policy if exists "Users can accept their follow requests" on public.follows;
create policy "Users can accept their follow requests"
  on public.follows for update to authenticated
  using (auth.uid() = following_id)
  with check (auth.uid() = following_id);

drop policy if exists "Users can unfollow or remove followers" on public.follows;
create policy "Users can unfollow or remove followers"
  on public.follows for delete to authenticated
  using (auth.uid() in (follower_id, following_id));

-- True when the current user may see content owned by [owner].
create or replace function public.can_view_user_content(owner uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select owner = auth.uid()
    or not coalesce((select p.is_private from public.profiles p where p.id = owner), false)
    or exists (
      select 1 from public.follows f
      where f.follower_id = auth.uid()
        and f.following_id = owner
        and f.status = 'accepted'
    );
$$;

-- ===========================================================================
-- Groups and pages
-- ===========================================================================
alter table public.groups
  add column if not exists description text,
  add column if not exists kind text not null default 'group',
  add column if not exists updated_at timestamptz;

alter table public.groups drop constraint if exists groups_kind_check;
alter table public.groups
  add constraint groups_kind_check check (kind in ('group', 'page'));

alter table public.groups drop constraint if exists groups_name_length;
alter table public.groups
  add constraint groups_name_length
  check (char_length(trim(name)) between 1 and 80) not valid;

drop trigger if exists groups_set_updated_at on public.groups;
create trigger groups_set_updated_at
  before update on public.groups
  for each row execute function public.set_updated_at();

alter table public.group_members
  add column if not exists role text not null default 'member',
  add column if not exists joined_at timestamptz not null default now();

update public.group_members set role = 'member'
where role not in ('owner', 'admin', 'member');

alter table public.group_members drop constraint if exists group_members_role_check;
alter table public.group_members
  add constraint group_members_role_check
  check (role in ('owner', 'admin', 'member'));

select public._drop_fk('public.group_members', 'group_id');
alter table public.group_members
  add constraint group_members_group_id_fkey
  foreign key (group_id) references public.groups (id) on delete cascade;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.group_members'::regclass and contype in ('p', 'u')
  ) then
    alter table public.group_members
      add constraint group_members_pkey primary key (group_id, user_id);
  end if;
end;
$$;

create or replace function public.group_role(gid uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role from public.group_members m
  where m.group_id = gid and m.user_id = auth.uid();
$$;

-- Group: every member can post. Page: only owner/admins can post.
create or replace function public.can_post_in_group(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select gid is null or exists (
    select 1
    from public.group_members m
    join public.groups g on g.id = m.group_id
    where m.group_id = gid
      and m.user_id = auth.uid()
      and (g.kind = 'group' or m.role in ('owner', 'admin'))
  );
$$;

-- The creator becomes the owner.
create or replace function public.add_group_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.group_members (group_id, user_id, role)
  values (new.id, new.created_by, 'owner')
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists groups_add_owner on public.groups;
create trigger groups_add_owner
  after insert on public.groups
  for each row execute function public.add_group_owner();

alter table public.groups enable row level security;
grant select, insert, update, delete on public.groups to authenticated;

drop policy if exists "Groups are visible to signed-in users" on public.groups;
create policy "Groups are visible to signed-in users"
  on public.groups for select to authenticated
  using (true);

drop policy if exists "Users can create groups" on public.groups;
create policy "Users can create groups"
  on public.groups for insert to authenticated
  with check (auth.uid() = created_by);

drop policy if exists "Owners and admins can edit groups" on public.groups;
create policy "Owners and admins can edit groups"
  on public.groups for update to authenticated
  using (public.group_role(id) in ('owner', 'admin'));

drop policy if exists "Owners can delete groups" on public.groups;
create policy "Owners can delete groups"
  on public.groups for delete to authenticated
  using (public.group_role(id) = 'owner');

alter table public.group_members enable row level security;
grant select, insert, update, delete on public.group_members to authenticated;

drop policy if exists "Members are visible to signed-in users" on public.group_members;
create policy "Members are visible to signed-in users"
  on public.group_members for select to authenticated
  using (true);

drop policy if exists "Users can join groups" on public.group_members;
create policy "Users can join groups"
  on public.group_members for insert to authenticated
  with check (auth.uid() = user_id and role = 'member');

drop policy if exists "Members can leave and admins can remove" on public.group_members;
create policy "Members can leave and admins can remove"
  on public.group_members for delete to authenticated
  using (
    (auth.uid() = user_id and role <> 'owner')
    or (public.group_role(group_id) in ('owner', 'admin') and role = 'member')
  );

-- ===========================================================================
-- Posts: media, hashtags, groups, privacy
-- ===========================================================================
alter table public.posts
  add column if not exists group_id uuid,
  add column if not exists media_url text,
  add column if not exists media_type text,
  add column if not exists tags text[] not null default '{}';

select public._drop_fk('public.posts', 'group_id');
alter table public.posts
  add constraint posts_group_id_fkey
  foreign key (group_id) references public.groups (id) on delete cascade;

alter table public.posts drop constraint if exists posts_media_type_check;
alter table public.posts
  add constraint posts_media_type_check
  check (media_type is null or media_type in ('image', 'video'));

-- Text may be empty when the post has an image or video.
alter table public.posts drop constraint if exists posts_content_length;
alter table public.posts
  add constraint posts_content_length
  check (
    char_length(content) <= 2000
    and (char_length(trim(content)) > 0 or media_url is not null)
  ) not valid;

create index if not exists posts_group_created_idx
  on public.posts (group_id, created_at desc);
create index if not exists posts_user_created_idx
  on public.posts (user_id, created_at desc);
create index if not exists posts_tags_idx on public.posts using gin (tags);

create or replace function public.extract_post_tags()
returns trigger
language plpgsql
as $$
begin
  new.tags := coalesce(
    (select array_agg(distinct lower(m[1]))
     from regexp_matches(coalesce(new.content, ''),
                         '#([^[:space:][:punct:]]+)', 'g') as m),
    '{}'
  );
  return new;
end;
$$;

drop trigger if exists posts_extract_tags on public.posts;
create trigger posts_extract_tags
  before insert or update of content on public.posts
  for each row execute function public.extract_post_tags();

-- Only bump updated_at when the text changes (not on tag backfill etc.).
drop trigger if exists posts_set_updated_at on public.posts;
create trigger posts_set_updated_at
  before update of content on public.posts
  for each row execute function public.set_updated_at();

drop trigger if exists comments_set_updated_at on public.comments;
create trigger comments_set_updated_at
  before update of content on public.comments
  for each row execute function public.set_updated_at();

update public.posts p
set tags = coalesce(
  (select array_agg(distinct lower(m[1]))
   from regexp_matches(coalesce(p.content, ''),
                       '#([^[:space:][:punct:]]+)', 'g') as m),
  '{}'
);

-- Replace every read policy on posts with the privacy-aware one.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'posts' and cmd in ('SELECT', 'ALL')
  loop
    execute format('drop policy %I on public.posts', p.policyname);
  end loop;
end;
$$;

create policy "Posts follow the author's privacy"
  on public.posts for select to authenticated
  using (public.can_view_user_content(user_id));

drop policy if exists "Users can create their own posts" on public.posts;
create policy "Users can create their own posts"
  on public.posts for insert to authenticated
  with check (auth.uid() = user_id and public.can_post_in_group(group_id));

drop policy if exists "Users can delete their own posts" on public.posts;
create policy "Users can delete their own posts"
  on public.posts for delete to authenticated
  using (
    auth.uid() = user_id
    or (group_id is not null and public.group_role(group_id) in ('owner', 'admin'))
  );

-- ===========================================================================
-- Reactions: emoji set + dislike
-- ===========================================================================
alter table public.post_reactions drop constraint if exists post_reactions_type_check;
alter table public.post_reactions
  add constraint post_reactions_type_check
  check (type in ('like', 'love', 'haha', 'wow', 'sad', 'angry', 'dislike'));

-- ===========================================================================
-- Direct messages (1-1 chat)
-- ===========================================================================
alter table public.direct_messages
  add column if not exists message text not null default '',
  add column if not exists media_url text,
  add column if not exists media_type text,
  add column if not exists is_read boolean not null default false;

alter table public.direct_messages alter column message set default '';

alter table public.direct_messages drop constraint if exists direct_messages_media_type_check;
alter table public.direct_messages
  add constraint direct_messages_media_type_check
  check (media_type is null or media_type in ('image', 'video'));

alter table public.direct_messages drop constraint if exists direct_messages_not_empty;
alter table public.direct_messages
  add constraint direct_messages_not_empty
  check (
    char_length(coalesce(message, '')) <= 4000
    and (char_length(trim(coalesce(message, ''))) > 0 or media_url is not null)
  ) not valid;

create index if not exists direct_messages_pair_idx
  on public.direct_messages (sender_id, receiver_id, created_at desc);
create index if not exists direct_messages_receiver_idx
  on public.direct_messages (receiver_id, created_at desc);

alter table public.direct_messages enable row level security;
grant select, insert, update, delete on public.direct_messages to authenticated;

do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'direct_messages'
  loop
    execute format('drop policy %I on public.direct_messages', p.policyname);
  end loop;
end;
$$;

create policy "Participants can read their messages"
  on public.direct_messages for select to authenticated
  using (auth.uid() in (sender_id, receiver_id));

create policy "Users send messages as themselves"
  on public.direct_messages for insert to authenticated
  with check (auth.uid() = sender_id and sender_id <> receiver_id);

create policy "Receivers can mark messages as read"
  on public.direct_messages for update to authenticated
  using (auth.uid() = receiver_id)
  with check (auth.uid() = receiver_id);

create policy "Senders can unsend messages"
  on public.direct_messages for delete to authenticated
  using (auth.uid() = sender_id);

-- Live updates for the chat screen.
do $$
begin
  alter publication supabase_realtime add table public.direct_messages;
exception
  when duplicate_object then null;
  when undefined_object then null;
end;
$$;

-- ===========================================================================
-- Reports
-- ===========================================================================
alter table public.reports
  add column if not exists details text,
  add column if not exists status text not null default 'pending';

alter table public.reports drop constraint if exists reports_reason_check;
alter table public.reports
  add constraint reports_reason_check
  check (reason in ('spam', 'nudity', 'violence', 'harassment', 'hate',
                    'false_information', 'other')) not valid;

select public._drop_fk('public.reports', 'post_id');
alter table public.reports
  add constraint reports_post_id_fkey
  foreign key (post_id) references public.posts (id) on delete cascade;

do $$
begin
  create unique index if not exists reports_once_per_user
    on public.reports (post_id, reported_by);
exception when unique_violation then
  raise notice 'Duplicate reports exist; one-report-per-user index skipped.';
end;
$$;

alter table public.reports enable row level security;
grant select, insert on public.reports to authenticated;

drop policy if exists "Users can report posts" on public.reports;
create policy "Users can report posts"
  on public.reports for insert to authenticated
  with check (auth.uid() = reported_by);

drop policy if exists "Users can see their own reports" on public.reports;
create policy "Users can see their own reports"
  on public.reports for select to authenticated
  using (auth.uid() = reported_by);

-- ===========================================================================
-- Storage
-- ===========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880,
   array['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  ('post-media', 'post-media', true, 52428800,
   array['image/jpeg', 'image/png', 'image/webp', 'image/gif',
         'video/mp4', 'video/webm', 'video/quicktime']),
  ('chat-media', 'chat-media', false, 52428800,
   array['image/jpeg', 'image/png', 'image/webp', 'image/gif',
         'video/mp4', 'video/webm', 'video/quicktime'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users upload to their own folder" on storage.objects;
create policy "Users upload to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('avatars', 'post-media', 'chat-media')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users delete their own files" on storage.objects;
create policy "Users delete their own files"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('avatars', 'post-media', 'chat-media')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users update their own files" on storage.objects;
create policy "Users update their own files"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('avatars', 'post-media')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- chat-media/<sender>/<receiver>/<file>: readable by both participants.
drop policy if exists "Chat participants read chat media" on storage.objects;
create policy "Chat participants read chat media"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat-media'
    and auth.uid()::text in ((storage.foldername(name))[1],
                             (storage.foldername(name))[2])
  );

drop function if exists public._drop_fk(regclass, text);

notify pgrst, 'reload schema';
