-- قطب‌نما — جدول‌ها و زمان‌بندی اعلان صفحه قفل
-- این را یک بار در SQL Editor سوپابیس اجرا کن (Run).

-- کلیدهای اعلان: فقط تابع سرور می‌تواند بخواند (هیچ policy ندارد)
create table if not exists public.push_keys (
  id int primary key,
  pub text not null,
  priv text not null
);
alter table public.push_keys enable row level security;
revoke all on public.push_keys from anon, authenticated;

-- دستگاه‌هایی که اعلان روی صفحه قفل را روشن کرده‌اند
create table if not exists public.push_subs (
  endpoint text primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  p256dh text not null,
  auth text not null,
  origin text,
  device text,
  created_at timestamptz not null default now()
);
alter table public.push_subs enable row level security;
drop policy if exists "own push subs" on public.push_subs;
create policy "own push subs" on public.push_subs for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update, delete on public.push_subs to authenticated;

-- صف اعلان‌ها: فقط ساعت و متن کلی؛ متن واقعی یادآورها این‌جا نمی‌آید
create table if not exists public.push_queue (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id text not null,
  at timestamptz not null,
  title text,
  body text,
  hash text,
  sent boolean not null default false,
  primary key (user_id, id)
);
alter table public.push_queue enable row level security;
drop policy if exists "own push queue" on public.push_queue;
create policy "own push queue" on public.push_queue for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update, delete on public.push_queue to authenticated;
create index if not exists push_queue_due on public.push_queue (sent, at);

-- هر دقیقه تابع push را صدا بزن
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.unschedule('qutb-push') where exists (select 1 from cron.job where jobname = 'qutb-push');
select cron.schedule('qutb-push', '* * * * *', $$
  select net.http_post(
    url := 'https://znasigemhiuyutyrcdjj.supabase.co/functions/v1/push',
    body := '{"tick":1}'::jsonb,
    headers := '{"Content-Type":"application/json"}'::jsonb
  );
$$);
