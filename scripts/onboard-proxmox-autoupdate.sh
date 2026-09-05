#!/usr/bin/env bash
# Onboarding de proxmox-autoupdate en Vault, mismo patron que
# onboard-k8s-mcp-server.sh (AppRole vault-admin, nunca root/unseal).
#
# El bot de Telegram ya existe (nacio en secret/devops-multiagent, y ya se
# habia duplicado una vez a secret/observability para el escaneo semanal de
# imagenes -- mismo criterio: credencial duplicada por consumidor, no
# AppRole compartido). Esta es la tercera copia, para el notificador de
# actualizaciones de Proxmox que corre en el host batman01, fuera de
# cualquier LXC.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ADMIN_APPROLE="$REPO_ROOT/.admin-approle"
TARGET_ENV="${1:?uso: onboard-proxmox-autoupdate.sh <ruta-de-salida-vault.env>}"

[ -f "$ADMIN_APPROLE" ] || { echo "No encuentro $ADMIN_APPROLE" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ADMIN_APPROLE"
set +a

echo "== Login con AppRole vault-admin =="
VAULT_TOKEN="$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
export VAULT_TOKEN

echo "== Leyendo credencial de Telegram existente (secret/devops-multiagent) =="
BOT_TOKEN="$(vault kv get -field=TELEGRAM_BOT_TOKEN secret/devops-multiagent)"
CHAT_ID="$(vault kv get -field=TELEGRAM_CHAT_ID secret/devops-multiagent)"

echo "== Politica proxmox-autoupdate =="
vault policy write proxmox-autoupdate "$REPO_ROOT/policies/proxmox-autoupdate.hcl"

echo "== Role proxmox-autoupdate =="
vault write auth/approle/role/proxmox-autoupdate \
  token_policies="proxmox-autoupdate" \
  token_ttl=15m \
  token_max_ttl=30m \
  secret_id_num_uses=0 \
  secret_id_ttl=0 >/dev/null

echo "== Escribiendo secret/proxmox-autoupdate =="
vault kv put secret/proxmox-autoupdate \
  TELEGRAM_BOT_TOKEN="$BOT_TOKEN" \
  TELEGRAM_CHAT_ID="$CHAT_ID" >/dev/null

echo "== Generando credenciales de AppRole en $TARGET_ENV =="
ROLE_ID="$(vault read -field=role_id auth/approle/role/proxmox-autoupdate/role-id)"
SECRET_ID="$(vault write -field=secret_id -f auth/approle/role/proxmox-autoupdate/secret-id)"

cat > "$TARGET_ENV" <<EOF
VAULT_ADDR=$VAULT_ADDR
VAULT_ROLE_ID=$ROLE_ID
VAULT_SECRET_ID=$SECRET_ID
EOF
chmod 600 "$TARGET_ENV"

vault token revoke -self >/dev/null 2>&1 || true
echo "== Listo. Credenciales escritas en $TARGET_ENV (no impresas aqui), token de vault-admin revocado. =="
