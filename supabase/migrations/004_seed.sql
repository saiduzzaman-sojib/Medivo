-- MEDIVO Step 2 / 004: demo data (same story as the approved prototype).
-- Safe to run once. Uses fixed ids so the tests can find the demo plan.

insert into public.tenants (id, name)
values ('11111111-1111-1111-1111-111111111111', 'Dhanmondi Pharmacy Chain')
on conflict (id) do nothing;

insert into public.branches (tenant_id, name)
select '11111111-1111-1111-1111-111111111111', n
  from (values ('Dhanmondi'), ('Uttara'), ('Mirpur'), ('Gulshan')) v(n)
on conflict (tenant_id, name) do nothing;

insert into public.medicines (tenant_id, product_code, name, pack_size, unit_price, lead_time_days)
select '11111111-1111-1111-1111-111111111111', code, name, pack, price, lead
  from (values
    ('NAPA500', 'Napa 500mg', 100, 1.20, 3),
    ('SECLO20', 'Seclo 20mg', 30, 6.00, 5),
    ('ACE100', 'Ace 100ml', 12, 38.00, 4),
    ('ORS', 'ORS sachet', 50, 12.00, 2),
    ('MONT10', 'Montair 10mg', 30, 14.00, 4),
    ('AZI500', 'Azithro 500mg', 6, 35.00, 6)
  ) v(code, name, pack, price, lead)
on conflict (tenant_id, product_code) do nothing;

-- Batches (one is already expired on purpose, so the expiry trigger is paused here only).
alter table public.batches disable trigger batches_check_insert_trg;
insert into public.batches (tenant_id, medicine_id, branch_id, batch_code, quantity, expires_on)
select '11111111-1111-1111-1111-111111111111', m.id, b.id, v.code, v.qty, current_date + v.days
  from (values
    ('B-2291', 'NAPA500', 'Uttara', 1200, 12), ('B-2292', 'NAPA500', 'Uttara', 600, 140),
    ('B-2293', 'NAPA500', 'Mirpur', 150, 90), ('B-2294', 'NAPA500', 'Dhanmondi', 500, 70),
    ('B-2295', 'NAPA500', 'Gulshan', 400, -3),
    ('B-1877', 'SECLO20', 'Mirpur', 500, 41), ('B-1878', 'SECLO20', 'Dhanmondi', 120, 200),
    ('B-1879', 'SECLO20', 'Gulshan', 60, 160),
    ('B-3302', 'ACE100', 'Gulshan', 350, 18), ('B-3303', 'ACE100', 'Dhanmondi', 40, 120),
    ('B-4410', 'ORS', 'Dhanmondi', 300, 25), ('B-4411', 'ORS', 'Uttara', 120, 100),
    ('B-4412', 'ORS', 'Mirpur', 60, 80),
    ('B-5510', 'MONT10', 'Uttara', 200, 55), ('B-5511', 'MONT10', 'Mirpur', 90, 120),
    ('B-5512', 'MONT10', 'Dhanmondi', 150, 150),
    ('B-6001', 'AZI500', 'Gulshan', 90, 30), ('B-6002', 'AZI500', 'Dhanmondi', 40, 60)
  ) v(code, mcode, bname, qty, days)
  join public.medicines m on m.tenant_id = '11111111-1111-1111-1111-111111111111' and m.product_code = v.mcode
  join public.branches b on b.tenant_id = '11111111-1111-1111-1111-111111111111' and b.name = v.bname
on conflict (tenant_id, batch_code) do nothing;
alter table public.batches enable trigger batches_check_insert_trg;

