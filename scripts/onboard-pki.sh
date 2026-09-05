#!/usr/bin/env bash
# Onboarding de pki-ca (step-ca) en Vault, mismo patron que onboard-sso.sh --
# AppRole vault-admin, nunca root/unseal.
#
# El password de la CA no es equivalente al quorum de unseal de Vault (no
# requiere ceremonia multi-parte, y perderlo se recupera regenerando la CA y
# re-confiando el root cert nuevo en los clientes) -- se trata como cualquier
# otro secreto de servicio del portafolio: nace en Vault, no en un archivo
# plano.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ADMIN_APPROLE="$REPO_ROOT/.admin-approle"
TARGET_ENV="${1:?uso: onboard-pki.sh <ruta-de-salida-.approle-env>}"

[ -f "$ADMIN_APPROLE" ] || { echo "No encuentro $ADMIN_APPROLE" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ADMIN_APPROLE"
set +a

echo "== Login con AppRole vault-admin =="
VAULT_TOKEN="$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
export VAULT_TOKEN

echo "== Politica pki =="
vault policy write pki "$REPO_ROOT/policies/pki.hcl"

echo "== Role pki =="
vault write auth/approle/role/pki \
  token_policies="pki" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_num_uses=0 \
  secret_id_ttl=0 >/dev/null

echo "== Generando y escribiendo secret/pki =="
STEPCA_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
vault kv put secret/pki STEPCA_PASSWORD="$STEPCA_PASSWORD" >/dev/null

echo "== Generando credenciales de AppRole en $TARGET_ENV =="
ROLE_ID="$(vault read -field=role_id auth/approle/role/pki/role-id)"
SECRET_ID="$(vault write -field=secret_id -f auth/approle/role/pki/secret-id)"

cat > "$TARGET_ENV" <<EOF
VAULT_ADDR=$VAULT_ADDR
VAULT_ROLE_ID=$ROLE_ID
VAULT_SECRET_ID=$SECRET_ID
EOF
chmod 600 "$TARGET_ENV"

vault token revoke -self >/dev/null 2>&1 || true
echo "== Listo. Credenciales de AppRole en $TARGET_ENV, secretos en Vault, nada impreso aqui. =="
