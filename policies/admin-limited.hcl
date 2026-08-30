# Politica de administracion para trabajo cotidiano en Vault, sin las
# capacidades reservadas al root token/llaves de unseal: no puede sellar,
# resellar, regenerar un root token (sys/generate-root) ni rotar llaves de
# unseal (sys/rekey). Alguien con este token no puede escalar de vuelta a
# root sin las 3 llaves de unseal.

path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
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
