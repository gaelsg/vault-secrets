# vault-secrets

Gestión centralizada de secretos para el homelab "Modo Ingeniería", vía [HashiCorp Vault](https://www.vaultproject.io/) OSS. Idea 2 de un roadmap de 6 (IaC → **Secretos** → Observabilidad → CI/CD → Evals de RAG → Kubernetes).

Reemplaza tokens estáticos de vida larga en archivos `.env` por secretos leídos en tiempo de ejecución, con acceso acotado por proyecto y auditado. Documentación formal bajo `docs/29110/` (Perfil Básico ISO/IEC 29110); `docs/bitacora/` es el diario de implementación — incluye los 7 incidentes reales del bootstrap, sin editar.

## Arquitectura

```
policies/                  # politicas HCL, versionadas
  admin-limited.hcl         # trabajo administrativo sin root
  proxmox-mcp-server.hcl    # solo-lectura de un proyecto
scripts/
  bootstrap.sh               # mount KV v2, politicas, AppRole, migracion inicial
  admin-cleanup.sh           # AppRole vault-admin + limpieza puntual
tls/
  ca-cert.pem                # CA propia (publica, versionada)
  ca-key.pem                 # (gitignored - nunca sale de la workstation)
vault.hcl                    # config real desplegada en el servidor
```

El LXC de Vault se provisiona desde [`proxmox-iac/environments/vault`](https://github.com/gaelsg/proxmox-iac), reusando el módulo de la Idea 1.

## Cómo funciona el acceso de un proyecto

1. Cada proyecto tiene su propia política (`policies/<proyecto>.hcl`) — solo puede leer `secret/data/<proyecto>`, nada más.
2. Un AppRole por proyecto (`role_id` + `secret_id`) autentica y obtiene un token de vida corta (1h, máx 4h).
3. El proyecto guarda `VAULT_ADDR`, `VAULT_CACERT`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID` en su propio `.env` — eso es lo único que queda ahí. Los secretos reales (tokens de Proxmox, API keys, etc.) viven solo en Vault.

Ver [`proxmox_mcp_server/secrets_loader.py`](https://github.com/gaelsg/proxmox-mcp-server/blob/master/src/proxmox_mcp_server/secrets_loader.py) para la implementación de referencia — cliente HTTP directo (`requests`), sin el SDK `hvac`, misma filosofía de "nada pesado" que el resto del proyecto.

## Seguridad: el material que nunca pasa por el asistente

Las 5 llaves de unseal y el root token del bootstrap **nunca** se comparten con Claude Code, ni en chat ni en un archivo que lea — se generan y manejan enteramente en la terminal del operador humano. Ver `docs/29110/idea2-vault/01-plan-proyecto.md` para el detalle de esta regla y por qué importa (a diferencia de un token de Proxmox, revocar el root de Vault sin plan de recuperación deja el sistema realmente inaccesible hasta juntar el quórum de llaves — se vivió en la práctica durante esta implementación).

Para trabajo administrativo rutinario después del bootstrap existe un AppRole `vault-admin` (política `admin-limited`, tokens de 30 min) — ni el usuario ni el asistente necesitan volver a tocar el root/las llaves de unseal salvo en una recuperación real de emergencia.

## Setup (resumen — ver bitácora para el paso a paso real, incluyendo lo que salió mal)

```bash
# 1. Provisionar el LXC (ver proxmox-iac/environments/vault)
# 2. Instalar Vault, desplegar vault.hcl y tls/vault-*.pem, systemctl enable --now vault
# 3. En tu propia terminal, nunca compartido:
export VAULT_ADDR="https://192.168.8.91:8200"
export VAULT_CACERT="$HOME/projects/vault-secrets/tls/ca-cert.pem"
vault operator init      # guarda las 5 llaves + root token en un gestor de contraseñas
vault operator unseal    # x3, con llaves distintas

vault login                          # con el root token
bash scripts/bootstrap.sh            # KV, politicas, AppRole, migracion
vault token revoke -self && rm -f ~/.vault-token
```
