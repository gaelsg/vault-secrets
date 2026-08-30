#!/usr/bin/env bash
# Onboarding de devops-multiagent en Vault: migra TELEGRAM_BOT_TOKEN,
# TELEGRAM_CHAT_ID y WEBHOOK_SHARED_SECRET de su .env real a
# secret/devops-multiagent, y deja el .env solo con el AppRole. Usa
# vault-admin (Idea 2), no root token -- mismo criterio que
# onboard-k8s-mcp-server.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ADMIN_APPROLE="$REPO_ROOT/.admin-approle"
TARGET_ENV="$HOME/projects/devops-multiagent/.env"

[ -f "$ADMIN_APPROLE" ] || { echo "No encuentro $ADMIN_APPROLE" >&2; exit 1; }
[ -f "$TARGET_ENV" ] || { echo "No encuentro $TARGET_ENV" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ADMIN_APPROLE"
set +a

echo "== Login con AppRole vault-admin =="
VAULT_TOKEN="$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
export VAULT_TOKEN

echo "== Politica devops-multiagent =="
vault policy write devops-multiagent "$REPO_ROOT/policies/devops-multiagent.hcl"

echo "== Role devops-multiagent =="
vault write auth/approle/role/devops-multiagent \
  token_policies="devops-multiagent" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_num_uses=0 \
  secret_id_ttl=0 >/dev/null

echo "== Migrando TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID / WEBHOOK_SHARED_SECRET a secret/devops-multiagent =="
python3 - "$TARGET_ENV" <<'PYEOF'
import subprocess
import sys

env_path = sys.argv[1]
KEYS = {"TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID", "WEBHOOK_SHARED_SECRET"}
values = {}
with open(env_path) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k in KEYS and v.strip():
            values[k] = v.strip()

missing = KEYS - values.keys()
if missing:
    print(f"Faltan valores en {env_path} para: {', '.join(sorted(missing))}", file=sys.stderr)
    sys.exit(1)

args = ["vault", "kv", "put", "secret/devops-multiagent"]
args += [f"{k}={v}" for k, v in values.items()]
subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
print(f"{len(values)} claves escritas en secret/devops-multiagent (valores no impresos)")
PYEOF

echo "== Generando credenciales AppRole y reescribiendo $TARGET_ENV =="
ROLE_ID="$(vault read -field=role_id auth/approle/role/devops-multiagent/role-id)"
SECRET_ID="$(vault write -field=secret_id -f auth/approle/role/devops-multiagent/secret-id)"

python3 - "$TARGET_ENV" "$VAULT_ADDR" "$VAULT_CACERT" "$ROLE_ID" "$SECRET_ID" <<'PYEOF'
import sys

env_path, vault_addr, vault_cacert, role_id, secret_id = sys.argv[1:6]
STRIP_KEYS = ("VAULT_ADDR=", "VAULT_CACERT=", "VAULT_ROLE_ID=", "VAULT_SECRET_ID=",
              "TELEGRAM_BOT_TOKEN=", "TELEGRAM_CHAT_ID=", "WEBHOOK_SHARED_SECRET=")

with open(env_path) as f:
    lines = [l for l in f if not l.startswith(STRIP_KEYS)]

lines.append(f"VAULT_ADDR={vault_addr}\n")
lines.append(f"VAULT_CACERT={vault_cacert}\n")
lines.append(f"VAULT_ROLE_ID={role_id}\n")
lines.append(f"VAULT_SECRET_ID={secret_id}\n")

with open(env_path, "w") as f:
    f.writelines(lines)

print(f"Credenciales de AppRole agregadas a {env_path} (no impresas aqui)")
PYEOF

vault token revoke -self >/dev/null 2>&1 || true
echo "== Listo. Token de vault-admin de esta sesion revocado. =="
