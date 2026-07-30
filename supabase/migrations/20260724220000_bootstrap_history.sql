-- One-shot bootstrap for ShootIQ history + storage.
-- Paste into Supabase → SQL Editor → Run if History/cloud save is broken.

create table if not exists public.shots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  video_url text,
  analysis_video_url text,
  skeleton_video_url text,
  slow_motion_video_url text,
  original_video_url text,
  overall_score integer,
  elbow_alignment integer,
  knee_bend integer,
  balance integer,
  follow_through integer,
  issues jsonb not null default '[]'::jsonb,
  recommendations jsonb not null default '[]'::jsonb,
  breakdown jsonb not null default '[]'::jsonb,
  timeline jsonb not null default '[]'::jsonb,
  improvement_summary text,
  shot_type text
);

create index if not exists shots_user_id_created_at_idx
  on public.shots (user_id, created_at desc);

alter table public.shots enable row level security;

drop policy if exists "Users can view own shots" on public.shots;
create policy "Users can view own shots"
  on public.shots for select using (auth.uid() = user_id);

drop policy if exists "Users can insert own shots" on public.shots;
create policy "Users can insert own shots"
  on public.shots for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own shots" on public.shots;
create policy "Users can update own shots"
  on public.shots for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can delete own shots" on public.shots;
create policy "Users can delete own shots"
  on public.shots for delete using (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
values ('shot-videos', 'shot-videos', true)
on conflict (id) do nothing;

drop policy if exists "Users can upload own shot videos" on storage.objects;
create policy "Users can upload own shot videos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'shot-videos'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "Public can read shot videos" on storage.objects;
create policy "Public can read shot videos"
  on storage.objects for select to public
  using (bucket_id = 'shot-videos');

drop policy if exists "Users can delete own shot videos" on storage.objects;
create policy "Users can delete own shot videos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'shot-videos'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
