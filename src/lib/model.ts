export const statuses = {
  new: { label: 'À qualifier', color: 'bg-slate-100 text-slate-700' },
  to_contact: { label: 'À contacter', color: 'bg-blue-50 text-blue-800' },
  contacted: { label: 'Contacté', color: 'bg-amber-50 text-amber-900' },
  replied: { label: 'Réponse reçue', color: 'bg-violet-50 text-violet-800' },
  interested: { label: 'Intéressé', color: 'bg-emerald-50 text-emerald-800' },
  booked: { label: 'Réservation', color: 'bg-green-100 text-green-900' },
  declined: { label: 'Refus', color: 'bg-stone-100 text-stone-700' },
  do_not_contact: { label: 'Ne plus contacter', color: 'bg-rose-50 text-rose-800' },
} as const;
export type Status = keyof typeof statuses;
export type Prospect = {
  id: string; name: string; siret: string | null; address: string | null; city: string | null;
  postal_code: string | null; activity_code: string | null; employee_band: string | null; employee_year: number | null;
  website: string | null; source_url: string | null; source_checked_at: string | null;
  contact_name: string | null; contact_role: string | null; email: string | null; phone: string | null;
  contact_source_url: string | null; status: Status; notes: string; next_follow_up: string | null;
  created_at: string; updated_at: string;
};
export type Message = { id: string; prospect_id: string; to_email: string; subject: string; body: string; status: 'draft'|'approved'|'sending'|'sent'|'received'|'failed'|'cancelled'; created_at: string; sent_at: string | null; };
export type Activity = { id: number; prospect_id: string; kind: string; actor: string; detail: string; created_at: string };
export type AgentConnection = { configured: boolean; last_seen_at: string | null; expires_at: string | null };
export const messageLabels: Record<Message['status'],string> = { draft:'À valider',approved:'Approuvé',sending:'En cours d’envoi',sent:'Envoyé',received:'Réponse reçue',failed:'Échec',cancelled:'Annulé' };
export const emptyProspect: Omit<Prospect,'id'|'created_at'|'updated_at'> = { name:'',siret:null,address:null,city:'Bègles',postal_code:'33130',activity_code:null,employee_band:null,employee_year:null,website:null,source_url:null,source_checked_at:null,contact_name:null,contact_role:null,email:null,phone:null,contact_source_url:null,status:'new',notes:'',next_follow_up:null };
export function dateLabel(value: string | null, time = false) { if(!value) return '—'; return new Intl.DateTimeFormat('fr-FR',{day:'numeric',month:'short',...(time?{hour:'2-digit',minute:'2-digit'}:{})}).format(new Date(value)); }
export function safeUrl(value: string | null) { if(!value) return undefined; try { const u=new URL(value); return ['https:','http:'].includes(u.protocol)?u.href:undefined; } catch {return undefined;} }
export function parisToday() { return new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Paris',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()); }
export function isDue(p: Prospect) { return !!p.next_follow_up && p.next_follow_up<=parisToday() && !['declined','do_not_contact','booked'].includes(p.status); }
const demoBase={...emptyProspect,created_at:'2026-09-09T10:00:00Z',updated_at:'2026-09-09T10:00:00Z'};
export const demoProspects: Prospect[] = [
  {...demoBase,id:'demo-1',name:'Atelier des Rives',city:'Bègles',employee_band:'10 à 19 salariés',status:'interested',contact_name:'Camille — exemple',contact_role:'Office manager',email:'contact@atelier.example',notes:'Exemple fictif : déjeuner d’équipe de 12 personnes.'},
  {...demoBase,id:'demo-2',name:'Collectif Belvédère',city:'Bordeaux',employee_band:'20 à 49 salariés',status:'contacted',contact_role:'Direction',email:'bonjour@belvedere.example'},
  {...demoBase,id:'demo-3',name:'Studio Garonne',city:'Bègles',employee_band:'6 à 9 salariés',status:'new',contact_role:'Contact à rechercher'},
];
