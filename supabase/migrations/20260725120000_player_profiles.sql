-- Player profiles: one row per authenticated user.

create table if not exists public.player_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  first_name text not null default '',
  last_name text not null default '',
  username text not null default '',
  height text,
  weight integer,
  age integer,
  dominant_hand text,
  position text,
  skill_level text,
  experience integer,
  favorite_team text,
  bio text,
  photo_url text,
  updated_at timestamptz not null default now()
);

create index if not exists player_profiles_user_id_idx
  on public.player_profiles (user_id);

alter table public.player_profiles enable row level security;

drop policy if exists "Users can view own player profile" on public.player_profiles;
create policy "Users can view own player profile"
  on public.player_profiles
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own player profile" on public.player_profiles;
create policy "Users can insert own player profile"
  on public.player_profiles
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own player profile" on public.player_profiles;
create policy "Users can update own player profile"
  on public.player_profiles
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own player profile" on public.player_profiles;
create policy "Users can delete own player profile"
  on public.player_profiles
  for delete
  using (auth.uid() = user_id);

-- Allow avatar upserts under users/{uid}/avatar/ in the existing public bucket.
drop policy if exists "Users can update own shot videos" on storage.objects;
create policy "Users can update own shot videos"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'shot-videos'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  )
  with check (
    bucket_id = 'shot-videos'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
