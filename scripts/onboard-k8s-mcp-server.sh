#!/usr/bin/env bash
# Onboarding de k8s-mcp-server en Vault, usando el AppRole vault-admin
# (creado en la Idea 2, scripts/admin-cleanup.sh) en vez de requerir un
# login interactivo con el root token -- primera vez que vault-admin se usa
# para lo que se penso: tareas administrativas rutinarias sin volver a
# tocar root/unseal.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ADMIN_APPROLE="$REPO_ROOT/.admin-approle"
KUBECONFIG_FILE="${1:?uso: onboard-k8s-mcp-server.sh <ruta-al-kubeconfig-de-solo-lectura>}"
TARGET_ENV="$HOME/projects/k8s-mcp-server/.env"

[ -f "$ADMIN_APPROLE" ] || { echo "No encuentro $ADMIN_APPROLE" >&2; exit 1; }
[ -f "$KUBECONFIG_FILE" ] || { echo "No encuentro $KUBECONFIG_FILE" >&2; exit 1; }
[ -f "$TARGET_ENV" ] || { echo "No encuentro $TARGET_ENV -- corre esto despues de crear el repo" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ADMIN_APPROLE"
set +a

echo "== Login con AppRole vault-admin =="
VAULT_TOKEN="$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
export VAULT_TOKEN

echo "== Politica k8s-mcp-server =="
vault policy write k8s-mcp-server "$REPO_ROOT/policies/k8s-mcp-server.hcl"

echo "== Role k8s-mcp-server =="
vault write auth/approle/role/k8s-mcp-server \
  token_policies="k8s-mcp-server" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_num_uses=0 \
  secret_id_ttl=0 >/dev/null

echo "== Escribiendo secret/k8s-mcp-server (kubeconfig de solo lectura) =="
vault kv put secret/k8s-mcp-server kubeconfig=@"$KUBECONFIG_FILE" >/dev/null

echo "== Generando credenciales AppRole y escribiendolas en $TARGET_ENV =="
ROLE_ID="$(vault read -field=role_id auth/approle/role/k8s-mcp-server/role-id)"
SECRET_ID="$(vault write -field=secret_id -f auth/approle/role/k8s-mcp-server/secret-id)"

python3 - "$TARGET_ENV" "$VAULT_ADDR" "$VAULT_CACERT" "$ROLE_ID" "$SECRET_ID" <<'PYEOF'
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

vault token revoke -self >/dev/null 2>&1 || true
echo "== Listo. Token de vault-admin de esta sesion revocado. =="
