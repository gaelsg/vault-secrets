#!/usr/bin/env bash
# Desella Vault interactivamente -- un solo comando en vez de repetir
# "vault operator unseal" 3 veces a mano. A proposito NO acepta las keys
# como argumentos ni variables de entorno hardcodeadas en un archivo: las
# pide una por una con `read -s` (no se muestran en pantalla, no quedan en
# el historial de bash, no se escriben a disco en ningun momento). Las
# keys siguen viviendo solo en tu gestor de contrasenas -- este script
# solo evita el tipeo repetido de "vault operator unseal" y el export de
# VAULT_ADDR/VAULT_CACERT cada vez.
set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-https://192.168.8.91:8200}"
export VAULT_CACERT="${VAULT_CACERT:-$HOME/projects/vault-secrets/tls/ca-cert.pem}"

echo "Desellando Vault en $VAULT_ADDR"

status="$(vault status -format=json 2>/dev/null || true)"
threshold="$(echo "$status" | grep -o '"t":[0-9]*' | head -1 | cut -d: -f2)"
threshold="${threshold:-3}"

for i in $(seq 1 "$threshold"); do
  read -rs -p "Unseal key $i/$threshold: " key
  echo
  vault operator unseal "$key" >/dev/null
  unset key
done

echo
vault status
