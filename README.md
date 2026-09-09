# La Table d’Arçins — Prospection B2B

Interface Next.js **16.3.4**, React et Tailwind CSS **4.3.3**. Versions stables vérifiées au registre npm le 10 septembre 2026 ; toutes les dépendances sont figées dans le manifeste et le verrou npm.

## Fonctionnement

L’interface utilise Supabase Auth (Google), la base Postgres et ses règles RLS. Le compte Google autorisé est configuré côté serveur. Il n'y a aucun secret administrateur dans le navigateur.

Hermes reste sur le VPS. Il appelle l’Edge Function `hermes-prospection` avec une clé dédiée, révocable et limitée à 90 jours. Cette fonction exécute uniquement une liste définie d’actions ; elle n’offre aucun accès SQL à l’agent.

La compilation Next.js produit une interface statique dans `out/`. Les données restent dynamiques : elles sont chargées après authentification et actualisées toutes les 30 secondes. Le backend est Supabase. Cela permet d’héberger l’interface sur Sites ou un serveur de fichiers sans processus Node permanent. Les futurs besoins SSR nécessiteraient de revoir ce mode de déploiement.

## Écrans

- Prospects : recherche, filtre par avancement, échéances, fiche, ajout et modification.
- Messages : brouillons éditables, approbation explicite, retrait d’approbation, historique d’envoi et de réponse.
- Hermes : état du dernier contact, génération/révocation de la clé, activité récente.
- Aperçu sans accès aux données : trois entreprises explicitement fictives, aucun enregistrement.

L’interface charge les 500 dernières entreprises, les 500 derniers messages et les 100 dernières activités. Les indicateurs portent sur ces fiches chargées. L’API agent permet de parcourir les prospects par pages de 100.

## Développement

Node 22 ou plus récent. Copier `.env.example` vers `.env.local` et renseigner la clé **publishable** du projet ; ne jamais utiliser de clé secrète dans une variable `NEXT_PUBLIC_`.

```bash
npm ci
npm run dev
npm run typecheck
npm run lint
npm run build
```

La première migration a été appliquée au projet `lxtigfcpdmjpthskuspm`. Les fichiers `supabase/migrations/` sont la référence : ne pas réappliquer la migration initiale au même projet. Les tests `supabase/tests/prospection.sql` créent des fixtures dans une transaction puis annulent toutes les écritures. Ils ne transmettent aucun mail.

## Connexion Google

L’interface est prête pour Google, mais le fournisseur est encore désactivé dans Supabase au moment de la création du projet.

1. Dans Google Cloud, configurer un client OAuth de type **Application Web** et son écran de consentement. Si l’application est en mode test, ajouter le compte du propriétaire comme utilisateur de test.
2. Origines JavaScript autorisées : `https://table-darcins-b2b.rttm-influenceur.chatgpt.site` et, pour le développement, `http://127.0.0.1:3000`.
3. URI de redirection autorisée Google : `https://lxtigfcpdmjpthskuspm.supabase.co/auth/v1/callback`.
4. Dans Supabase → Authentication → Sign In / Providers → Google, activer Google et saisir l’identifiant client et le secret **directement dans Supabase**.
5. Dans Supabase → Authentication → URL Configuration, définir Site URL sur `https://table-darcins-b2b.rttm-influenceur.chatgpt.site/`. Ajouter cette même URL ainsi que `http://127.0.0.1:3000/` aux redirections autorisées.
6. Se connecter avec le compte Google autorisé. L’email doit être vérifié et l’identité Google doit correspondre à l’email autorisé côté base.

L’aperçu Sites est privé au propriétaire et demande aussi l'accès Sites. Google sécurise séparément les données Supabase. Une ouverture à d’autres personnes demande de configurer les deux niveaux d’accès.

Documentation : https://supabase.com/docs/guides/auth/social-login/auth-google

## Installation Hermes

Voir [hermes/README.md](hermes/README.md). Le kit n'est pas encore installé sur le VPS par cette tâche, faute d’accès à ce serveur. La messagerie d’envoi/réception doit être reliée séparément à Hermes.

Une approbation rend le message disponible pour `claim_message`, qui le réserve une seule fois. La confirmation `record_sent` nécessite l’identifiant réellement retourné par la messagerie. Un résultat réseau incertain reste `sending` : vérifier le fournisseur avant toute reprise. Une idempotence côté base n’empêche pas, à elle seule, un double envoi chez un fournisseur externe.

Les refus bloquent les nouveaux brouillons et annulent les messages non encore pris en charge. Ils ne rappellent pas un message déjà en cours d’envoi.

## Données et sécurité

- Tables applicatives protégées par RLS et contrôle d’un compte Google autorisé côté base.
- Tables privées de clés et autorisations sans accès direct depuis le navigateur.
- Secrets Hermes stockés uniquement sous forme d’empreinte SHA-256 en base.
- RPC de l’agent réservée au serveur de la fonction ; pas d’appel direct avec la clé publique.
- Fiches dédoublonnées par SIRET ; un réimport ne réinitialise pas un refus ni l’avancement.
- Les mises à jour de statut, brouillons de l’agent, approbations et confirmations sont historisés.
- Les URL affichées sont limitées aux protocoles HTTP(S).
- Sirene ne contient ni la liste des salariés ni leurs emails. Conserver la provenance des contacts trouvés ailleurs.

Le contrôle Supabase signale les tables du schéma `private` sans politique RLS : c’est intentionnel (aucun accès client, fonctions vérifiées uniquement). Ne pas y ajouter une politique ouverte pour faire disparaître cet avis informatif.

## À finaliser avant une campagne réelle

Activer Google ; connecter le kit au VPS ; relier la messagerie du restaurant ; préciser les tarifs, capacités, menus, zone et critères de ciblage ; valider un test d’envoi et de réponse sur une adresse contrôlée. Aucun mail de prospection n'a été envoyé par cette tâche.
