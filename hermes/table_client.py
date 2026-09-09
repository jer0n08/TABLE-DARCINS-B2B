#!/usr/bin/env python3
"""Restricted Hermes bridge. Standard library only. Never sends email."""
import argparse
import json
import os
import sys
import time
import uuid
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ENDPOINT = "https://lxtigfcpdmjpthskuspm.supabase.co/functions/v1/hermes-prospection"
ACTIONS = ("heartbeat", "list_prospects", "upsert_prospect", "create_draft", "list_approved", "claim_message", "record_sent", "record_reply")

def call(action, payload, request_id=None):
    token = os.environ.get("TABLE_HERMES_TOKEN", "")
    if not token.startswith("ht_") or len(token) != 67:
        raise ValueError("Configure TABLE_HERMES_TOKEN dans l'environnement du VPS.")
    if action not in ACTIONS or not isinstance(payload, dict):
        raise ValueError("Action ou contenu invalide.")
    request_id = str(uuid.UUID(request_id)) if request_id else str(uuid.uuid4())
    body = json.dumps({"action": action, "payload": payload, "request_id": request_id}).encode("utf-8")
    if len(body) > 65536:
        raise ValueError("Le contenu dépasse 64 Kio.")
    # The same ID is retained across retries, including uncertain write outcomes.
    print("request_id=" + request_id, file=sys.stderr)
    for attempt in range(3):
        request = Request(ENDPOINT, data=body, headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"}, method="POST")
        try:
            with urlopen(request, timeout=30) as response:
                return json.load(response)
        except HTTPError as exc:
            if exc.code < 500 and exc.code != 429:
                try:
                    reason = json.loads(exc.read()).get("error", "Requête refusée")
                except (ValueError, AttributeError):
                    reason = "Requête refusée"
                raise RuntimeError(f"HTTP {exc.code}: {reason}") from None
            if attempt == 2:
                raise RuntimeError(f"HTTP {exc.code}. Réessayer avec --request-id {request_id} et le même contenu.") from None
        except (URLError, TimeoutError):
            if attempt == 2:
                raise RuntimeError(f"Résultat réseau incertain. Réessayer avec --request-id {request_id} et le même contenu.") from None
        time.sleep(2 ** attempt)
    raise RuntimeError("Requête inachevée")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=ACTIONS)
    parser.add_argument("--file", help="Fichier JSON du contenu. Sinon, {}.")
    parser.add_argument("--request-id", help="UUID à réutiliser pour reprendre une requête incertaine.")
    args = parser.parse_args()
    try:
        if args.file:
            with open(args.file, encoding="utf-8") as stream:
                payload = json.load(stream)
        else:
            payload = {}
        print(json.dumps(call(args.action, payload, args.request_id), ensure_ascii=False, indent=2))
    except (ValueError, OSError, RuntimeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
