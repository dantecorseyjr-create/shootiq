-- Enrich shots history for 18Birdies-style coaching payloads.

alter table if exists public.shots
  add column if not exists breakdown jsonb not null default '[]'::jsonb;

alter table if exists public.shots
  add column if not exists timeline jsonb not null default '[]'::jsonb;

alter table if exists public.shots
  add column if not exists improvement_summary text;
