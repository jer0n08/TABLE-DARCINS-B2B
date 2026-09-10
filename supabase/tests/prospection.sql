-- Integration tests: all fixtures and credentials are rolled back.
begin;
do $$
declare v_user uuid := gen_random_uuid();
begin
  insert into auth.users(id,email,email_confirmed_at) values(v_user,'jerome.nguyen08@gmail.com',now());
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  if has_table_privilege('anon','public.prospects','select') then raise exception 'Anonymous read granted'; end if;
  if has_function_privilege('authenticated','public.hermes_call(text,text,jsonb,uuid)','execute') then raise exception 'Agent RPC exposed to browser'; end if;
end; $$;

set local role authenticated;
do $$
declare v_prospect uuid; v_message jsonb;
begin
  if not public.has_dashboard_access() then raise exception 'Authorized confirmed email rejected'; end if;
  insert into public.prospects(name,siret,city,email) values('Integration test','99999999999999','Bègles','test@example.invalid') returning id into v_prospect;
  perform set_config('test.prospect',v_prospect::text,true);
  perform set_config('test.token',public.manage_hermes('rotate')->>'token',true);
  v_message := public.save_message(v_prospect,'Test subject','Test body','test@example.invalid');
  perform set_config('test.message',v_message->>'id',true);
  begin
    insert into public.messages(prospect_id,to_email,subject,body,status) values(v_prospect,'test@example.invalid','Forbidden','Forbidden','approved');
    raise exception 'Direct message write allowed';
  exception when insufficient_privilege then null; end;
end; $$;

set local role service_role;
do $$
declare v_token text:=current_setting('test.token'); v_req uuid:=gen_random_uuid(); v_one jsonb; v_two jsonb; v_payload jsonb;
begin
  v_one := public.hermes_call(v_token,'heartbeat','{}',v_req);
  v_two := public.hermes_call(v_token,'heartbeat','{}',v_req);
  if v_one<>v_two then raise exception 'Idempotent request changed'; end if;
  begin
    perform public.hermes_call(v_token,'list_prospects','{}',v_req);
    raise exception 'Different request content accepted';
  exception when raise_exception then if sqlerrm <> 'Request id reused with different content' then raise; end if; end;
  begin
    perform public.hermes_call(v_token,'claim_message',jsonb_build_object('message_id',current_setting('test.message')),gen_random_uuid());
    raise exception 'Unapproved message claimed';
  exception when raise_exception then if sqlerrm <> 'Message non approuvé ou déjà pris en charge' then raise; end if; end;
  begin
    perform public.hermes_call('ht_'||repeat('0',64),'heartbeat','{}',gen_random_uuid());
    raise exception 'Invalid token accepted';
  exception when invalid_authorization_specification then null; end;
  v_payload:=jsonb_build_object('name','Integration test enriched','siret','99999999999999','source_url','https://example.invalid/source');
  perform public.hermes_call(v_token,'upsert_prospect',v_payload,gen_random_uuid());
end; $$;

set local role authenticated;
do $$ begin
  if (select count(*) from public.prospects where siret='99999999999999')<>1 then raise exception 'SIRET deduplication failed'; end if;
  perform public.review_message(current_setting('test.message')::uuid,true);
end; $$;

set local role service_role;
do $$
declare v_token text:=current_setting('test.token'); v_message uuid:=current_setting('test.message')::uuid; v_resp jsonb;
begin
  v_resp:=public.hermes_call(v_token,'claim_message',jsonb_build_object('message_id',v_message),gen_random_uuid());
  if v_resp->>'status'<>'sending' then raise exception 'Approved message not claimed'; end if;
  begin
    perform public.hermes_call(v_token,'claim_message',jsonb_build_object('message_id',v_message),gen_random_uuid());
    raise exception 'Double claim allowed';
  exception when raise_exception then if sqlerrm <> 'Message non approuvé ou déjà pris en charge' then raise; end if; end;
  perform public.hermes_call(v_token,'record_sent',jsonb_build_object('message_id',v_message,'provider_message_id','integration-test-provider-id'),gen_random_uuid());
end; $$;

set local role authenticated;
do $$
declare v_prospect uuid:=current_setting('test.prospect')::uuid; v_draft jsonb;
begin
  if (select status from public.prospects where id=v_prospect)<>'contacted' then raise exception 'Sent status not reflected'; end if;
  v_draft:=public.save_message(v_prospect,'Follow-up','Test follow-up','test@example.invalid');
  perform public.review_message((v_draft->>'id')::uuid,true);
  update public.prospects set status='do_not_contact' where id=v_prospect;
  if (select status from public.messages where id=(v_draft->>'id')::uuid)<>'cancelled' then raise exception 'Opt-out did not cancel pending message'; end if;
  perform set_config('test.cancelled_message',v_draft->>'id',true);
end; $$;

set local role service_role;
do $$
declare v_token text:=current_setting('test.token');
begin
  perform public.hermes_call(v_token,'upsert_prospect',jsonb_build_object('name','Test','siret','99999999999999','source_url','https://example.invalid/source'),gen_random_uuid());
  if (select status from public.prospects where id=current_setting('test.prospect')::uuid)<>'do_not_contact' then raise exception 'Reimport reset opt-out'; end if;
  begin
    perform public.hermes_call(v_token,'create_draft',jsonb_build_object('prospect_id',current_setting('test.prospect'),'subject','Forbidden','body','Forbidden'),gen_random_uuid());
    raise exception 'Opt-out draft allowed';
  exception when raise_exception then if sqlerrm <> 'Prospect absent ou à ne plus contacter' then raise; end if; end;
end; $$;

set local role authenticated;
do $$ begin perform public.manage_hermes('revoke'); end; $$;
set local role service_role;
do $$ begin
  begin
    perform public.hermes_call(current_setting('test.token'),'heartbeat','{}',gen_random_uuid());
    raise exception 'Revoked token accepted';
  exception when invalid_authorization_specification then null; end;
end; $$;

reset role;
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
set local role authenticated;
do $$ begin
  if public.has_dashboard_access() then raise exception 'Unknown account authorized'; end if;
  if (select count(*) from public.prospects)>0 then raise exception 'RLS exposed data to another account'; end if;
  begin
    insert into public.prospects(name) values('Forbidden');
    raise exception 'Unauthorized insert allowed';
  exception when insufficient_privilege then null; end;
  begin
    perform public.manage_hermes('rotate');
    raise exception 'Unauthorized credential rotation';
  exception when insufficient_privilege then null; end;
end; $$;
reset role;
select 'PASS: email allowlist, RLS, agent isolation, token revocation, idempotency, SIRET deduplication, approval, single claim, sent confirmation, opt-out protection' as result;
rollback;
