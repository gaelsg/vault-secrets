ui = true

# Sin esto, "vault operator generate-root" (la ceremonia estandar para
# recuperar acceso admin usando las llaves de unseal, sin el root token
# original) devuelve 403 - endurecimiento por defecto en Vault 2.x que no
# existia en versiones anteriores. Se descubrio en la practica al revocar
# el root token del bootstrap inicial e intentar regenerarlo.
enable_unauthenticated_access = ["generate-root"]

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/vault-key.pem"
}

api_addr     = "https://192.168.8.91:8200"
cluster_addr = "https://192.168.8.91:8201"

# El LXC se provisiono sin swap (memory.swap = 0 en proxmox-iac) - el riesgo
# que mlock mitiga (secretos swappeados a disco) no aplica porque no hay
# swap al que puedan ir. Sin esto Vault no arranca dentro de un LXC sin
# privilegios (no tiene CAP_IPC_LOCK).
disable_mlock = true
