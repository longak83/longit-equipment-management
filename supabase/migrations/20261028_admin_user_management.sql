-- Admin user management security hardening.
-- Users may read their own role, but cannot grant themselves a role.
begin;

drop policy if exists "admins manage roles" on public.user_roles;
drop policy if exists "users read own profile" on public.profiles;
drop policy if exists "users update own profile" on public.profiles;

create policy "users read own role or admins read all"
  on public.user_roles for select to authenticated
  using (user_id = auth.uid() or public.current_user_role() = 'admin');

create policy "admins manage roles"
  on public.user_roles for all to authenticated
  using (public.current_user_role() = 'admin')
  with check (public.current_user_role() = 'admin');

create policy "users read own profile or admins read all"
  on public.profiles for select to authenticated
  using (id = auth.uid() or public.current_user_role() = 'admin');

create policy "users update own profile"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Keep service-role-only account creation in the Edge Function.
-- Never expose SUPABASE_SERVICE_ROLE_KEY in browser code.

commit;

-- One-time bootstrap for the first administrator (run manually in SQL Editor
-- after replacing the email with the intended administrator's verified Auth email):
-- insert into public.user_roles (user_id, role)
-- select id, 'admin' from auth.users where lower(email) = lower('admin@example.com')
-- on conflict (user_id) do update set role = 'admin';
