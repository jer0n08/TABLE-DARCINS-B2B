-- Initial schema. The applied migration is copied to migrations after deployment.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

create table private.authorized_emails (
  email text primary key check (email = lower(email)),
  created_at timestamptz not null default now()
);
alter table private.authorized_emails enable row level security;
insert into private.authorized_emails(email) values ('jerome.nguyen08@gmail.com');

-- An approved email must belong to a confirmed Google identity of this user.
create function private.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from auth.users u
    join auth.identities i on i.user_id = u.id and i.provider = 'google'
    join private.authorized_emails a on a.email = lower(u.email)
    where u.id = auth.uid() and u.email_confirmed_at is not null
      and lower(i.identity_data->>'email') = a.email
      and i.identity_data->>'email_verified' = 'true'
  );
$$;
revoke all on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated;
create function public.has_dashboard_access() returns boolean language sql stable security invoker set search_path = '' as $$ select private.is_admin(); $$;
revoke all on function public.has_dashboard_access() from public, anon;
grant execute on function public.has_dashboard_access() to authenticated;

create table public.prospects (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 200),
  siret text unique check (siret ~ '^[0-9]{14}$'),
  address text, city text, postal_code text, activity_code text,
  employee_band text, employee_year integer check (employee_year between 1900 and 2200),
  website text, source_url text, source_checked_at timestamptz,
  contact_name text, contact_role text, email text, phone text, contact_source_url text,
  status text not null default 'new' check (status in ('new','to_contact','contacted','replied','interested','booked','declined','do_not_contact')),
  notes text not null default '' check (length(notes) <= 20000),
  next_follow_up date, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index prospects_status_followup on public.prospects(status, next_follow_up);
create index prospects_created_at on public.prospects(created_at desc);
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  prospect_id uuid not null references public.prospects(id) on delete cascade,
  to_email text not null check (to_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  subject text not null check (length(trim(subject)) between 1 and 300),
  body text not null check (length(trim(body)) between 1 and 20000),
  status text not null default 'draft' check (status in ('draft','approved','sending','sent','received','failed','cancelled')),
  provider_message_id text unique, approved_at timestamptz, claimed_at timestamptz, sent_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index messages_prospect_created on public.messages(prospect_id, created_at desc);
create index messages_status_created on public.messages(status, created_at desc);
create table public.activities (
  id bigint generated always as identity primary key,
  prospect_id uuid references public.prospects(id) on delete cascade,
  kind text not null, actor text not null, detail text not null,
  created_at timestamptz not null default now()
);
create index activities_prospect_created on public.activities(prospect_id,created_at desc);
create index activities_created on public.activities(created_at desc);
alter table public.prospects enable row level security;
alter table public.messages enable row level security;
alter table public.activities enable row level security;
revoke all on public.prospects, public.messages, public.activities from anon, authenticated;
grant select, insert, update on public.prospects to authenticated;
grant select on public.messages, public.activities to authenticated;
grant all on public.prospects, public.messages, public.activities to service_role;
create policy admin_prospects on public.prospects for all to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));
create policy admin_messages on public.messages for select to authenticated using ((select private.is_admin()));
create policy admin_activities on public.activities for select to authenticated using ((select private.is_admin()));

create function private.audit_prospect() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.activities(prospect_id,kind,actor,detail)
    values(new.id, case when tg_op='INSERT' then 'prospect_created' else 'status_changed' end,
      case when current_setting('app.actor',true)='hermes' then 'Hermes' else 'Vous' end,
      case when tg_op='INSERT' then new.name else new.status end);
  end if;
  if new.status in ('do_not_contact','declined') then
    update public.messages set status='cancelled', updated_at=now() where prospect_id=new.id and status in ('draft','approved');
  end if;
  return new;
end; $$;
-- AFTER insert so the activity's foreign key can see the prospect.
create function private.touch_prospect() returns trigger language plpgsql set search_path = '' as $$ begin new.updated_at := now(); return new; end; $$;
create trigger prospect_touch before update on public.prospects for each row execute function private.touch_prospect();
create trigger prospect_audit after insert or update on public.prospects for each row execute function private.audit_prospect();
revoke all on function private.audit_prospect(), private.touch_prospect() from public, anon, authenticated;

