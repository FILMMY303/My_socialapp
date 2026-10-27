-- Per-person DM notification mutes. Run after 20261008010000_social_features.sql.
--
--   chat_mutes  user_id -> auth.users (who muted), muted_user_id -> auth.users,
--               created_at, PRIMARY KEY (user_id, muted_user_id)
--
-- Each user can only see and change their own mutes. Safe to re-run.

create table if not exists public.chat_mutes (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  muted_user_id uuid not null
    references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, muted_user_id),
  constraint chat_mutes_not_self check (user_id <> muted_user_id)
);

alter table public.chat_mutes enable row level security;
grant select, insert, delete on public.chat_mutes to authenticated;

drop policy if exists "Users see their own mutes" on public.chat_mutes;
create policy "Users see their own mutes"
  on public.chat_mutes for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users mute as themselves" on public.chat_mutes;
create policy "Users mute as themselves"
  on public.chat_mutes for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users unmute their own mutes" on public.chat_mutes;
create policy "Users unmute their own mutes"
  on public.chat_mutes for delete to authenticated
  using (auth.uid() = user_id);

-- Make sure new messages are broadcast for live notifications.
do $$
begin
  alter publication supabase_realtime add table public.direct_messages;
exception
  when duplicate_object then null;
  when undefined_object then null;
end;
$$;

notify pgrst, 'reload schema';
