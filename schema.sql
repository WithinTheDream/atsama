-- =====================================================================
-- 0. EXTENSIONS
-- =====================================================================
create extension if not exists postgis;
create extension if not exists pgcrypto;

-- =====================================================================
-- 1. ENUMS
-- (urutan nilai verification_level penting: bisa dibandingkan dengan > / <)
-- =====================================================================
create type user_role             as enum ('wakif','nazhir','mitra_pelaksana','verifikator','admin');
create type account_status        as enum ('pending','aktif','ditangguhkan');
create type project_source        as enum ('internal','external');
create type project_category      as enum ('Konservasi & Kehutanan','Pengelolaan Sampah',
                                           'Energi Berkelanjutan','Pemberdayaan Masyarakat');
create type project_status        as enum ('draft','menunggu_kurasi','aktif','selesai','diarsipkan');
create type donation_status       as enum ('diniatkan','menunggu_verifikasi','dikonfirmasi_nazhir','ditolak');
create type verification_level    as enum ('dilaporkan_mitra','diverifikasi_internal','divalidasi_independen');
create type verification_decision as enum ('disetujui','perlu_revisi','ditolak');
create type evidence_type         as enum ('foto','dokumen','citra_satelit','lainnya');

-- =====================================================================
-- 2. USERS  (profil publik; autentikasi ditangani Supabase auth.users)
-- =====================================================================
create table users (
  id                uuid primary key references auth.users(id) on delete cascade,
  role              user_role      not null default 'wakif',
  account_status    account_status not null default 'aktif',  -- signup trigger: non-wakif => 'pending'
  full_name         text not null,
  email             text not null unique,
  phone             text,
  organization_name text,
  organization_url  text,
  avatar_url        text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint chk_org_required check (
    role not in ('nazhir','mitra_pelaksana','verifikator') or organization_name is not null)
);

-- Rekening tujuan transfer langsung (milik Nazhir)
create table nazhir_bank_accounts (
  id             uuid primary key default gen_random_uuid(),
  nazhir_id      uuid not null references users(id) on delete cascade,
  bank_name      text not null,
  account_number text not null,
  account_holder text not null,
  is_primary     boolean not null default false,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (nazhir_id, bank_name, account_number),
  unique (id, nazhir_id)                      -- target FK komposit dari donations
);
create unique index uq_nazhir_primary_account
  on nazhir_bank_accounts (nazhir_id) where is_primary;

-- =====================================================================
-- 3. PROJECTS
-- =====================================================================
create table projects (
  id              uuid primary key default gen_random_uuid(),
  source          project_source   not null default 'internal',
  nazhir_id       uuid not null references users(id),   -- penerima dana (internal & eksternal)
  mitra_id        uuid references users(id),            -- pelaksana lapangan
  curated_by      uuid references users(id),            -- admin yang menyetujui
  external_url    text,                                 -- wajib bila source = 'external'
  title           text not null,
  slug            text not null unique,
  summary         text,
  description     text,
  category        project_category not null,
  status          project_status   not null default 'draft',
  province        text,
  regency         text,
  location        geography(Point,4326),                -- titik pusat (marker Leaflet)
  area_geom       geography(MultiPolygon,4326),         -- area restorasi/lokasi (opsional)
  target_amount   numeric(18,2) not null check (target_amount > 0),   -- IDR
  start_date      date,
  end_date        date,
  cover_image_path text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, nazhir_id),                               -- target FK komposit dari donations
  constraint chk_external_url check (source = 'internal' or external_url is not null),
  constraint chk_dates        check (start_date is null or end_date is null or end_date >= start_date)
);
create index idx_projects_location on projects using gist (location);
create index idx_projects_area     on projects using gist (area_geom);
create index idx_projects_filter   on projects (status, category, province);
create index idx_projects_nazhir   on projects (nazhir_id);

