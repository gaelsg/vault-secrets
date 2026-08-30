# Plan de Proyecto — Idea 2: Gestión de Secretos (HashiCorp Vault)

Según proceso **PM.1** del Perfil Básico ISO/IEC 29110.

## Objetivo
Reemplazar los `.env` con tokens estáticos de vida larga (usados en `proxmox-mcp-server`, `nextcloud-mcp-server`, `devops-multiagent`) por un secret manager centralizado, con acceso auditado y credenciales de trabajo distintas del secreto maestro.

## Alcance

**Incluye:**
- LXC dedicado, provisionado vía el módulo de OpenTofu de la Idea 1 (`proxmox-iac/environments/vault`).
- HashiCorp Vault OSS, Integrated Storage (Raft), listener TLS con CA propia (self-signed, de uso interno).
- Bootstrap: motor KV v2, política de administración no-root, AppRole para acceso programático.
- Migración real de al menos un proyecto existente (`proxmox-mcp-server`) para leer sus secretos de Vault en vez de `.env` estático, como prueba del patrón completo.
- Documentación 29110 + bitácora.

**No incluye:**
- Auto-unseal vía KMS de nube — no aplica a un homelab sin cuenta cloud; unseal queda manual (Shamir, 3 de 5 llaves), documentado como decisión consciente, no limitación.
- Rotación automática/dinámica de credenciales de Proxmox — Vault soporta "dynamic secrets" con plugins específicos por sistema; Proxmox no tiene uno oficial. Se queda en secretos estáticos gestionados centralmente (KV v2), no dinámicos — mejora de gestión y auditoría, no de rotación automática. Anotado como posible extensión futura.
- Migrar los 4 proyectos completos en esta pasada — se prueba el patrón end-to-end con uno; el resto queda documentado como pendiente explícito, no silencioso.

## Entregables
1. `proxmox-iac/environments/vault` — LXC provisionado.
2. Repo `vault-secrets` — políticas HCL, scripts de bootstrap y de migración, documentación.
3. `proxmox-mcp-server` actualizado para leer sus credenciales de Vault en runtime.
4. Esta serie de documentos 29110 + bitácora.

## Riesgos identificados
| Riesgo | Mitigación |
|---|---|
| Las llaves de unseal o el root token quedan expuestas en un chat/log | `vault operator init` y `vault operator unseal` los corre el usuario en su propia terminal, nunca vía el asistente ni pegados en la conversación. El asistente jamás ve ese material. |
| El root token se sigue usando para trabajo cotidiano (mala práctica reconocida de Vault) | Se crea una política de administración limitada inmediatamente después del bootstrap; el root token se revoca (`vault token revoke`) una vez que esa política funciona. |
| Vault sellado (`sealed`) tras un reinicio del LXC deja todo inaccesible sin aviso | Se documenta explícitamente el procedimiento de unseal manual; se acepta como comportamiento esperado de Vault sin auto-unseal, no como bug. |
| Migrar un proyecto a Vault y dejarlo roto si Vault no está disponible | `proxmox-mcp-server` mantiene fallback a `.env` si Vault no responde, documentado como decisión explícita para no crear un punto único de fallo en un servidor MCP que se usa a diario. |

## Criterios de aceptación
- Vault corre con TLS, Raft, e inicializado — verificado con `vault status` (sin ver las llaves).
- Existe una política no-root capaz de leer/escribir en `secret/` sin poder gestionar Vault mismo (crear políticas, sellar/desellar, gestionar auth methods).
- `proxmox-mcp-server` arranca y opera correctamente leyendo sus tokens desde Vault, con el `.env` real *removido* de la máquina (no solo dejado sin usar).
- El root token no se usa para ninguna operación después del bootstrap inicial.
