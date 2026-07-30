-- ShootIQ Step 7: progress metrics + extensible historical metrics blob.

alter table public.shots
  add column if not exists release_point integer;

alter table public.shots
  add column if not exists pose_data_url text;

-- Future-proof bag for additional metrics without schema churn.
alter table public.shots
  add column if not exists metrics_json jsonb not null default '{}'::jsonb;

comment on column public.shots.release_point is 'Release Position biomechanics score 0-100';
comment on column public.shots.pose_data_url is 'URL/path to pose_data.json for this analysis';
comment on column public.shots.metrics_json is 'Extensible historical metrics map (new keys OK)';

create index if not exists shots_user_created_idx
  on public.shots (user_id, created_at desc);
