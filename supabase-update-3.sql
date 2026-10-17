-- MotiveMap update 3: chat on each event
-- Run once in Supabase > SQL Editor after supabase-update-2.sql.

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  device_id text not null,
  name text not null,
  body text not null,
  is_host boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists comments_event_idx on public.comments (event_id, created_at);

-- No direct access: the site reads and writes only through the functions below,
-- so device ids stay private and invite-only chats need the event link.
alter table public.comments enable row level security;

create or replace function public.get_comments(p_event_id uuid, p_device text)
returns table (id uuid, name text, body text, is_host boolean, created_at timestamptz, mine boolean)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.name, c.body, c.is_host, c.created_at, c.device_id = p_device
  from comments c
  where c.event_id = p_event_id
  order by c.created_at asc
  limit 200;
$$;

create or replace function public.add_comment(p_event_id uuid, p_device text, p_name text, p_body text, p_token text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  v_name text := left(trim(coalesce(p_name, '')), 30);
  v_body text := trim(coalesce(p_body, ''));
begin
  if length(v_body) = 0 or length(v_body) > 280 then
    raise exception 'Messages must be 1-280 characters';
  end if;
  if length(v_name) = 0 then v_name := 'Someone'; end if;
  if p_device is null or length(p_device) < 8 then
    raise exception 'Missing device id';
  end if;
  if not exists (select 1 from events where id = p_event_id) then
    raise exception 'That event no longer exists';
  end if;
  if (select count(*) from comments where device_id = p_device and created_at > now() - interval '1 minute') >= 6 then
    raise exception 'Slow down a little';
  end if;

  insert into comments (event_id, device_id, name, body, is_host)
  values (p_event_id, p_device, v_name, v_body,
          p_token is not null and exists (select 1 from event_tokens t where t.event_id = p_event_id and t.token = p_token))
  returning id into new_id;
  return new_id;
end;
$$;

-- Delete your own message, or any message on an event you host.
create or replace function public.delete_comment(p_comment_id uuid, p_device text, p_token text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from comments c
  where c.id = p_comment_id
    and (c.device_id = p_device
         or (p_token is not null and exists (select 1 from event_tokens t where t.event_id = c.event_id and t.token = p_token)));
  return found;
end;
$$;

revoke all on function public.get_comments(uuid, text) from public;
revoke all on function public.add_comment(uuid, text, text, text, text) from public;
revoke all on function public.delete_comment(uuid, text, text) from public;
grant execute on function public.get_comments(uuid, text) to anon, authenticated;
grant execute on function public.add_comment(uuid, text, text, text, text) to anon, authenticated;
grant execute on function public.delete_comment(uuid, text, text) to anon, authenticated;
