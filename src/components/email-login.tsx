'use client';

import { useEffect, useRef, useState, type FormEvent } from 'react';
import { ArrowRight, Mail } from 'lucide-react';
import { supabase } from '@/lib/supabase';

export function EmailLogin() {
  const [email, setEmail] = useState('');
  const [sentTo, setSentTo] = useState('');
  const [busy, setBusy] = useState(false);
  const [cooldown, setCooldown] = useState(0);
  const [error, setError] = useState('');
  const sending = useRef(false);

  useEffect(() => {
    if (!cooldown) return;
    const timer = setTimeout(() => setCooldown(value => Math.max(0, value - 1)), 1000);
    return () => clearTimeout(timer);
  }, [cooldown]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (sending.current || cooldown > 0) return;
    sending.current = true;
    setBusy(true);
    setError('');
    const address = email.trim().toLowerCase();
    try {
      const { error } = await supabase.auth.signInWithOtp({
        email: address,
        options: { emailRedirectTo: window.location.origin + '/' },
      });
      if (error) {
        if (error.status === 429 || error.code === 'over_email_send_rate_limit') {
          setCooldown(60);
          setError('Trop de demandes. Patientez une minute avant de réessayer.');
        } else {
          setError('Le lien n’a pas pu être envoyé. Vérifiez votre adresse et réessayez. Si le problème persiste, contactez l’administrateur.');
        }
        return;
      }
      setSentTo(address);
      setCooldown(60);
    } catch {
      setError('Connexion au service impossible. Vérifiez votre connexion internet et réessayez.');
    } finally {
      sending.current = false;
      setBusy(false);
    }
  }

  return <form className="mt-8 space-y-5" onSubmit={submit} aria-busy={busy}>
    <div>
      <label htmlFor="login-email">Votre adresse email</label>
      <input id="login-email" name="email" type="email" autoComplete="email" required maxLength={254}
        value={email} onChange={event => { setEmail(event.target.value); setError(''); }}
        disabled={busy} placeholder="vous@exemple.fr" aria-describedby="login-help" />
      <p id="login-help" className="mt-2 text-xs leading-5 text-muted">Utilisez l’adresse autorisée par le restaurant. Aucun mot de passe nécessaire.</p>
    </div>
    <button type="submit" className="button button-primary w-full !py-3.5" disabled={busy || cooldown > 0}>
      <Mail size={17} aria-hidden="true" />
      {busy ? 'Envoi en cours…' : cooldown > 0 ? `Renvoyer dans ${cooldown} s` : sentTo ? 'Envoyer un nouveau lien' : 'Recevoir un lien de connexion'}
      <ArrowRight size={17} className="ml-auto shrink-0" aria-hidden="true" />
    </button>
    {sentTo && <div role="status" className="rounded-lg border border-line bg-white p-4 text-sm leading-6">
      <p className="font-semibold">Consultez votre messagerie</p>
      <p className="mt-1">Un lien de connexion a été demandé pour <strong className="break-all">{sentTo}</strong>. Ouvrez le lien reçu pour accéder à votre espace.</p>
      <p className="mt-2 text-muted">Pensez aux courriers indésirables. Seule une adresse autorisée pourra consulter les données.</p>
    </div>}
    {error && <p role="alert" className="text-sm text-rose-800">{error}</p>}
  </form>;
}
