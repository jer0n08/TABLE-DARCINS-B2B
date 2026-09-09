# Connecter Hermes sur le VPS

Le serveur de connexion est déployé dans le projet Supabase du restaurant. Aucun port entrant supplémentaire n'est nécessaire sur le VPS : Hermes appelle une URL HTTPS sortante.

## 1. Préparer l'accès

Connectez-vous au tableau avec le compte Google autorisé. Dans **Agent Hermes → Configurer l'accès**, générez la clé et copiez-la. Elle est affichée une seule fois, expire sous 90 jours et peut être révoquée depuis le tableau.

Le fournisseur Google doit d'abord être activé : voir [la configuration du projet](../README.md#connexion-google).

## 2. Installer le kit

Copiez les fichiers de ce dossier dans un dossier de skill personnel de votre installation Hermes, par exemple `~/.hermes/skills/table-darcins-prospection/`. Préservez les autres skills et votre configuration actuelle. Le fichier `table_client.py` doit rester à côté de `SKILL.md`.

Python 3 est nécessaire ; aucune dépendance Python supplémentaire.

Configurez `TABLE_HERMES_TOKEN` dans l'environnement réel du processus Hermes (service systemd, conteneur ou autre gestionnaire déjà utilisé). Le définir uniquement dans une session SSH ne le transmet pas à un service déjà démarré. Utilisez le mécanisme de secrets de votre hébergeur ou un fichier protégé accessible uniquement au compte qui exécute Hermes. Ne donnez jamais la clé `service_role` de Supabase à l'agent.

Pour tester temporairement depuis une session bash sans inscrire la clé dans l'historique :

```bash
read -rsp 'Clé Hermes : ' TABLE_HERMES_TOKEN
export TABLE_HERMES_TOKEN
printf '\n'
python3 ~/.hermes/skills/table-darcins-prospection/table_client.py heartbeat
```

Après avoir configuré l'environnement persistant, redémarrez uniquement le service Hermes avec le gestionnaire utilisé sur votre VPS. La commande exacte dépend de votre installation ; ne redémarrez pas tout le VPS.

## 3. Valider depuis Telegram

Demandez à Hermes de charger le skill `table-darcins-prospection` et d'envoyer un heartbeat. Vérifiez l'heure dans **Agent Hermes**. Demandez ensuite une seule recherche d'établissement réel avec son SIRET et ses sources. Vérifiez sa fiche dans **Prospects**, puis créez un brouillon sans l'approuver.

## 4. Brancher la messagerie séparément

Ce kit enregistre et contrôle les étapes mais n'envoie aucun email. Il reste à connecter à Hermes la messagerie autorisée du restaurant et à vérifier la réception des réponses. N'activez l'envoi qu'après un test complet avec un destinataire de test que vous contrôlez.

Avant l'envoi, le message doit être approuvé dans le tableau, puis réclamé par `claim_message`. En cas d'incertitude après l'appel du fournisseur, ne pas renvoyer sans vérification : le statut reste `sending` pour rendre cette incertitude visible.

## Requêtes disponibles

`heartbeat`, `list_prospects`, `upsert_prospect`, `create_draft`, `list_approved`, `claim_message`, `record_sent`, `record_reply`.

Le détail des champs et les règles de prospection sont dans [SKILL.md](SKILL.md).
