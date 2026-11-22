-- Sykulven: multiplayer nickname leases
-- Kjør hele skriptet i Supabase Dashboard -> SQL Editor.
create table if not exists public.game_nickname_leases (
  nickname_key text primary key,
  nickname text not null,
  session_id uuid not null,
  updated_at timestamptz not null default now()
);
alter table public.game_nickname_leases enable row level security;
revoke all on public.game_nickname_leases from anon, authenticated;

create or replace function public.claim_game_nickname(p_nickname text, p_session_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := btrim(regexp_replace(p_nickname, '\s+', ' ', 'g'));
  v_key text := lower(btrim(regexp_replace(p_nickname, '\s+', ' ', 'g')));
  v_claimed text;
begin
  if length(v_name) < 3 or length(v_name) > 18
     or v_name !~ '^[[:alnum:]_ -]+$' then
    return false;
  end if;

  delete from public.game_nickname_leases
  where updated_at < now() - interval '45 seconds';

  insert into public.game_nickname_leases(nickname_key,nickname,session_id,updated_at)
  values(v_key,v_name,p_session_id,now())
  on conflict (nickname_key) do update
    set nickname=excluded.nickname,
        session_id=excluded.session_id,
        updated_at=now()
    where public.game_nickname_leases.session_id=excluded.session_id
       or public.game_nickname_leases.updated_at < now() - interval '45 seconds'
  returning nickname_key into v_claimed;

  return v_claimed is not null;
end;
$$;

create or replace function public.heartbeat_game_nickname(p_nickname text, p_session_id uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update public.game_nickname_leases
  set updated_at=now()
  where nickname_key=lower(btrim(regexp_replace(p_nickname, '\s+', ' ', 'g')))
    and session_id=p_session_id
  returning true;
$$;

create or replace function public.release_game_nickname(p_nickname text, p_session_id uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  delete from public.game_nickname_leases
  where nickname_key=lower(btrim(regexp_replace(p_nickname, '\s+', ' ', 'g')))
    and session_id=p_session_id
  returning true;
$$;

revoke all on function public.claim_game_nickname(text,uuid) from public;
revoke all on function public.heartbeat_game_nickname(text,uuid) from public;
revoke all on function public.release_game_nickname(text,uuid) from public;
grant execute on function public.claim_game_nickname(text,uuid) to anon, authenticated;
grant execute on function public.heartbeat_game_nickname(text,uuid) to anon, authenticated;
grant execute on function public.release_game_nickname(text,uuid) to anon, authenticated;

-- Realtime lobby uses a public channel. No database table is exposed to the browser.
