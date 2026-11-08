-- Personal OS: encrypted per-user vault
-- Run this entire script in Supabase Dashboard > SQL Editor.

create table if not exists public.personal_os_vaults (
  user_id uuid primary key references auth.users (id) on delete cascade,
  encrypted_blob jsonb not null,
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.personal_os_vaults enable row level security;

-- Remove broad defaults, then grant only the operations needed by signed-in users.
revoke all on table public.personal_os_vaults from anon;
grant select, insert, update, delete on table public.personal_os_vaults to authenticated;

-- A signed-in user can access only their own encrypted vault row.
drop policy if exists "Users can read own Personal OS vault" on public.personal_os_vaults;
create policy "Users can read own Personal OS vault"
  on public.personal_os_vaults for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can create own Personal OS vault" on public.personal_os_vaults;
create policy "Users can create own Personal OS vault"
  on public.personal_os_vaults for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own Personal OS vault" on public.personal_os_vaults;
create policy "Users can update own Personal OS vault"
  on public.personal_os_vaults for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own Personal OS vault" on public.personal_os_vaults;
create policy "Users can delete own Personal OS vault"
  on public.personal_os_vaults for delete to authenticated
  using (auth.uid() = user_id);

-- Enable Realtime for this table (idempotent).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'personal_os_vaults'
     ) then
    execute 'alter publication supabase_realtime add table public.personal_os_vaults';
  end if;
end $$;
