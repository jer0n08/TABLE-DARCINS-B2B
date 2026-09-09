import { createClient } from 'npm:@supabase/supabase-js@2.116.0';

const actions = new Set(['heartbeat','list_prospects','upsert_prospect','create_draft','list_approved','claim_message','record_sent','record_reply']);
const reply = (status:number,data:unknown) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type':'application/json', 'Cache-Control':'no-store' } });

Deno.serve(async (req:Request) => {
  if(req.method!=='POST')return reply(405,{error:'POST required'});
  const bearer=req.headers.get('authorization')??'';
  if(!/^Bearer ht_[a-f0-9]{64}$/.test(bearer))return reply(401,{error:'Invalid agent token'});
  if(!req.headers.get('content-type')?.includes('application/json'))return reply(415,{error:'JSON required'});
  const reader=req.body?.getReader(); if(!reader)return reply(400,{error:'Missing body'});
  const chunks:Uint8Array[]=[];let size=0;
  try {
    while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>65536){await reader.cancel();return reply(413,{error:'Maximum payload: 64 KiB'});}chunks.push(value);}
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
    const body=JSON.parse(new TextDecoder().decode(bytes));
    if(!actions.has(body.action)||!body.payload||typeof body.payload!=='object'||Array.isArray(body.payload)||! /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(body.request_id??''))return reply(400,{error:'action, object payload and UUID request_id required'});
    const url=Deno.env.get('SUPABASE_URL');const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if(!url||!key)return reply(503,{error:'Server configuration unavailable'});
    // Only this server holds the project credential. The agent gets a revocable,
    // expiring, hashed token restricted to the actions above, never SQL access.
    const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data,error}=await client.rpc('hermes_call',{p_token:bearer.slice(7),p_action:body.action,p_payload:body.payload,p_request_id:body.request_id});
    if(error){
      if(error.code==='28000')return reply(401,{error:'Agent token expired, revoked or invalid'});
      if(error.code==='42501')return reply(403,{error:'Access denied'});
      if(error.code==='P0001')return reply(409,{error:error.message});
      if(error.code?.startsWith('22')||error.code?.startsWith('23'))return reply(400,{error:'Invalid data or duplicate record; verify required fields and identifiers'});
      return reply(500,{error:'Operation failed; retry with the same request_id'});
    }
    return reply(200,{data,request_id:body.request_id});
  } catch {return reply(400,{error:'Invalid request body'});}
});