-- =====================================================================
-- 4. PREFERENSI WAKIF (input AI Matching)
-- =====================================================================
create table wakif_preferences (
  id               uuid primary key default gen_random_uuid(),
  wakif_id         uuid not null references users(id) on delete cascade,
  categories       project_category[] not null default '{}',
  provinces        text[] not null default '{}',
  home_location    geography(Point,4326),
  max_distance_km  integer check (max_distance_km > 0),
  budget_min       numeric(18,2),
  budget_max       numeric(18,2),
  impact_statement text,                                 -- kepedulian wakif dalam teks bebas (untuk LLM)
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint chk_budget check (budget_min is null or budget_max is null or budget_max >= budget_min)
);

-- =====================================================================
-- 5. DONATIONS  (platform tidak memegang dana; ini hanya pencatatan niat & konfirmasi)
-- =====================================================================
create table donations (
  id                     uuid primary key default gen_random_uuid(),
  reference_code         text not null unique,           -- mis. ATS-260101-A1B2C3 (dibuat server)
  wakif_id               uuid not null references users(id),
  project_id             uuid not null,
  nazhir_id              uuid not null,
  nazhir_bank_account_id uuid not null,
  amount                 numeric(18,2) not null check (amount > 0),
  status                 donation_status not null default 'diniatkan',
  is_anonymous           boolean not null default false,
  niat_note              text,
  transfer_proof_path    text,                           -- Storage: transfer-proofs
  transferred_at         timestamptz,
  confirmed_by           uuid references users(id),
  confirmed_at           timestamptz,
  rejected_reason        text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  -- nazhir_id otomatis harus sama dengan nazhir proyek & pemilik rekening
  foreign key (project_id, nazhir_id)
    references projects (id, nazhir_id) on update restrict,
  foreign key (nazhir_bank_account_id, nazhir_id)
    references nazhir_bank_accounts (id, nazhir_id),
  constraint chk_proof     check (status not in ('menunggu_verifikasi','dikonfirmasi_nazhir')
                                  or transfer_proof_path is not null),
  constraint chk_confirmed check (status <> 'dikonfirmasi_nazhir'
                                  or (confirmed_by is not null and confirmed_at is not null)),
  constraint chk_rejected  check (status <> 'ditolak' or rejected_reason is not null)
);
create index idx_donations_wakif   on donations (wakif_id, status);
create index idx_donations_project on donations (project_id, status);
create index idx_donations_nazhir  on donations (nazhir_id, status);

-- =====================================================================
-- 6. FINANCIAL TRACKING: BUDGETS (rencana) & FUND_USAGES (realisasi)
-- =====================================================================
create table budgets (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references projects(id) on delete cascade,
  line_item      text not null,                          -- mis. 'Bibit', 'Upah tanam', 'Monitoring'
  description    text,
  planned_amount numeric(18,2) not null check (planned_amount >= 0),
  created_by     uuid references users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (id, project_id)
);

create table fund_usages (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references projects(id) on delete cascade,
  budget_id    uuid,                                     -- boleh null = belanja di luar pos anggaran
  amount       numeric(18,2) not null check (amount > 0),
  usage_date   date not null,
  description  text not null,
  receipt_path text,                                     -- Storage: receipts
  recorded_by  uuid not null references users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  foreign key (budget_id, project_id) references budgets (id, project_id)
);
create index idx_fund_usages_project on fund_usages (project_id, usage_date);

-- =====================================================================
-- 7. IMPACT TRACKING
-- =====================================================================
create table impact_indicators (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references projects(id) on delete cascade,
  standard_code      text,                               -- mis. TREES_PLANTED, CO2E_REDUCED_TON, WASTE_DIVERTED_KG
  name               text not null,
  unit               text not null,
  baseline_value     numeric(18,2) not null default 0,
  target_value       numeric(18,2) not null check (target_value > 0),
  measurement_method text,
  created_at         timestamptz not null default now(),
  unique (id, project_id),
  unique (project_id, name)
);

