#!/usr/bin/env bash
# Limpieza puntual + AppRole de admin-limited para uso futuro del asistente,
# para no tener que repetir la ceremonia de generate-root en cada ajuste
# administrativo rutinario. Requiere estar logueado con un root token
# temporal (via generate-root), igual que bootstrap.sh.
set -euo pipefail

: "${VAULT_ADDR:?export VAULT_ADDR primero}"
: "${VAULT_CACERT:?export VAULT_CACERT primero}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROXMOX_ENV="$HOME/projects/proxmox-mcp-server/.env"
ADMIN_CREDS_FILE="$REPO_ROOT/.admin-approle"

echo "== 1. Limpiando secret/proxmox-mcp-server (quitando claves VAULT_* que se colaron) =="
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
        if k.strip().startswith("VAULT_"):
            continue
        values[k.strip()] = v.strip()

args = ["vault", "kv", "put", "secret/proxmox-mcp-server"]
args += [f"{k}={v}" for k, v in values.items()]
subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
print(f"{len(values)} claves limpias reescritas (valores no impresos)")
PYEOF

echo "== 2. Revocando secret_id huerfanos del role proxmox-mcp-server =="
CURRENT_SECRET_ID="$(grep '^VAULT_SECRET_ID=' "$PROXMOX_ENV" | cut -d= -f2-)"
CURRENT_ACCESSOR="$(vault write -field=secret_id_accessor -f auth/approle/role/proxmox-mcp-server/secret-id/lookup secret_id="$CURRENT_SECRET_ID" 2>/dev/null || true)"

vault list -format=json auth/approle/role/proxmox-mcp-server/secret-id 2>/dev/null | python3 -c "
import json, sys, subprocess
accessors = json.load(sys.stdin)
current = '$CURRENT_ACCESSOR'
for acc in accessors:
    if acc == current:
        print(f'  conservando accessor actual: {acc}')
        continue
    subprocess.run(
        ['vault', 'write', '-f', 'auth/approle/role/proxmox-mcp-server/secret-id-accessor/destroy',
         f'secret_id_accessor={acc}'],
        check=True, stdout=subprocess.DEVNULL,
    )
    print(f'  revocado accessor huerfano: {acc}')
"

echo "== 3. AppRole de admin-limited (para uso futuro del asistente, sin volver a tocar root) =="
if ! vault read auth/approle/role/vault-admin >/dev/null 2>&1; then
  vault write auth/approle/role/vault-admin \
    token_policies="admin-limited" \
    token_ttl=30m \
    token_max_ttl=2h \
    secret_id_num_uses=0 \
    secret_id_ttl=0 >/dev/null
  echo "role vault-admin creado"
else
  echo "(role vault-admin ya existia)"
fi

ADMIN_ROLE_ID="$(vault read -field=role_id auth/approle/role/vault-admin/role-id)"
ADMIN_SECRET_ID="$(vault write -field=secret_id -f auth/approle/role/vault-admin/secret-id)"

cat > "$ADMIN_CREDS_FILE" <<EOF
VAULT_ADDR=$VAULT_ADDR
VAULT_CACERT=$VAULT_CACERT
VAULT_ROLE_ID=$ADMIN_ROLE_ID
VAULT_SECRET_ID=$ADMIN_SECRET_ID
EOF
chmod 600 "$ADMIN_CREDS_FILE"
echo "Credenciales de vault-admin escritas en $ADMIN_CREDS_FILE (no impresas aqui, gitignored)"

echo ""
echo "== Listo. Token de admin de vida corta (30min/2h max) via AppRole, no un token de pie de vida infinita =="
echo "== Siguiente paso IMPORTANTE: vault token revoke -self && rm -f ~/.vault-token =="
