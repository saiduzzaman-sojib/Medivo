-- MEDIVO Step 2 / 001: core schema
-- Every table carries tenant_id. Foreign keys are tenant-consistent: a row can
-- only point at rows of the SAME tenant (composite keys), so cross-tenant links
-- are impossible even for a privileged mistake.

create extension if not exists pgcrypto with schema extensions;

create type public.user_role as enum ('pharmacist', 'purchaser', 'branch_manager');
create type public.plan_state as enum ('draft', 'reviewed', 'approved', 'returned');
create type public.transfer_state as enum ('pending', 'approved', 'rejected');
create type public.sales_flag as enum ('routine', 'promotion', 'return', 'stockout');

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  require_mfa_for_recall boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id),
  full_name text not null,
  role public.user_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index profiles_tenant_idx on public.profiles (tenant_id);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  name text not null,
  created_at timestamptz not null default now(),
  unique (tenant_id, name),
  unique (tenant_id, id)
);

create table public.medicines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  product_code text not null,
  name text not null,
  pack_size integer not null check (pack_size > 0),
  unit_price numeric(12, 2) not null check (unit_price >= 0),
  lead_time_days integer not null default 3 check (lead_time_days >= 0),
  created_at timestamptz not null default now(),
  unique (tenant_id, product_code),
  unique (tenant_id, id)
);

create table public.batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  medicine_id uuid not null,
  branch_id uuid not null,
  batch_code text not null,
  quantity integer not null check (quantity >= 0),
  expires_on date not null,
  validated boolean not null default false,
  validated_by uuid references auth.users (id),
  recalled boolean not null default false,
  recalled_by uuid references auth.users (id),
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  version integer not null default 1,
  unique (tenant_id, batch_code),
  unique (tenant_id, id),
  foreign key (tenant_id, medicine_id) references public.medicines (tenant_id, id),
  foreign key (tenant_id, branch_id) references public.branches (tenant_id, id)
);
create index batches_lookup_idx on public.batches (tenant_id, branch_id, medicine_id);

create table public.sales_imports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  file_hash text not null,
  row_count integer not null check (row_count >= 0),
  imported_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  unique (tenant_id, file_hash),
  unique (tenant_id, id)
);

create table public.medicine_sales (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  medicine_id uuid not null,
  branch_id uuid not null,
  day date not null,
  quantity integer not null check (quantity >= 0),
  flag public.sales_flag not null default 'routine',
  import_id uuid,
  created_at timestamptz not null default now(),
  unique (tenant_id, medicine_id, branch_id, day, flag),
  foreign key (tenant_id, medicine_id) references public.medicines (tenant_id, id),
  foreign key (tenant_id, branch_id) references public.branches (tenant_id, id),
  foreign key (tenant_id, import_id) references public.sales_imports (tenant_id, id)
);
create index sales_lookup_idx on public.medicine_sales (tenant_id, medicine_id, branch_id, day desc);

create table public.forecast_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  medicine_id uuid not null,
  branch_id uuid not null,
  horizon_days integer not null check (horizon_days in (7, 14, 21)),
  source text not null check (source in ('model', 'baseline', 'manual')),
  model_version text not null,
  input_hash text not null,
  points jsonb not null default '[]'::jsonb,
  assumption text,
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed')),
  error_code text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  unique (tenant_id, input_hash),
  unique (tenant_id, id),
  foreign key (tenant_id, medicine_id) references public.medicines (tenant_id, id),
  foreign key (tenant_id, branch_id) references public.branches (tenant_id, id)
);

create table public.stock_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  forecast_run_id uuid,
  moves jsonb not null default '[]'::jsonb,
  orders jsonb not null default '[]'::jsonb,
  state public.plan_state not null default 'draft',
  reviewed_by uuid references auth.users (id),
  reviewed_version integer,
  approved_by uuid references auth.users (id),
  approved_at timestamptz,
  revision integer not null default 0,
  content_hash text,
  version integer not null default 1,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, forecast_run_id) references public.forecast_runs (tenant_id, id)
);

create table public.transfers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  plan_id uuid not null,
  medicine_id uuid not null,
  batch_id uuid not null,
  from_branch_id uuid not null,
  to_branch_id uuid not null,
  quantity integer not null check (quantity > 0),
  state public.transfer_state not null default 'pending',
  decided_by uuid references auth.users (id),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  check (from_branch_id <> to_branch_id),
  foreign key (tenant_id, plan_id) references public.stock_plans (tenant_id, id),
  foreign key (tenant_id, medicine_id) references public.medicines (tenant_id, id),
  foreign key (tenant_id, batch_id) references public.batches (tenant_id, id),
  foreign key (tenant_id, from_branch_id) references public.branches (tenant_id, id),
  foreign key (tenant_id, to_branch_id) references public.branches (tenant_id, id)
);
create index transfers_plan_idx on public.transfers (tenant_id, plan_id);

create table public.outcomes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  plan_id uuid not null,
  cycle_label text not null,
  baseline_cost numeric(14, 2) not null check (baseline_cost >= 0),
  plan_cost numeric(14, 2) not null check (plan_cost >= 0),
  recorded_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  unique (tenant_id, plan_id),
  foreign key (tenant_id, plan_id) references public.stock_plans (tenant_id, id)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants (id),
  actor_id uuid,
  actor_role public.user_role,
  action text not null,
  ok boolean not null default true,
  detail jsonb not null default '{}'::jsonb,
  prev_hash text not null,
  row_hash text not null,
  created_at timestamptz not null default now()
);
create index audit_tenant_idx on public.audit_log (tenant_id, id);

-- Business rules enforced in the database, not only in the app ------------

-- Expired stock can never be added (422 rule from the blueprint).
create or replace function public.batches_check_insert() returns trigger
language plpgsql as $$
begin
  if new.expires_on <= current_date then
    raise exception 'MEDIVO_422: expired stock cannot be added' using errcode = 'PT422';
  end if;
  return new;
end $$;
create trigger batches_check_insert_trg before insert on public.batches
  for each row execute function public.batches_check_insert();

-- Transfers: whole packs only, and never from an expired or recalled batch.
create or replace function public.transfers_check() returns trigger
language plpgsql as $$
declare
  v_pack integer;
  v_exp date;
  v_rec boolean;
begin
  select pack_size into v_pack from public.medicines
   where id = new.medicine_id and tenant_id = new.tenant_id;
  if v_pack is null or new.quantity % v_pack <> 0 then
    raise exception 'MEDIVO_422: transfer quantity must be whole packs' using errcode = 'PT422';
  end if;
  if tg_op = 'INSERT' then
    select expires_on, recalled into v_exp, v_rec from public.batches
     where id = new.batch_id and tenant_id = new.tenant_id;
    if v_exp is null or v_exp <= current_date or v_rec then
      raise exception 'MEDIVO_422: expired or recalled batches cannot be transferred' using errcode = 'PT422';
    end if;
  end if;
  return new;
end $$;
create trigger transfers_check_trg before insert or update on public.transfers
  for each row execute function public.transfers_check();