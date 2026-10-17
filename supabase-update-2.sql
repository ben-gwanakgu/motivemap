-- MotiveMap update 2: hosts can edit their own events
-- Run once in Supabase > SQL Editor after supabase-update-1.sql.

create or replace function public.update_event(p_event_id uuid, p_token text, p_event jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stops jsonb := coalesce(p_event->'stops', '[]'::jsonb);
  s jsonb;
begin
  if not exists (select 1 from event_tokens t where t.event_id = p_event_id and t.token = p_token) then
    raise exception 'Only the person who posted this event can edit it';
  end if;
  if coalesce(length(trim(p_event->>'title')), 0) = 0 or length(p_event->>'title') > 80 then
    raise exception 'Event name must be 1-80 characters';
  end if;
  if (p_event->>'lat')::float8 not between 54.70 and 54.85 or (p_event->>'lng')::float8 not between -1.70 and -1.45 then
    raise exception 'Location must be in Durham';
  end if;
  if jsonb_typeof(v_stops) <> 'array' or jsonb_array_length(v_stops) > 8 then
    raise exception 'A route can have at most 8 extra stops';
  end if;
  for s in select * from jsonb_array_elements(v_stops) loop
    if (s->>'lat')::float8 not between 54.70 and 54.85 or (s->>'lng')::float8 not between -1.70 and -1.45 then
      raise exception 'Location must be in Durham';
    end if;
    if (s->>'time')::timestamptz is null or length(coalesce(s->>'name', '')) > 80 then
      raise exception 'Each stop needs a time and a short name';
    end if;
  end loop;

  update events set
    title = trim(p_event->>'title'),
    category = case when p_event->>'category' in ('party','social','sport','society','other') then p_event->>'category' else 'other' end,
    start_at = (p_event->>'start_at')::timestamptz,
    end_at = nullif(p_event->>'end_at', '')::timestamptz,
    venue_name = left(p_event->>'venue_name', 120),
    address = left(p_event->>'address', 200),
    lat = (p_event->>'lat')::float8,
    lng = (p_event->>'lng')::float8,
    is_private = coalesce((p_event->>'is_private')::boolean, false),
    host = left(p_event->>'host', 60),
    price = left(p_event->>'price', 30),
    description = left(p_event->>'description', 280),
    visibility = case when p_event->>'visibility' = 'link' then 'link' else 'public' end,
    stops = v_stops
  where id = p_event_id;
  return found;
end;
$$;

revoke all on function public.update_event(uuid, text, jsonb) from public;
grant execute on function public.update_event(uuid, text, jsonb) to anon, authenticated;
