import test from 'node:test';
import assert from 'node:assert/strict';
import { safeUrl, isDue, parisToday, emptyProspect } from '../src/lib/model.ts';

test('external source links reject script, data and file schemes',()=>{
  for(const value of ['javascript:alert(1)','data:text/html,<script>alert(1)</script>','file:///etc/passwd','not a URL',null])assert.equal(safeUrl(value),undefined);
  assert.equal(safeUrl('https://example.com/source'),'https://example.com/source');
});
test('refusals and bookings never enter the follow-up queue',()=>{
  for(const status of ['do_not_contact','declined','booked'])assert.equal(isDue({...emptyProspect,status,next_follow_up:'2000-01-01'}),false);
  assert.equal(isDue({...emptyProspect,status:'contacted',next_follow_up:parisToday()}),true);
  assert.equal(isDue({...emptyProspect,next_follow_up:null}),false);
  assert.equal(isDue({...emptyProspect,next_follow_up:'2200-01-01'}),false);
});
