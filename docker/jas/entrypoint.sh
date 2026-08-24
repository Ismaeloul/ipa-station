#!/bin/sh
# Genera jas.toml desde el entorno, siembra la URL del anisette en el primer
# arranque y asegura una clave de cifrado persistente. Todo idempotente:
# despues del primer arranque no vuelve a tocar nada que hayas cambiado.
set -eu

DB_PATH="${JAS_DB:-/data/jas.db}"
IPA_DIR="${JAS_IPA_DIR:-/data/ipas}"
ANISETTE_URL="${ANISETTE_URL:-http://anisette:6969}"
BIND="${JAS_BIND:-0.0.0.0:3000}"
LOG_LEVEL="${JAS_LOG_LEVEL:-info}"
MDNS_ENABLED="${JAS_MDNS_ENABLED:-false}"
MDNS_INTERFACE="${JAS_MDNS_INTERFACE:-}"
INTERVAL_HOURS="${JAS_INTERVAL_HOURS:-2}"
REFRESH_WINDOW_DAYS="${JAS_REFRESH_WINDOW_DAYS:-3}"
WORKER_THREADS="${JAS_WORKER_THREADS:-2}"
CONFIG_PATH="${JAS_CONFIG:-/app/jas.toml}"
KEY_FILE="$(dirname "$DB_PATH")/secret.key"

mkdir -p "$(dirname "$DB_PATH")" "$IPA_DIR"

# ---------------------------------------------------------------------------
# Clave de cifrado
#
# Cifra los tokens de sesion de Apple y las claves privadas guardadas. Si se
# pierde, hay que volver a iniciar sesion con el Apple ID: por eso vive en el
# volumen persistente, junto a la base de datos que protege.
# ---------------------------------------------------------------------------
if [ -z "${JAS_SECRET_KEY:-}" ]; then
  if [ ! -f "$KEY_FILE" ]; then
    echo "[entrypoint] generando clave de cifrado en $KEY_FILE"
    sqlite3 :memory: "SELECT lower(hex(randomblob(32)));" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
  fi
  JAS_SECRET_KEY="$(cat "$KEY_FILE")"
  export JAS_SECRET_KEY
fi

# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------
cat > "$CONFIG_PATH" <<EOF
# Generado por entrypoint.sh en cada arranque. No edites este fichero:
# cambia las variables de entorno del docker-compose.yml.
[server]
bind = "$BIND"
log_level = "$LOG_LEVEL"

[storage]
database_path = "$DB_PATH"
ipa_dir = "$IPA_DIR"

[scheduler]
interval_hours = $INTERVAL_HOURS
refresh_window_days = $REFRESH_WINDOW_DAYS
worker_threads = $WORKER_THREADS

[security]
secret_key = ""

[discovery]
mdns_enabled = $MDNS_ENABLED
mdns_interface = "$MDNS_INTERFACE"
EOF

# ---------------------------------------------------------------------------
# Siembra del anisette
#
# jas lee _server/anisette_url UNA sola vez, al arrancar, y si no existe usa
# un servidor publico. Para que use el nuestro la fila tiene que estar puesta
# antes de que arranque el binario. Todas las migraciones de jas son
# CREATE TABLE IF NOT EXISTS, asi que crear esta tabla por adelantado no
# rompe nada. Solo se hace con la base de datos recien creada, para no pisar
# la URL si algun dia la cambias desde Ajustes.
# ---------------------------------------------------------------------------
if [ ! -f "$DB_PATH" ]; then
  echo "[entrypoint] base de datos nueva, apuntando al anisette $ANISETTE_URL"
  sqlite3 "$DB_PATH" \
    "CREATE TABLE IF NOT EXISTS sideload_storage (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
     INSERT OR IGNORE INTO sideload_storage (key, value)
       VALUES ('_server/anisette_url', '$ANISETTE_URL');" \
    || echo "[entrypoint] no se pudo sembrar; ponlo a mano en Ajustes > Anisette Server"
fi

echo "[entrypoint] arrancando jas en $BIND (db=$DB_PATH, ipas=$IPA_DIR)"
exec /app/jas