create table private.agent_tokens (
  id uuid primary key default gen_random_uuid(), token_hash text not null unique,
  created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '90 days',
  revoked_at timestamptz, last_seen_at timestamptz
);
create table private.agent_requests (
  request_id uuid primary key, token_id uuid not null references private.agent_tokens(id),
  fingerprint text not null, response jsonb not null, created_at timestamptz not null default now()
);
create index agent_requests_token on private.agent_requests(token_id);
alter table private.agent_tokens enable row level security;
alter table private.agent_requests enable row level security;
revoke all on all tables in schema private from public, anon, authenticated;

create function private.manage_agent(p_action text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_token text; v_result jsonb;
begin
  if not private.is_admin() then raise exception 'Accès refusé' using errcode='42501'; end if;
  if p_action='status' then
    select jsonb_build_object('configured',count(*)>0,'last_seen_at',max(last_seen_at),'expires_at',max(expires_at)) into v_result
    from private.agent_tokens where revoked_at is null and expires_at>now();
    return v_result;
  elsif p_action in ('rotate','revoke') then
    update private.agent_tokens set revoked_at=now() where revoked_at is null;
    if p_action='revoke' then return jsonb_build_object('revoked',true); end if;
    v_token := 'ht_' || encode(extensions.gen_random_bytes(32),'hex');
    insert into private.agent_tokens(token_hash) values(encode(extensions.digest(v_token,'sha256'),'hex'));
    return jsonb_build_object('token',v_token,'expires_at',now()+interval '90 days');
  end if;
  raise exception 'Action inconnue';
end; $$;
revoke all on function private.manage_agent(text) from public, anon;
grant execute on function private.manage_agent(text) to authenticated;
create function public.manage_hermes(p_action text) returns jsonb language sql security invoker set search_path = '' as $$ select private.manage_agent(p_action); $$;
revoke all on function public.manage_hermes(text) from public, anon;
grant execute on function public.manage_hermes(text) to authenticated;

create function private.save_message(p_prospect_id uuid,p_subject text,p_body text,p_to_email text,p_id uuid default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.messages; v_status text;
begin
  if not private.is_admin() then raise exception 'Accès refusé' using errcode='42501'; end if;
  select status into v_status from public.prospects where id=p_prospect_id for update;
  if v_status is null or v_status in ('do_not_contact','declined') then raise exception 'Ce prospect ne peut pas être contacté'; end if;
  if p_id is null then
    insert into public.messages(prospect_id,subject,body,to_email) values(p_prospect_id,p_subject,p_body,p_to_email) returning * into v;
  else
    update public.messages set subject=p_subject,body=p_body,to_email=p_to_email,updated_at=now()
    where id=p_id and prospect_id=p_prospect_id and status='draft' returning * into v;
    if not found then raise exception 'Seul un brouillon peut être modifié'; end if;
  end if;
  return to_jsonb(v);
end; $$;
revoke all on function private.save_message(uuid,text,text,text,uuid) from public,anon;
grant execute on function private.save_message(uuid,text,text,text,uuid) to authenticated;
create function public.save_message(p_prospect_id uuid,p_subject text,p_body text,p_to_email text,p_id uuid default null) returns jsonb language sql security invoker set search_path = '' as $$ select private.save_message(p_prospect_id,p_subject,p_body,p_to_email,p_id); $$;
revoke all on function public.save_message(uuid,text,text,text,uuid) from public,anon;
grant execute on function public.save_message(uuid,text,text,text,uuid) to authenticated;

create function private.review_message(p_id uuid,p_approve boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.messages; v_prospect uuid; v_status text;
begin
  if not private.is_admin() then raise exception 'Accès refusé' using errcode='42501'; end if;
  select prospect_id into v_prospect from public.messages where id=p_id;
  select status into v_status from public.prospects where id=v_prospect for update;
  if v_status is null or v_status in ('do_not_contact','declined') then raise exception 'Ce prospect ne peut pas être contacté'; end if;
  update public.messages set status=case when p_approve then 'approved' else 'draft' end,
    approved_at=case when p_approve then now() else null end, updated_at=now()
  where id=p_id and status=case when p_approve then 'draft' else 'approved' end returning * into v;
  if not found then raise exception 'Le statut du message a changé. Actualisez.'; end if;
  insert into public.activities(prospect_id,kind,actor,detail) values(v.prospect_id,'message_reviewed','Vous',case when p_approve then 'Message approuvé' else 'Approbation retirée' end);
  return to_jsonb(v);
end; $$;
revoke all on function private.review_message(uuid,boolean) from public,anon;
grant execute on function private.review_message(uuid,boolean) to authenticated;
create function public.review_message(p_id uuid,p_approve boolean) returns jsonb language sql security invoker set search_path = '' as $$ select private.review_message(p_id,p_approve); $$;
revoke all on function public.review_message(uuid,boolean) from public,anon;
grant execute on function public.review_message(uuid,boolean) to authenticated;

create function private.agent_call(p_token text,p_action text,p_payload jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_token private.agent_tokens; v_prev private.agent_requests; v_fp text; v_result jsonb;
  v_prospect public.prospects; v_message public.messages; v_id uuid; v_status text;
begin
  if p_token is null or p_token !~ '^ht_[a-f0-9]{64}$' then raise exception 'Invalid token' using errcode='28000'; end if;
  select * into v_token from private.agent_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and revoked_at is null and expires_at>now() for update;
  if not found then raise exception 'Invalid token' using errcode='28000'; end if;
  if p_request_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Invalid request'; end if;
  v_fp := encode(extensions.digest(p_action || p_payload::text,'sha256'),'hex');
  select * into v_prev from private.agent_requests where request_id=p_request_id;
  if found then
    if v_prev.token_id<>v_token.id or v_prev.fingerprint<>v_fp then raise exception 'Request id reused with different content'; end if;
    return v_prev.response;
  end if;
  perform set_config('app.actor','hermes',true);
  update private.agent_tokens set last_seen_at=now() where id=v_token.id;
  if p_action='heartbeat' then
    v_result := jsonb_build_object('ok',true,'server_time',now());
  elsif p_action='list_prospects' then
    select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) into v_result from (
      select * from public.prospects where (p_payload->>'status' is null or status=p_payload->>'status')
      order by created_at desc, id limit 100 offset greatest(0,least(coalesce((p_payload->>'offset')::integer,0),100000))
    ) p;
  elsif p_action='upsert_prospect' then
    if coalesce(p_payload->>'siret','') !~ '^[0-9]{14}$' or coalesce(p_payload->>'source_url','') !~ '^https?://' then raise exception 'SIRET et URL source obligatoires'; end if;
    insert into public.prospects(name,siret,address,city,postal_code,activity_code,employee_band,employee_year,website,source_url,source_checked_at,contact_name,contact_role,email,phone,contact_source_url,notes)
    values(p_payload->>'name',p_payload->>'siret',p_payload->>'address',p_payload->>'city',p_payload->>'postal_code',p_payload->>'activity_code',p_payload->>'employee_band',(p_payload->>'employee_year')::integer,p_payload->>'website',p_payload->>'source_url',now(),p_payload->>'contact_name',p_payload->>'contact_role',nullif(p_payload->>'email',''),p_payload->>'phone',p_payload->>'contact_source_url',coalesce(p_payload->>'notes',''))
    on conflict(siret) do update set name=excluded.name,address=coalesce(excluded.address,prospects.address),city=coalesce(excluded.city,prospects.city),postal_code=coalesce(excluded.postal_code,prospects.postal_code),activity_code=coalesce(excluded.activity_code,prospects.activity_code),employee_band=coalesce(excluded.employee_band,prospects.employee_band),employee_year=coalesce(excluded.employee_year,prospects.employee_year),website=coalesce(excluded.website,prospects.website),source_url=excluded.source_url,source_checked_at=now(),
      contact_name=coalesce(prospects.contact_name,excluded.contact_name),contact_role=coalesce(prospects.contact_role,excluded.contact_role),email=coalesce(prospects.email,excluded.email),phone=coalesce(prospects.phone,excluded.phone),contact_source_url=coalesce(prospects.contact_source_url,excluded.contact_source_url)
    returning * into v_prospect;
    v_result := to_jsonb(v_prospect);
  elsif p_action='create_draft' then
    select * into v_prospect from public.prospects where id=(p_payload->>'prospect_id')::uuid for update;
    if not found or v_prospect.status in ('do_not_contact','declined') then raise exception 'Prospect absent ou à ne plus contacter'; end if;
    insert into public.messages(prospect_id,to_email,subject,body) values(v_prospect.id,coalesce(nullif(p_payload->>'to_email',''),v_prospect.email),p_payload->>'subject',p_payload->>'body') returning * into v_message;
    insert into public.activities(prospect_id,kind,actor,detail) values(v_prospect.id,'draft_created','Hermes',v_message.subject);
    v_result := to_jsonb(v_message);
  elsif p_action='list_approved' then
    select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) into v_result from (
      select m.* from public.messages m join public.prospects p on p.id=m.prospect_id
      where m.status='approved' and p.status not in ('declined','do_not_contact') order by m.approved_at limit 50
    ) m;
  elsif p_action in ('claim_message','record_sent','record_reply') then
    if p_action='record_reply' then
      v_id := (p_payload->>'prospect_id')::uuid;
    else
      select prospect_id into v_id from public.messages where id=(p_payload->>'message_id')::uuid;
    end if;
    select * into v_prospect from public.prospects where id=v_id for update;
    if not found then raise exception 'Prospect absent'; end if;
    if p_action='claim_message' then
      if v_prospect.status in ('declined','do_not_contact') then raise exception 'Prospect à ne plus contacter'; end if;
      update public.messages set status='sending',claimed_at=now(),updated_at=now()
      where id=(p_payload->>'message_id')::uuid and status='approved' returning * into v_message;
      if not found then raise exception 'Message non approuvé ou déjà pris en charge'; end if;
      v_result := to_jsonb(v_message);
    elsif p_action='record_sent' then
      if length(coalesce(p_payload->>'provider_message_id',''))=0 then raise exception 'Identifiant du fournisseur obligatoire'; end if;
      update public.messages set status='sent',sent_at=now(),provider_message_id=p_payload->>'provider_message_id',updated_at=now()
      where id=(p_payload->>'message_id')::uuid and status='sending' returning * into v_message;
      if not found then raise exception 'Message non pris en charge'; end if;
      update public.prospects set status='contacted' where id=v_id and status in ('new','to_contact');
      insert into public.activities(prospect_id,kind,actor,detail) values(v_id,'mail_sent','Hermes',v_message.subject);
      v_result := to_jsonb(v_message);
    else
      if length(coalesce(p_payload->>'provider_message_id',''))=0 then raise exception 'Identifiant du fournisseur obligatoire'; end if;
      insert into public.messages(prospect_id,to_email,subject,body,status,provider_message_id) values(v_id,p_payload->>'from_email',p_payload->>'subject',p_payload->>'body','received',p_payload->>'provider_message_id') returning * into v_message;
      update public.prospects set status=case when coalesce((p_payload->>'opt_out')::boolean,false) then 'do_not_contact' else 'replied' end
      where id=v_id and (status not in ('declined','do_not_contact','booked') or coalesce((p_payload->>'opt_out')::boolean,false));
      insert into public.activities(prospect_id,kind,actor,detail) values(v_id,'reply_received','Hermes',v_message.subject);
      v_result := to_jsonb(v_message);
    end if;
  else
    raise exception 'Action inconnue';
  end if;
  insert into private.agent_requests(request_id,token_id,fingerprint,response) values(p_request_id,v_token.id,v_fp,v_result);
  return v_result;
end; $$;
revoke all on function private.agent_call(text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function private.agent_call(text,text,jsonb,uuid) to service_role;
create function public.hermes_call(p_token text,p_action text,p_payload jsonb,p_request_id uuid) returns jsonb language sql security invoker set search_path = '' as $$ select private.agent_call(p_token,p_action,p_payload,p_request_id); $$;
revoke all on function public.hermes_call(text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.hermes_call(text,text,jsonb,uuid) to service_role;
