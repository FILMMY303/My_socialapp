-- Per-member notification setting for groups and pages.
-- Run after 20261008040000_...sql. Safe to re-run.
--
--   group_members  + notify boolean  null = default for the kind
--                                    (pages on, groups off)
--   notifications  types + group_post
--
-- Members change only their own setting through set_group_notifications(),
-- so the existing owner-only update policy (roles) stays as it is.

alter table public.group_members
  add column if not exists notify boolean;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check
  check (type in (
    'follow', 'follow_request', 'follow_accepted', 'friend_post', 'page_post',
    'group_post', 'comment', 'reply', 'reaction', 'share'
  ));

create or replace function public.set_group_notifications(
  gid uuid,
  enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.group_members
  set notify = enabled
  where group_id = gid and user_id = auth.uid();
  if not found then
    raise exception 'Join this group or page to change its notifications.'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.set_group_notifications(uuid, boolean) from public;
grant execute on function public.set_group_notifications(uuid, boolean)
  to authenticated;

create or replace function public.notify_new_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  original_owner uuid;
  group_kind text;
begin
  if new.group_id is null then
    insert into public.notifications (user_id, actor_id, type, post_id)
    select f.follower_id, new.user_id, 'friend_post', new.id
    from public.follows f
    where f.following_id = new.user_id and f.status = 'accepted'
      and not public.is_blocked_pair(f.follower_id, new.user_id);
  else
    select g.kind into group_kind from public.groups g where g.id = new.group_id;
    insert into public.notifications (user_id, actor_id, type, post_id, group_id)
    select m.user_id, new.user_id,
           case when group_kind = 'page' then 'page_post' else 'group_post' end,
           new.id, new.group_id
    from public.group_members m
    where m.group_id = new.group_id and m.user_id <> new.user_id
      and coalesce(m.notify, group_kind = 'page')
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
