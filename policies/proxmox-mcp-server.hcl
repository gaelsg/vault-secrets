# Solo lectura de su propia ruta - ni siquiera puede listar otros proyectos.

path "secret/data/proxmox-mcp-server" {
  capabilities = ["read"]
}

path "secret/metadata/proxmox-mcp-server" {
  capabilities = ["read"]
}