-- 60 days of sales per medicine and branch. Stockout, promotion and return days are flagged.
insert into public.medicine_sales (tenant_id, medicine_id, branch_id, day, quantity, flag)
select '11111111-1111-1111-1111-111111111111', m.id, b.id, current_date - (60 - d),
       case
         when (mb.mcode, bk.bname, d) in (('ACE100', 'Gulshan', 40), ('ACE100', 'Gulshan', 41), ('ACE100', 'Gulshan', 47)) then 0
         when (mb.mcode, bk.bname, d) in (('NAPA500', 'Uttara', 50)) then round(x.q * 1.7)::int
         when (mb.mcode, bk.bname, d) in (('NAPA500', 'Uttara', 51)) then round(x.q * 1.6)::int
         when (mb.mcode, bk.bname, d) in (('ORS', 'Mirpur', 44)) then round(x.q * 1.8)::int
         else x.q
       end,
       case
         when (mb.mcode, bk.bname, d) in (('ACE100', 'Gulshan', 40), ('ACE100', 'Gulshan', 41), ('ACE100', 'Gulshan', 47)) then 'stockout'::public.sales_flag
         when (mb.mcode, bk.bname, d) in (('NAPA500', 'Uttara', 50), ('NAPA500', 'Uttara', 51), ('ORS', 'Mirpur', 44)) then 'promotion'::public.sales_flag
         else 'routine'::public.sales_flag
       end
  from (values ('NAPA500', 55), ('SECLO20', 14), ('ACE100', 6), ('ORS', 18), ('MONT10', 9), ('AZI500', 5)) mb(mcode, base)
  join public.medicines m on m.tenant_id = '11111111-1111-1111-1111-111111111111' and m.product_code = mb.mcode
  cross join (values ('Dhanmondi', 1.0), ('Uttara', 0.8), ('Mirpur', 1.2), ('Gulshan', 0.7)) bk(bname, k)
  join public.branches b on b.tenant_id = '11111111-1111-1111-1111-111111111111' and b.name = bk.bname
  cross join generate_series(0, 59) d
  cross join lateral (
    select greatest(0, round(
      mb.base * bk.k * (1 + 0.28 * sin(2 * pi() * d / 7.0 + 1)) * (1 + d / 600.0)
      + (((d * 7919 + length(mb.mcode) * 104729 + length(bk.bname) * 1299709) % 1000) / 1000.0 - 0.5) * mb.base * 0.25
    ))::int as q
  ) x
on conflict (tenant_id, medicine_id, branch_id, day, flag) do nothing;

insert into public.medicine_sales (tenant_id, medicine_id, branch_id, day, quantity, flag)
select '11111111-1111-1111-1111-111111111111', m.id, b.id, current_date - 8, 6, 'return'
  from public.medicines m, public.branches b
 where m.tenant_id = '11111111-1111-1111-1111-111111111111' and m.product_code = 'SECLO20'
   and b.tenant_id = '11111111-1111-1111-1111-111111111111' and b.name = 'Dhanmondi'
on conflict (tenant_id, medicine_id, branch_id, day, flag) do nothing;

-- One demo forecast run, one draft plan and two proposed transfers.
insert into public.forecast_runs (id, tenant_id, medicine_id, branch_id, horizon_days, source, model_version, input_hash, status)
select '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', m.id, b.id,
       14, 'baseline', 'seasonal-naive-1.0', 'seed-run', 'succeeded'
  from public.medicines m, public.branches b
 where m.tenant_id = '11111111-1111-1111-1111-111111111111' and m.product_code = 'NAPA500'
   and b.tenant_id = '11111111-1111-1111-1111-111111111111' and b.name = 'Uttara'
on conflict (id) do nothing;

insert into public.stock_plans (id, tenant_id, forecast_run_id, moves, orders)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        '[{"note":"demo moves, see transfers"}]'::jsonb, '[{"note":"demo orders"}]'::jsonb)
on conflict (id) do nothing;

insert into public.transfers (tenant_id, plan_id, medicine_id, batch_id, from_branch_id, to_branch_id, quantity)
select '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333',
       m.id, ba.id, fb.id, tb.id, v.qty
  from (values
    ('NAPA500', 'B-2291', 'Uttara', 'Mirpur', 200),
    ('ACE100', 'B-3302', 'Gulshan', 'Dhanmondi', 60)
  ) v(mcode, bcode, fromb, tob, qty)
  join public.medicines m on m.tenant_id = '11111111-1111-1111-1111-111111111111' and m.product_code = v.mcode
  join public.batches ba on ba.tenant_id = '11111111-1111-1111-1111-111111111111' and ba.batch_code = v.bcode
  join public.branches fb on fb.tenant_id = '11111111-1111-1111-1111-111111111111' and fb.name = v.fromb
  join public.branches tb on tb.tenant_id = '11111111-1111-1111-1111-111111111111' and tb.name = v.tob
 where not exists (
   select 1 from public.transfers t where t.plan_id = '33333333-3333-3333-3333-333333333333'
 );