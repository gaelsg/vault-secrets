# Especificación de Requisitos — Idea 2: Vault

Según proceso **SI.2** del Perfil Básico ISO/IEC 29110.

## Requisitos funcionales

| ID | Requisito |
|---|---|
| RF1 | Vault debe exponer un motor de secretos KV v2 en `secret/`, con una ruta por proyecto (`secret/proxmox-mcp-server`, `secret/nextcloud-mcp-server`, etc.) para que cada uno lea solo lo suyo. |
| RF2 | Debe existir una identidad programática (AppRole) por proyecto migrado, con una política que solo permite leer su propia ruta — no las de los demás proyectos. |
| RF3 | `proxmox-mcp-server` debe poder arrancar leyendo sus credenciales (tokens de Proxmox, API key de Portainer) desde Vault en vez de `.env`, sin cambiar su comportamiento funcional. |
| RF4 | Debe quedar un procedimiento documentado y reproducible de unseal manual (qué comando, cuántas llaves, en qué orden) para cuando el LXC se reinicie. |

## Requisitos no funcionales

| ID | Requisito |
|---|---|
| RNF1 | El listener de Vault debe usar TLS — nunca `tls_disable = true`, ni siquiera en homelab (es precisamente el hábito que vale la pena entrenar). |
| RNF2 | Ninguna llave de unseal ni el root token deben pasar por el asistente (Claude Code) en ningún momento — ni en el chat, ni en un archivo que el asistente lea. |
| RNF3 | El acceso de cada proyecto a Vault debe quedar acotado por política (RF2) — principio de mínimo privilegio, igual que con Proxmox/Portainer en ideas anteriores. |
| RNF4 | El audit log de Vault debe estar habilitado desde el bootstrap, no agregado después — cada lectura de secreto queda registrada con quién/qué la pidió. |
| RNF5 | Si Vault está configurado (`VAULT_ROLE_ID` presente) pero no responde al arrancar, el servidor debe fallar rápido y con un error claro — no arrancar en un estado a medias con credenciales incompletas. Si Vault *no* está configurado, debe arrancar normal contra lo que haya en el entorno (compatibilidad con desarrollo local sin Vault). |

## Trazabilidad
RF1-RF2 y RNF3 son la aplicación directa del patrón de mínimo privilegio ya usado en Proxmox (`mcp-agent`/`tofu@pve`) y Portainer, esta vez a nivel de gestión de secretos. RNF1-RNF2 responden al riesgo más alto identificado en el plan: exposición del material de sellado/root.
