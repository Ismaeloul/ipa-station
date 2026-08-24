#!/usr/bin/env bash
# Comprobaciones previas y de diagnostico, para ejecutar EN EL UMBREL por SSH:
#
#   bash check-umbrel.sh 192.168.1.50      # IP del iPhone
#
# No instala nada ni toca la configuracion de Umbrel. Solo mira.
#
# Nota: aqui no hace falta libimobiledevice ni usbmuxd. Este stack no habla
# con el iPhone por USB en ningun momento, asi que no hay dependencias que
# instalar en el host.
set -u

IPHONE_IP="${1:-}"
APP_PORT=7795
RSD_PORT=49152

ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mFALLO\033[0m %s\n' "$1"; }
warn() { printf '  \033[33mAVISO\033[0m %s\n' "$1"; }

echo
echo "=== 1. Puerto $APP_PORT libre en el host ==="
if command -v ss >/dev/null 2>&1; then
  if ss -ltn "( sport = :$APP_PORT )" 2>/dev/null | grep -q ":$APP_PORT"; then
    bad "el puerto $APP_PORT ya esta ocupado. Cambia 'port:' en umbrel-app.yml"
    ss -ltnp "( sport = :$APP_PORT )" 2>/dev/null | tail -n +2
  else
    ok "puerto $APP_PORT libre"
  fi
else
  warn "sin 'ss' para comprobarlo"
fi

echo
echo "=== 2. Puertos ya usados por tus otras apps ==="
# 7788 nutritrack, 7791/7792 ace player, 8449 craftdeck, 8095 AdGuard,
# 3005 umbrel-share, 8621/8622 motores AceStream, 11434 Ollama.
for p in 7788 7791 7792 8095 8449 3005 8621 8622 11434; do
  if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$p )" 2>/dev/null | grep -q ":$p"; then
    printf '  en uso: %s\n' "$p"
  fi
done
echo "  (el $APP_PORT no aparece en esta lista, por eso lo hemos elegido)"

echo
echo "=== 3. Contenedores del stack ==="
if command -v docker >/dev/null 2>&1; then
  docker ps --filter "name=ipa-station" --format '  {{.Names}}  {{.Status}}' 2>/dev/null
  docker ps --filter "name=ismaeloul-ipa-station" --format '  {{.Names}}  {{.Status}}' 2>/dev/null
else
  warn "docker no accesible desde este usuario"
fi

echo
echo "=== 4. Anisette responde ==="
ANI=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -m1 anisette || true)
if [ -n "$ANI" ]; then
  if docker exec "$ANI" curl -fsS http://127.0.0.1:6969/v3/client_info >/dev/null 2>&1; then
    ok "$ANI contesta en /v3/client_info"
  else
    bad "$ANI no contesta. Mira: docker logs $ANI"
  fi
else
  warn "contenedor de anisette no encontrado (aun no instalado?)"
fi

echo
echo "=== 5. iPhone alcanzable ==="
if [ -z "$IPHONE_IP" ]; then
  warn "no has pasado la IP del iPhone. Uso: bash check-umbrel.sh 192.168.1.50"
else
  # El iPhone escucha en 49152 mientras este emparejado y en la misma red,
  # incluso con la pantalla apagada.
  if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$IPHONE_IP/$RSD_PORT" 2>/dev/null; then
    ok "$IPHONE_IP:$RSD_PORT acepta conexiones"
  else
    bad "$IPHONE_IP:$RSD_PORT no responde"
    echo "        - comprueba que la IP es la correcta (Ajustes > Wi-Fi > (i))"
    echo "        - el iPhone debe estar en la MISMA red que el Umbrel"
    echo "        - si tienes aislamiento de clientes en el router, desactivalo"
  fi

  # Desde dentro del contenedor: confirma que la red bridge alcanza la LAN.
  JAS=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -m1 jas || true)
  if [ -n "$JAS" ]; then
    if docker exec "$JAS" timeout 5 curl -s "telnet://$IPHONE_IP:$RSD_PORT" >/dev/null 2>&1; then
      ok "el contenedor $JAS tambien lo alcanza"
    else
      warn "el contenedor no lo alcanza aunque el host si: revisa la red bridge"
    fi
  fi
fi

echo
