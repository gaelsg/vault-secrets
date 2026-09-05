# 2026-09-05 — Primer segmento real de red: pve-firewall restringiendo Vault

Pedido del usuario dentro de la mejora de seguridad de red (después de Tailscale,
AdGuard, y TLS interno con `pki-ca`): usar `pve-firewall` (ya instalado en Proxmox,
nunca configurado) para reducir el radio de exposición. Se arrancó por Vault
(LXC 103) por ser el servicio más sensible del homelab — hoy alcanzable desde
cualquier punto de la LAN `192.168.8.0/24`.

## Diseño

Mapeo real de consumidores de `192.168.8.91:8200` (no hipotético, basado en lo que
efectivamente se construyó esta sesión y antes): la workstation (`pm-agent`,
`devops-multiagent`, los MCP servers, scripts `render-secrets.sh`), el propio host
`batman01` (`proxmox-autoupdate` autenticándose vía AppRole), y la LXC
`observability` (Prometheus scrapeando las métricas nativas de Vault). Nadie más
necesita el puerto 8200.

`/etc/pve/firewall/103.fw`: `policy_in: DROP`, con `ACCEPT` explícito para esos 3
orígenes en 8200, más SSH (22) desde la workstation para no perder el acceso de
administración. `policy_out: ACCEPT` sin cambios (Vault necesita salir a internet
para nada especial, pero no hay razón para restringir salida en esta vuelta).

## Incidente real: las reglas no se aplicaban

Primera corrida: `pve-firewall status` mostraba `enabled/running`, pero probando
desde una LXC explícitamente NO autorizada (`sso`, 192.168.8.94) el puerto 8200
seguía respondiendo `200` -- el firewall estaba activo pero **no enganchado a la
interfaz de red de la LXC**. Causa: en Proxmox, además de las reglas en el `.fw`
del guest, cada interfaz de red necesita su propio flag `firewall=1`
(`/etc/pve/lxc/103.conf`, línea `net0: ...`) para que `pve-firewall` de verdad
intercepte su tráfico -- sin eso, las reglas existen "en el papel" pero no se
enforcean. Nunca se seteó al crear la LXC vía OpenTofu (el módulo compartido no lo
incluía). Corregido en caliente: `pct set 103 -net0 ...,firewall=1` (sin reiniciar
la LXC), y corregido en el módulo (`proxmox-iac/modules/lxc/main.tf`) para que
toda LXC nueva lo traiga por defecto.

## Verificado real

- Antes del fix: `sso` (no autorizada) → `HTTP 200` contra Vault (falla de
  seguridad real, no hipotética).
- Después del fix: `sso` → `HTTP 000` (cortado); workstation y `observability`
  (ambas autorizadas) → `HTTP 200` sin cambios; SSH a la LXC de Vault verificado
  intacto.

## Pendiente

- Extender el mismo criterio (mapear consumidores reales, `policy_in: DROP` +
  allowlist) al resto de las LXC (Plane, SSO, PKI, Nextcloud, docker-host,
  observability, k3s) -- alcance recortado a propósito, Vault primero por ser la
  más sensible.
- Las LXC ya existentes (100-107 salvo la 103) no tienen `firewall=1` en su
  interfaz todavía -- el fix del módulo solo aplica a LXC *nuevas*; no se
  retro-aplicó a las existentes en esta vuelta porque no tienen reglas
  restrictivas propias, así que no cambia nada de seguridad activarlo ahí todavía.
- ACLs de Tailscale y `fail2ban` siguen en la lista de seguridad de red, sin tocar.
