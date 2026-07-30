-- DEPRECATED for basketball video storage.
-- The Flutter app no longer writes shot videos or analysis rows here.
-- Videos stay on-device; Supabase is auth / profiles / subscription only.
-- Kept for older environments; do not provision new video buckets from this.

-- ShootIQ shot analysis table + storage bucket foundation.

create table if not exists public.shot_analysis (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  video_url text,
  overall_score integer,
  release_score integer,
  arc_score integer,
  elbow_score integer,
  balance_score integer,
  follow_through_score integer,
  created_at timestamptz not null default now()
);

create index if not exists shot_analysis_user_id_created_at_idx
  on public.shot_analysis (user_id, created_at desc);

alter table public.shot_analysis enable row level security;

create policy "Users can view own shot analyses"
  on public.shot_analysis
  for select
  using (auth.uid() = user_id);

create policy "Users can insert own shot analyses"
  on public.shot_analysis
  for insert
  with check (auth.uid() = user_id);

create policy "Users can update own shot analyses"
  on public.shot_analysis
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own shot analyses"
  on public.shot_analysis
  for delete
  using (auth.uid() = user_id);

-- Storage bucket for shot videos.
insert into storage.buckets (id, name, public)
values ('shot-videos', 'shot-videos', true)
on conflict (id) do nothing;

-- Path layout: users/{user_id}/shots/{filename}
create policy "Users can upload own shot videos"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'shot-videos'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "Users can read own shot videos"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'shot-videos'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "Public can read shot videos"
  on storage.objects
  for select
  to public
  using (bucket_id = 'shot-videos');

create policy "Users can delete own shot videos"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'shot-videos'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