-- Satu baris = satu pengukuran satu indikator untuk satu periode (nilai inkremental periode tsb)
create table impact_reports (
  id                   uuid primary key default gen_random_uuid(),
  project_id           uuid not null references projects(id) on delete cascade,
  indicator_id         uuid not null,
  reported_by          uuid not null references users(id),
  period_start         date not null,
  period_end           date not null,
  reported_value       numeric(18,2) not null check (reported_value >= 0),
  narrative            text,
  measurement_location geography(Point,4326),
  verification_level   verification_level not null default 'dilaporkan_mitra',
  report_state         text not null default 'aktif'
                         check (report_state in ('aktif','perlu_revisi','ditolak')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  foreign key (indicator_id, project_id) references impact_indicators (id, project_id),
  constraint chk_period check (period_end >= period_start)
);
create index idx_reports_project   on impact_reports (project_id, verification_level);
create index idx_reports_indicator on impact_reports (indicator_id);

create table report_evidences (
  id               uuid primary key default gen_random_uuid(),
  report_id        uuid not null references impact_reports(id) on delete cascade,
  evidence_type    evidence_type not null default 'foto',
  file_path        text not null,                        -- Storage: evidences
  caption          text,
  captured_at      timestamptz,
  capture_location geography(Point,4326),                -- geotag foto
  uploaded_by      uuid not null references users(id),
  created_at       timestamptz not null default now()
);
create index idx_evidences_report on report_evidences (report_id);

-- Log keputusan verifikasi (riwayat lengkap; level di impact_reports = level tertinggi yang berlaku)
create table verifications (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references impact_reports(id) on delete cascade,
  verifier_id   uuid not null references users(id),
  level         verification_level not null
                  check (level in ('diverifikasi_internal','divalidasi_independen')),
  decision      verification_decision not null,
  notes         text,
  document_path text,                                    -- berita acara / laporan kunjungan lapangan
  is_current    boolean not null default true,           -- false bila laporan diedit setelah diverifikasi
  verified_at   timestamptz not null default now()
);
create unique index uq_verification_approved
  on verifications (report_id, level) where decision = 'disetujui' and is_current;
create index idx_verifications_report on verifications (report_id);

-- =====================================================================
-- 8. PENDUKUNG AI MATCHING (audit)
-- =====================================================================
create table ai_match_logs (
  id                    uuid primary key default gen_random_uuid(),
  wakif_id              uuid not null references users(id) on delete cascade,
  preference_id         uuid references wakif_preferences(id) on delete set null,
  filter_params         jsonb not null,                  -- parameter rule-based yang dipakai
  candidate_project_ids uuid[] not null,                 -- hasil tahap 1 (rule-based)
  llm_model             text,                            -- null = fallback tanpa LLM
  ranked_results        jsonb,                           -- [{project_id, rank, reason}]
  created_at            timestamptz not null default now()
);
create index idx_match_logs_wakif on ai_match_logs (wakif_id, created_at desc);

-- =====================================================================
-- 9. TRIGGERS & ATURAN BISNIS
-- =====================================================================

-- updated_at otomatis
create or replace function fn_set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$ declare t text; begin
  foreach t in array array['users','projects','wakif_preferences','donations',
                           'budgets','fund_usages','impact_reports'] loop
    execute format('create trigger trg_%s_updated before update on %I
                    for each row execute function fn_set_updated_at()', t, t);
  end loop;
end $$;

-- ---------- Transisi status donasi ----------
create or replace function fn_donation_status_guard() returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'diniatkan'           and new.status = 'menunggu_verifikasi') or
      (old.status = 'menunggu_verifikasi' and new.status in ('dikonfirmasi_nazhir','ditolak')) or
      (old.status = 'ditolak'             and new.status = 'menunggu_verifikasi')   -- unggah ulang bukti
    ) then
      raise exception 'Transisi status donasi tidak valid: % -> %', old.status, new.status;
    end if;
  end if;
  return new;
end $$;
create trigger trg_donation_status_guard before update on donations
  for each row execute function fn_donation_status_guard();

