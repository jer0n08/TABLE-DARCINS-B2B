-- Authorize the confirmed account email, independently of an OAuth provider.
-- Keep the private allowlist and all existing RLS policies in force.
create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from auth.users u
    join private.authorized_emails a on a.email = lower(u.email)
    where u.id = auth.uid()
      and u.email_confirmed_at is not null
      and not coalesce(u.is_anonymous, false)
  );
$$;
revoke all on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated;
