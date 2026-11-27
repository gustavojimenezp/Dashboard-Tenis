-- =====================================================================
-- Copa Gigante del Hogar · Edición completa desde el modo organizador
-- Ejecuta este archivo UNA vez en Supabase → SQL Editor → New query → Run.
-- Requiere la función public.es_organizador() que ya usa la página.
-- =====================================================================

-- 1) Tabla de configuración: datos del torneo, grupos, premios, textos,
--    fotos y PDF. Cada fila es una sección (clave) con su valor en JSON.
create table if not exists public.config (
  clave       text primary key,
  valor       jsonb not null,
  actualizado timestamptz not null default now()
);

alter table public.config enable row level security;

drop policy if exists "config: lectura publica" on public.config;
create policy "config: lectura publica" on public.config
  for select using (true);

drop policy if exists "config: organizadores escriben" on public.config;
create policy "config: organizadores escriben" on public.config
  for all to authenticated
  using (public.es_organizador())
  with check (public.es_organizador());

-- Fecha de última edición
create or replace function public.config_tocar() returns trigger
language plpgsql as $$ begin new.actualizado := now(); return new; end $$;
drop trigger if exists config_tocar on public.config;
create trigger config_tocar before insert or update on public.config
  for each row execute function public.config_tocar();

-- Cambios en vivo para todos los visitantes
do $$ begin
  alter publication supabase_realtime add table public.config;
exception when duplicate_object then null; end $$;

-- 2) Espacio público "archivos" para subir fotos, logos y PDF
insert into storage.buckets (id, name, public)
values ('archivos', 'archivos', true)
on conflict (id) do update set public = true;

drop policy if exists "archivos: lectura publica" on storage.objects;
create policy "archivos: lectura publica" on storage.objects
  for select using (bucket_id = 'archivos');

drop policy if exists "archivos: organizadores suben" on storage.objects;
create policy "archivos: organizadores suben" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'archivos' and public.es_organizador());

drop policy if exists "archivos: organizadores editan" on storage.objects;
create policy "archivos: organizadores editan" on storage.objects
  for update to authenticated
  using (bucket_id = 'archivos' and public.es_organizador());

drop policy if exists "archivos: organizadores borran" on storage.objects;
create policy "archivos: organizadores borran" on storage.objects
  for delete to authenticated
  using (bucket_id = 'archivos' and public.es_organizador());

-- 3) Marcadores de fase final: se guardan en "resultados" con grupo = 0
--    y clave = 'P<id del partido en programacion>'. Si tu tabla tiene una
--    restricción que exige grupo >= 1, quítala o ajústala, por ejemplo:
--    alter table public.resultados drop constraint if exists resultados_grupo_check;