-- ---------- Verifikasi: cek peran & urutan level ----------
create or replace function fn_verification_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_role user_role;
begin
  select role into v_role from users where id = new.verifier_id;

  if new.level = 'diverifikasi_internal' and v_role <> 'admin' then
    raise exception 'Verifikasi internal hanya boleh dilakukan Admin';
  end if;

  if new.level = 'divalidasi_independen' then
    if v_role <> 'verifikator' then
      raise exception 'Validasi independen hanya boleh dilakukan Verifikator';
    end if;
    if not exists (select 1 from verifications
                   where report_id = new.report_id and level = 'diverifikasi_internal'
                     and decision = 'disetujui' and is_current) then
      raise exception 'Validasi independen memerlukan verifikasi internal yang disetujui';
    end if;
  end if;
  return new;
end $$;
create trigger trg_verification_guard before insert on verifications
  for each row execute function fn_verification_guard();

-- ---------- Terapkan keputusan ke impact_reports ----------
create or replace function fn_verification_apply() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.decision = 'disetujui' then
    update impact_reports
       set verification_level = new.level, report_state = 'aktif'
     where id = new.report_id;
  else
    update impact_reports
       set report_state = case new.decision when 'ditolak' then 'ditolak' else 'perlu_revisi' end
     where id = new.report_id;
  end if;
  return new;
end $$;
create trigger trg_verification_apply after insert on verifications
  for each row execute function fn_verification_apply();

-- ---------- Edit laporan = reset verifikasi ----------
create or replace function fn_report_reset_on_edit() returns trigger language plpgsql as $$
begin
  if (new.reported_value, new.period_start, new.period_end, new.indicator_id)
     is distinct from (old.reported_value, old.period_start, old.period_end, old.indicator_id) then
    new.verification_level := 'dilaporkan_mitra';
    new.report_state       := 'aktif';
    update verifications set is_current = false where report_id = old.id and is_current;
  end if;
  return new;
end $$;
create trigger trg_report_reset_on_edit before update on impact_reports
  for each row execute function fn_report_reset_on_edit();

-- =====================================================================
-- 10. VIEW: FUNDING, PORTFOLIO & MATCHING FUNCTION
-- =====================================================================

-- Agregat pendanaan per proyek (publik, hanya agregat; sengaja BUKAN security_invoker)
create view v_project_funding as
select p.id as project_id,
       p.target_amount,
       coalesce(sum(d.amount) filter (where d.status = 'dikonfirmasi_nazhir'), 0)                      as confirmed_amount,
       coalesce(sum(d.amount) filter (where d.status in ('diniatkan','menunggu_verifikasi')), 0)       as pending_amount,
       coalesce((select sum(f.amount) from fund_usages f where f.project_id = p.id), 0)               as spent_amount,
       greatest(p.target_amount - coalesce(sum(d.amount) filter (where d.status = 'dikonfirmasi_nazhir'), 0), 0)
                                                                                                       as remaining_target
from projects p
left join donations d on d.project_id = p.id
group by p.id;

-- Social Impact Portfolio: ringkasan (HANYA donasi dikonfirmasi_nazhir)
create view v_wakif_portfolio_summary with (security_invoker = true) as
select wakif_id,
       count(*)                  as total_donations,
       count(distinct project_id) as total_projects,
       count(distinct nazhir_id)  as total_nazhir,
       sum(amount)               as total_amount,
       min(confirmed_at)         as first_confirmed_at
from donations
where status = 'dikonfirmasi_nazhir'
group by wakif_id;

-- Social Impact Portfolio: dampak ter-atribusi pro-rata, dipisah per level verifikasi
create view v_wakif_portfolio_impact with (security_invoker = true) as
with mine as (
  select wakif_id, project_id, sum(amount) as wakif_amount
  from donations
  where status = 'dikonfirmasi_nazhir'
  group by wakif_id, project_id
)
select m.wakif_id, m.project_id,
       i.id as indicator_id, i.name as indicator_name, i.unit,
       r.verification_level,
       sum(r.reported_value) * (m.wakif_amount / nullif(pf.confirmed_amount, 0)) as attributed_value
