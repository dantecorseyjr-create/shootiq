-- DEPRECATED for app shot history.
-- Shot results (scores, feedback, local video paths) are saved on-device only.
-- Do not use this table for new video file storage.

-- ShootIQ shot history table (Step 7).

create table if not exists public.shots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  video_url text,
  analysis_video_url text,
  overall_score integer,
  elbow_alignment integer,
  knee_bend integer,
  balance integer,
  follow_through integer,
  issues jsonb not null default '[]'::jsonb,
  recommendations jsonb not null default '[]'::jsonb,
  shot_type text
);

create index if not exists shots_user_id_created_at_idx
  on public.shots (user_id, created_at desc);

alter table public.shots enable row level security;

create policy "Users can view own shots"
  on public.shots
  for select
  using (auth.uid() = user_id);

create policy "Users can insert own shots"
  on public.shots
  for insert
  with check (auth.uid() = user_id);

create policy "Users can update own shots"
  on public.shots
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own shots"
  on public.shots
  for delete
  using (auth.uid() = user_id);
