# Politica de administracion para trabajo cotidiano en Vault, sin las
# capacidades reservadas al root token/llaves de unseal: no puede sellar,
# resellar, regenerar un root token (sys/generate-root) ni rotar llaves de
# unseal (sys/rekey). Alguien con este token no puede escalar de vuelta a
# root sin las 3 llaves de unseal.

path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/approle/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/audit" {
  capabilities = ["read", "sudo"]
}

path "sys/audit/*" {
  capabilities = ["create", "read", "sudo"]
}

# Solo tomar snapshots (backup), no restaurarlos. Restaurar sobreescribe
# TODO el dataset de Vault -- mismo criterio que excluir seal/rekey/
# generate-root: una operacion de alto impacto y poco frecuente se deja
# fuera del AppRole de uso diario, no porque no se confie en el, sino
# porque un "break glass" real deberia pasar por una decision deliberada
# (root token), no ser posible con un token de 30 min que rota solo.
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