from mine m
join v_project_funding pf on pf.project_id = m.project_id
join impact_reports r     on r.project_id = m.project_id and r.report_state = 'aktif'
join impact_indicators i  on i.id = r.indicator_id
group by m.wakif_id, m.project_id, i.id, i.name, i.unit,
         r.verification_level, m.wakif_amount, pf.confirmed_amount;

-- Tahap 1 AI Matching: filter rule-based
create or replace function match_candidate_projects(
  p_categories project_category[] default null,
  p_provinces  text[]             default null,
  p_lng        double precision   default null,
  p_lat        double precision   default null,
  p_max_km     integer            default null,
  p_budget_min numeric            default null,
  p_limit      integer            default 15
) returns table (
  project_id uuid, title text, category project_category, province text,
  remaining_target numeric, distance_km double precision
) language sql stable as $$
  select p.id, p.title, p.category, p.province, pf.remaining_target,
         case when p_lng is not null and p_lat is not null and p.location is not null
              then st_distance(p.location, st_makepoint(p_lng, p_lat)::geography) / 1000 end
           as distance_km
  from projects p
  join v_project_funding pf on pf.project_id = p.id
  where p.status = 'aktif'
    and pf.remaining_target > 0
    and (p_categories is null or cardinality(p_categories) = 0 or p.category = any(p_categories))
    and (p_provinces  is null or cardinality(p_provinces)  = 0 or p.province = any(p_provinces))
    and (p_max_km is null or p_lng is null
         or st_dwithin(p.location, st_makepoint(p_lng, p_lat)::geography, p_max_km * 1000))
    and (p_budget_min is null or pf.remaining_target >= p_budget_min)
  order by distance_km nulls last, pf.remaining_target desc
  limit p_limit;
$$;

-- =====================================================================
-- 11. ROW LEVEL SECURITY (RLS)
-- =====================================================================

create or replace function auth_role() returns user_role
language sql stable security definer set search_path = public as
$$ select role from users where id = auth.uid() $$;

alter table users               enable row level security;
alter table nazhir_bank_accounts enable row level security;
alter table wakif_preferences   enable row level security;
alter table projects            enable row level security;
alter table donations           enable row level security;
alter table budgets             enable row level security;
alter table fund_usages         enable row level security;
alter table impact_indicators   enable row level security;
alter table impact_reports      enable row level security;
alter table report_evidences    enable row level security;
alter table verifications       enable row level security;
alter table ai_match_logs       enable row level security;

-- Pengguna tidak boleh menaikkan role/status dirinya sendiri
create policy users_update_self on users for update
  using (id = auth.uid())
  with check (id = auth.uid() and role = auth_role());

-- Proyek aktif terbuka untuk publik (marketplace)
create policy projects_public_read on projects for select
  using (status in ('aktif','selesai') or nazhir_id = auth.uid()
         or mitra_id = auth.uid() or auth_role() = 'admin');

-- Wakif: buat donasi hanya untuk proyek aktif, dan hanya ajukan bukti
create policy donations_wakif_insert on donations for insert
  with check (wakif_id = auth.uid() and status = 'diniatkan'
              and exists (select 1 from projects p where p.id = project_id and p.status = 'aktif'));
create policy donations_wakif_submit on donations for update
  using      (wakif_id = auth.uid() and status in ('diniatkan','ditolak'))
  with check (wakif_id = auth.uid() and status = 'menunggu_verifikasi');
create policy donations_wakif_read on donations for select
  using (wakif_id = auth.uid());

-- Nazhir: hanya donasi proyeknya yang sedang menunggu verifikasi
create policy donations_nazhir_read on donations for select using (nazhir_id = auth.uid());
create policy donations_nazhir_decide on donations for update
  using      (nazhir_id = auth.uid() and status = 'menunggu_verifikasi')
  with check (nazhir_id = auth.uid() and status in ('dikonfirmasi_nazhir','ditolak'));

-- Laporan dampak: Mitra pada proyeknya, hanya saat belum diverifikasi atau diminta revisi
create policy reports_mitra_write on impact_reports for update
  using (reported_by = auth.uid()
         and (verification_level = 'dilaporkan_mitra' or report_state = 'perlu_revisi'));
