#!/usr/bin/env bash
# Backup diario del dataset de Vault (Raft snapshot), corrido desde la
# workstation -- distinto dominio de falla que el LXC de Vault (server
# fisico distinto). Usa el AppRole vault-admin (Idea 2), que solo puede
# TOMAR snapshots, no restaurarlos (ver policies/admin-limited.hcl) -- una
# restauracion real es un "break glass" deliberado con el root token, no
# algo que un token de 30 min que corre por timer deberia poder hacer.
#
# El archivo resultante contiene el dataset cifrado con la barrier key de
# Vault (derivada de las llaves de unseal) -- no es texto plano, pero
# tampoco es publico: se guarda fuera de git, con permisos 600.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADMIN_APPROLE="$REPO_ROOT/.admin-approle"
BACKUP_DIR="$HOME/vault-backups"
KEEP_DAYS=14

[ -f "$ADMIN_APPROLE" ] || { echo "No encuentro $ADMIN_APPROLE" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

set -a
# shellcheck disable=SC1090
source "$ADMIN_APPROLE"
set +a

VAULT_TOKEN="$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
export VAULT_TOKEN

OUT_FILE="$BACKUP_DIR/vault-snapshot-$(date +%Y%m%d-%H%M%S).snap"
vault operator raft snapshot save "$OUT_FILE"
chmod 600 "$OUT_FILE"
echo "Snapshot guardado: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"

# Retencion: borra snapshots mas viejos que KEEP_DAYS.
find "$BACKUP_DIR" -name 'vault-snapshot-*.snap' -mtime "+$KEEP_DAYS" -delete

vault token revoke -self >/dev/null 2>&1 || true
echo "Listo. Token de esta corrida revocado."
