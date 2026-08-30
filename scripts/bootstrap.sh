#!/usr/bin/env bash
# Bootstrap de Vault: audit log, KV v2, politicas, AppRole para
# proxmox-mcp-server, y migracion de sus secretos reales desde su .env.
#
# Requiere: VAULT_ADDR y VAULT_CACERT exportados, y estar logueado con el
# root token (`vault login`, interactivo) ANTES de correr este script.
# Este script no imprime ningun secreto - ni el que ya existia en .env, ni
# el role_id/secret_id nuevos de AppRole.
set -euo pipefail

: "${VAULT_ADDR:?export VAULT_ADDR primero}"
: "${VAULT_CACERT:?export VAULT_CACERT primero}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROXMOX_ENV="$HOME/projects/proxmox-mcp-server/.env"

if [ ! -f "$PROXMOX_ENV" ]; then
  echo "No encuentro $PROXMOX_ENV" >&2
  exit 1
fi

echo "== Audit log =="
if vault audit list -format=json | python3 -c "import json,sys; sys.exit(0 if 'file/' in json.load(sys.stdin) else 1)" 2>/dev/null; then
  echo "(ya estaba habilitado)"
else
  vault audit enable file file_path=/var/log/vault/audit.log
  echo "habilitado"
fi

echo "== KV v2 en secret/ =="
if vault secrets list -format=json | python3 -c "import json,sys; sys.exit(0 if 'secret/' in json.load(sys.stdin) else 1)" 2>/dev/null; then
  echo "(ya estaba habilitado)"
else
  vault secrets enable -path=secret -version=2 kv
  echo "habilitado"
fi

echo "== Politicas =="
vault policy write admin-limited "$REPO_ROOT/policies/admin-limited.hcl"
vault policy write proxmox-mcp-server "$REPO_ROOT/policies/proxmox-mcp-server.hcl"

echo "== AppRole auth method =="
if vault auth list -format=json | python3 -c "import json,sys; sys.exit(0 if 'approle/' in json.load(sys.stdin) else 1)" 2>/dev/null; then
  echo "(ya estaba habilitado)"
else
  vault auth enable approle
  echo "habilitado"
fi

echo "== Role proxmox-mcp-server =="
vault write auth/approle/role/proxmox-mcp-server \
  token_policies="proxmox-mcp-server" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_num_uses=0 \
  secret_id_ttl=0 >/dev/null

echo "== Migrando secretos de $PROXMOX_ENV a secret/proxmox-mcp-server =="
python3 - "$PROXMOX_ENV" <<'PYEOF'
import subprocess
import sys

env_path = sys.argv[1]
values = {}
with open(env_path) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        values[k.strip()] = v.strip()

args = ["vault", "kv", "put", "secret/proxmox-mcp-server"]
args += [f"{k}={v}" for k, v in values.items()]
subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
print(f"{len(values)} claves escritas en secret/proxmox-mcp-server (valores no impresos)")
PYEOF

echo "== Generando credenciales AppRole y escribiendolas en $PROXMOX_ENV =="
ROLE_ID="$(vault read -field=role_id auth/approle/role/proxmox-mcp-server/role-id)"
SECRET_ID="$(vault write -field=secret_id -f auth/approle/role/proxmox-mcp-server/secret-id)"

python3 - "$PROXMOX_ENV" "$VAULT_ADDR" "$VAULT_CACERT" "$ROLE_ID" "$SECRET_ID" <<'PYEOF'
import sys

env_path, vault_addr, vault_cacert, role_id, secret_id = sys.argv[1:6]

with open(env_path) as f:
    lines = [
        l for l in f
        if not l.startswith(("VAULT_ADDR=", "VAULT_CACERT=", "VAULT_ROLE_ID=", "VAULT_SECRET_ID="))
    ]

lines.append(f"VAULT_ADDR={vault_addr}\n")
lines.append(f"VAULT_CACERT={vault_cacert}\n")
lines.append(f"VAULT_ROLE_ID={role_id}\n")
lines.append(f"VAULT_SECRET_ID={secret_id}\n")

with open(env_path, "w") as f:
    f.writelines(lines)

print(f"Credenciales de AppRole agregadas a {env_path} (no impresas aqui)")
PYEOF

echo ""
echo "== Listo. Nada sensible se imprimio en esta terminal salvo lo que ya estaba en tu .env. =="
echo "== Siguiente paso IMPORTANTE: revoca el root token de esta sesion CLI: =="
echo "     vault token revoke -self"
echo "== Y borra el cache local: rm -f ~/.vault-token =="
