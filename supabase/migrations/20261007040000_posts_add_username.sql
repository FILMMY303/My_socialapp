-- The posts table may already exist without a username column, in which case
-- the create-table migration is skipped. Bring it up to the expected shape.
alter table public.posts
  add column if not exists username text not null default 'User';

create index if not exists posts_created_at_idx
  on public.posts (created_at desc);

alter table public.posts enable row level security;

grant select, insert on public.posts to authenticated;

drop policy if exists "Authenticated users can read posts" on public.posts;
create policy "Authenticated users can read posts"
  on public.posts
  for select
  to authenticated
  using (true);

drop policy if exists "Users can create their own posts" on public.posts;
create policy "Users can create their own posts"
  on public.posts
  for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Make PostgREST pick up the new column immediately.
notify pgrst, 'reload schema';
