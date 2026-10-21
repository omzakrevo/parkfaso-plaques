-- PARKFASO — colonnes d'immatriculation (version Supabase / PostgreSQL).
-- À exécuter uniquement si les sessions de stationnement sont aussi stockées dans Supabase.
-- Idempotent : peut être relancé sans risque.

alter table public.parking_sessions
  add column if not exists license_plate        text,
  add column if not exists plate_capture_method text not null default 'AUCUN'
    check (plate_capture_method in ('OCR', 'MANUEL', 'AUCUN')),
  add column if not exists plate_ocr_raw_text   text,
  add column if not exists plate_photo_path     text,
  add column if not exists plate_verified       boolean not null default false;

create index if not exists idx_parking_sessions_license_plate
  on public.parking_sessions (license_plate);

-- Le texte OCR brut et le chemin local de la photo sont des données temporaires :
-- elles ne sont pas utiles côté serveur. Ne les synchronisez pas, ou purgez-les :
-- update public.parking_sessions
--   set plate_ocr_raw_text = null, plate_photo_path = null
--   where created_at < now() - interval '7 days';
