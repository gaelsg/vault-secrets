# Diseño — Idea 2: Vault

Según proceso **SI.3** del Perfil Básico ISO/IEC 29110.

## Arquitectura

```
proxmox-iac/environments/vault/   → LXC dedicado (mismo modulo de la Idea 1)

vault-secrets/
├── policies/
│   ├── admin-limited.hcl         → politica de administracion sin root
│   └── proxmox-mcp-server.hcl    → politica de solo-lectura de un proyecto
├── scripts/
│   ├── bootstrap.sh              → mount KV, politicas, AppRole, migracion inicial
│   └── admin-cleanup.sh          → AppRole vault-admin + limpieza puntual
├── tls/                          → CA propia (clave privada NUNCA committeada)
└── vault.hcl                     → config real del servidor (raft, TLS, etc.)

proxmox-mcp-server/
└── src/proxmox_mcp_server/secrets_loader.py   → cliente AppRole, inyecta en os.environ
```

## Flujo de secretos

1. `proxmox-mcp-server/.env` ya no tiene tokens de Proxmox/Portainer — solo `VAULT_ADDR`, `VAULT_CACERT`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID` (credencial de AppRole, acotada a leer únicamente `secret/proxmox-mcp-server`).
2. Al arrancar, `secrets_loader.load_secrets_from_vault()` hace login AppRole, lee `secret/data/proxmox-mcp-server`, e inyecta cada clave en `os.environ`.
3. El resto del código (`server.py`, `docker_tools.py`) no cambió — sigue leyendo `os.environ["PROXMOX_TOKEN_VALUE"]` etc. igual que siempre. El cambio es de dónde vienen esos valores, no de cómo se consumen.

## Decisiones técnicas

**Cliente propio con `requests`, no `hvac`.** El SDK oficial de Python para Vault (`hvac`) es una dependencia más para una operación de dos llamadas HTTP (login + read). Se prefirió mantener la huella mínima, mismo criterio que el dashboard de `devops-multiagent` ("nada pesado").

**Fail-fast, no fallback silencioso a `.env`.** El plan original (`01-plan-proyecto.md`) proponía mantener un fallback a `.env` si Vault no respondía. Al implementar se decidió lo contrario: si `VAULT_ROLE_ID` está presente pero Vault no responde, el servidor **falla al arrancar** con un error claro, en vez de arrancar con credenciales parciales o reusar una copia local potencialmente obsoleta. Arrancar roto-pero-silencioso es peor que negarse a arrancar. Si Vault no está configurado en absoluto (sin `VAULT_ROLE_ID`), sí arranca contra el entorno normal — eso cubre desarrollo local sin Vault, que es el caso real de "no depender de un único punto de fallo", no una copia de secretos duplicada. Ver RNF5 actualizado en el documento de requisitos.

**AppRole, no tokens de vida larga.** El rol `proxmox-mcp-server` emite tokens de 1h (máximo 4h) por login — el `role_id`/`secret_id` en `.env` no son ellos mismos el secreto final, son credenciales para *pedir* un token de corta vida. Igual patrón para `vault-admin` (30min/2h), usado por el asistente para tareas administrativas rutinarias sin volver a tocar el root token.

**Política por proyecto, no una política compartida.** `proxmox-mcp-server.hcl` solo puede leer su propia ruta (`secret/data/proxmox-mcp-server`) — ni listar, ni ver las de otros proyectos que se migren después. Mismo principio de mínimo privilegio que Proxmox/Portainer.

**CA propia, TLS obligatorio.** Certificado generado localmente (`tls/ca-*.pem`), la clave privada de la CA nunca sale de la workstation ni se versiona. El certificado público (`ca-cert.pem`) sí se versiona — es lo que cualquier cliente necesita para verificar la conexión.

**Raft (Integrated Storage), no `file`.** El paquete de Vault trae `storage "file"` por defecto; se reemplazó por `raft` — es la recomendación actual de HashiCorp incluso para un solo nodo (HA-capable sin depender de Consul), y es lo que de verdad se usa en despliegues reales.

**`disable_mlock = true`, justificado, no un descuido.** Sin `CAP_IPC_LOCK` (no disponible en un LXC sin privilegios), Vault no arranca con `mlock` activo. El riesgo que `mlock` mitiga — secretos en memoria terminando en swap — no aplica aquí porque el LXC se provisionó sin swap (`memory.swap = 0` en `proxmox-iac`). La mitigación real vive en la capa de infraestructura, no en Vault.

## Fuera de diseño (explícitamente)
- Migrar `nextcloud-mcp-server` y `devops-multiagent` (Telegram) a Vault — mismo patrón exacto que `proxmox-mcp-server`, pendiente documentado, no bloqueante para cerrar esta idea.
- Rotación dinámica de credenciales de Proxmox — Vault no tiene plugin oficial para Proxmox; se queda en gestión centralizada de secretos estáticos, no en secretos dinámicos con TTL real.
