-- MEDIVO Step 2 / 005: connect the three demo accounts to the demo tenant.
-- First create the users in the Supabase dashboard.
-- Re-running is safe.

insert into public.profiles (id, tenant_id, full_name, role)
select u.id, '11111111-1111-1111-1111-111111111111', v.full_name, v.role::public.user_role
  from auth.users u
  join (values
    ('pharmacist@medivo.test', 'Nusrat Jahan', 'pharmacist'),
    ('purchaser@medivo.test', 'Imran Hossain', 'purchaser'),
    ('manager@medivo.test', 'Rahim Uddin', 'branch_manager')
  ) v(email, full_name, role) on v.email = u.email
on conflict (id) do update
  set tenant_id = excluded.tenant_id, full_name = excluded.full_name, role = excluded.role, active = true;

select p.full_name, p.role, u.email
  from public.profiles p join auth.users u on u.id = p.id
 order by p.role;