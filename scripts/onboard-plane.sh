#!/usr/bin/env bash
# Onboarding de Plane (LXC 105) en Vault, mismo patron que
# onboard-k8s-mcp-server.sh: usa el AppRole vault-admin, nunca root/unseal.
#
# A diferencia de los demas proyectos del portafolio, las credenciales de
# Plane (Postgres, RabbitMQ, MinIO, Django SECRET_KEY, live-server secret
# key) no nacieron en Vault -- las genero el propio instalador oficial de
# Plane (`setup.sh`) directo en plane.env, en el LXC. Este script las trae
# a Vault como copia de respaldo/fuente de verdad (antes solo existian en
# un archivo plano en el disco de un unico LXC), y deja un AppRole de
# solo lectura listo para cuando algo necesite consumirlas en el futuro
# (ej. un script de render/restore si se recrea el LXC).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ADMIN_APPROLE="$REPO_ROOT/.admin-approle"
PLANE_HOST="root@192.168.8.93"
PLANE_ENV_REMOTE="/opt/plane-app/plane-app/plane.env"
SSH_KEY="$HOME/.ssh/id_ed25519_iac"

[ -f "$ADMIN_APPROLE" ] || { echo "No encuentro $ADMIN_APPROLE" >&2; exit 1; }

TMP_ENV="$(mktemp)"
trap 'shred -u "$TMP_ENV" 2>/dev/null || rm -f "$TMP_ENV"' EXIT

echo "== Trayendo plane.env desde el LXC (no queda copia mas que este temporal) =="
scp -i "$SSH_KEY" -q "$PLANE_HOST:$PLANE_ENV_REMOTE" "$TMP_ENV"

get_val() { grep -E "^$1=" "$TMP_ENV" | head -1 | cut -d= -f2-; }

POSTGRES_PASSWORD="$(get_val POSTGRES_PASSWORD)"
RABBITMQ_PASSWORD="$(get_val RABBITMQ_PASSWORD)"
SECRET_KEY="$(get_val SECRET_KEY)"
AWS_ACCESS_KEY_ID="$(get_val AWS_ACCESS_KEY_ID)"
AWS_SECRET_ACCESS_KEY="$(get_val AWS_SECRET_ACCESS_KEY)"
LIVE_SERVER_SECRET_KEY="$(get_val LIVE_SERVER_SECRET_KEY)"
# DATABASE_URL/AMQP_URL son las credenciales que Django realmente usa (no
# POSTGRES_PASSWORD/RABBITMQ_PASSWORD sueltos) -- el docker-compose.yaml de
# Plane tiene `${DATABASE_URL:-postgresql://plane:plane@plane-db/plane}` y
# el equivalente para AMQP_URL: si el valor en plane.env queda vacio, ese
# fallback HARDCODEADO EN EL YAML (con la password placeholder vieja) es lo
# que termina usando la app, sin importar lo que diga POSTGRES_PASSWORD.
# Incidente real 2026-09-01, ver docs/bitacora/.
DATABASE_URL="$(get_val DATABASE_URL)"
AMQP_URL="$(get_val AMQP_URL)"

set -a
# shellcheck disable=SC1090
source "$ADMIN_APPROLE"
set +a

echo "== Login con AppRole vault-admin =="
VAULT_TOKEN="$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
export VAULT_TOKEN

echo "== Politica plane =="
vault policy write plane "$REPO_ROOT/policies/plane.hcl"

echo "== Role plane =="
vault write auth/approle/role/plane \
  token_policies="plane" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_num_uses=0 \
  secret_id_ttl=0 >/dev/null

echo "== Escribiendo secret/plane =="
vault kv put secret/plane \
  postgres_password="$POSTGRES_PASSWORD" \
  rabbitmq_password="$RABBITMQ_PASSWORD" \
  django_secret_key="$SECRET_KEY" \
  minio_access_key="$AWS_ACCESS_KEY_ID" \
  minio_secret_key="$AWS_SECRET_ACCESS_KEY" \
  live_server_secret_key="$LIVE_SERVER_SECRET_KEY" \
  database_url="$DATABASE_URL" \
  amqp_url="$AMQP_URL" >/dev/null

vault token revoke -self >/dev/null 2>&1 || true
echo "== Listo. secret/plane escrito, token de vault-admin de esta sesion revocado. =="
