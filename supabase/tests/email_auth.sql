-- All fixtures and changes are rolled back; no emails are sent.
begin;
do $$
declare test_user uuid := gen_random_uuid();
begin
  insert into auth.users(id, email, raw_user_meta_data)
  values(test_user, 'email-auth-test@example.invalid', '{"email_verified":true}');
  insert into private.authorized_emails(email) values('email-auth-test@example.invalid');
  perform set_config('request.jwt.claim.sub', test_user::text, true);
  if public.has_dashboard_access() then raise exception 'Unconfirmed email accepted'; end if;
  update auth.users set email_confirmed_at = now() where id = test_user;
  if not public.has_dashboard_access() then raise exception 'Confirmed allowed email without Google rejected'; end if;
  update auth.users set is_anonymous = true where id = test_user;
  if public.has_dashboard_access() then raise exception 'Anonymous account accepted'; end if;
  update auth.users set is_anonymous = false, email = 'other-email-auth-test@example.invalid',
    raw_user_meta_data = '{"email":"email-auth-test@example.invalid","email_verified":true}'
    where id = test_user;
  if public.has_dashboard_access() then raise exception 'Non-allowed email or forged metadata accepted'; end if;
  perform set_config('request.jwt.claim.sub', '', true);
  if public.has_dashboard_access() then raise exception 'Missing session accepted'; end if;
end;
$$;
select 'PASS: confirmed allowlisted email, unconfirmed denial, anonymous denial, other email denial, metadata spoofing denial, missing session denial' as result;
rollback;
