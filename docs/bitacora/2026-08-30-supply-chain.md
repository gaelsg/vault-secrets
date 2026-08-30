# 2026-08-30 — Credencial de Telegram duplicada a secret/observability

Parte de la Idea 8 (ver `k8s-mcp-server/docs/29110/idea8-supply-chain/`). Esta entrada es solo el lado de Vault.

## Cambio
`secret/observability` recibió `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID`, copiados desde `secret/devops-multiagent` con un script puntual corrido con el AppRole `vault-admin` (login, `vault kv get` del origen, `vault kv patch` del destino, `revoke -self`) — ningún valor pasó por la terminal del asistente en texto plano.

## Por qué copiar y no compartir acceso
El AppRole de `observability` solo tiene permiso de lectura sobre `secret/data/observability` — darle acceso a `secret/data/devops-multiagent` también hubiera roto el aislamiento por proyecto que es la base de toda la Idea 2. El bot de Telegram es un canal compartido entre proyectos, no propiedad de uno solo — la solución consistente con el patrón ya establecido es que cada proyecto que lo necesita tenga su propia copia de la credencial en su propio secreto.

## Nota operativa, resuelta en el momento
`vault kv patch` avisó que la política `admin-limited` no tenía la capability `patch` explícita — funcionó igual via el fallback de lectura-modificación-escritura (capabilities `create`/`update` que la política sí tenía), pero se agregó `patch` a `secret/*` en `admin-limited.hcl` de una vez en vez de dejarlo como pendiente para "la próxima" — era un cambio de una línea, sin motivo para posponerlo.
