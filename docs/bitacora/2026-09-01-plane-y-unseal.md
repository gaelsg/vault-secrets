# 2026-09-01 — secret/plane + script de unseal interactivo

## `secret/plane`

Primer proyecto del portafolio cuyas credenciales no nacieron en Vault: el instalador oficial de
Plane (`setup.sh`) las genera solo en `plane.env`, dentro del LXC 105. `scripts/onboard-plane.sh`
las trae a `secret/plane` (política + AppRole `plane`, mismo patrón de mínimo privilegio que el
resto de los proyectos) usando `vault-admin` — nunca root. El archivo se trae por `scp` a un
temporal y se `shred`ea al salir, no queda ninguna copia adicional en la workstation.

## `scripts/unseal.sh`

El usuario pidió un script para automatizar el unseal completo pasando las keys como variables
que él mismo edite en un archivo. Se le señaló el problema antes de escribirlo: eso significa una
copia en texto plano del quórum completo de unseal keys viviendo en disco indefinidamente — justo
lo que la regla original de este repo evita (las keys solo existen en el gestor de contraseñas del
usuario, tipeadas frescas cada vez). Se propuso una alternativa que ahorra el mismo tiempo sin ese
riesgo: un script que pide cada key con `read -s` (sin eco, sin bash history, sin escribir a
disco en ningún momento), leyendo el umbral real (`t`) desde `vault status` en vez de asumir 3.
Aceptado por el usuario sin objeción. Probado en vivo: desselló el Vault de producción
correctamente.
