#!/usr/bin/env bash
# Onboarding de sso (Authentik) en Vault, mismo patron que
# onboard-k8s-mcp-server.sh -- AppRole vault-admin, nunca root/unseal.
#
# A diferencia de Plane (cuyas credenciales las genero el instalador oficial
# y se trajeron a Vault despues), aca el password de Postgres y el
# AUTHENTIK_SECRET_KEY nacen en Vault desde el dia uno -- mismo criterio que
# observability, ya que Authentik no trae un instalador propio que las
# genere por nosotros.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ADMIN_APPROLE="$REPO_ROOT/.admin-approle"
TARGET_ENV="${1:?uso: onboard-sso.sh <ruta-de-salida-.approle-env>}"

[ -f "$ADMIN_APPROLE" ] || { echo "No encuentro $ADMIN_APPROLE" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ADMIN_APPROLE"
set +a

echo "== Login con AppRole vault-admin =="
VAULT_TOKEN="$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
export VAULT_TOKEN

echo "== Politica sso =="
vault policy write sso "$REPO_ROOT/policies/sso.hcl"

echo "== Role sso =="
vault write auth/approle/role/sso \
  token_policies="sso" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_num_uses=0 \
  secret_id_ttl=0 >/dev/null

echo "== Generando y escribiendo secret/sso =="
# tr -d '\n': openssl rand -base64 inserta un salto de linea cada 64
# caracteres -- sin esto el valor queda partido en 2 lineas dentro del .env
# y docker compose lo interpreta como una variable nueva invalida.
PG_PASS="$(openssl rand -base64 32 | tr -d '\n')"
AUTHENTIK_SECRET_KEY="$(openssl rand -base64 60 | tr -d '\n')"
vault kv put secret/sso \
  PG_PASS="$PG_PASS" \
  AUTHENTIK_SECRET_KEY="$AUTHENTIK_SECRET_KEY" >/dev/null

echo "== Generando credenciales de AppRole en $TARGET_ENV =="
ROLE_ID="$(vault read -field=role_id auth/approle/role/sso/role-id)"
SECRET_ID="$(vault write -field=secret_id -f auth/approle/role/sso/secret-id)"

cat > "$TARGET_ENV" <<EOF
VAULT_ADDR=$VAULT_ADDR
VAULT_ROLE_ID=$ROLE_ID
VAULT_SECRET_ID=$SECRET_ID
EOF
chmod 600 "$TARGET_ENV"

vault token revoke -self >/dev/null 2>&1 || true
echo "== Listo. Credenciales de AppRole en $TARGET_ENV, secretos en Vault, nada impreso aqui. =="
