#!/usr/bin/env bash
# Compila las dos imagenes EN EL PROPIO UMBREL. Es la unica forma prevista:
# las imagenes no se publican en ningun registro, ni hace falta. Todo el
# stack se construye y vive en el NAS.
#
# Uso, por SSH en el Umbrel:
#
#   git clone https://github.com/Ismaeloul/ipa-station.git
#   cd ipa-station
#   bash scripts/build-on-umbrel.sh
#
# Tarda. En un N300 cuenta entre 40 y 90 minutos la primera vez: jas es Rust
# mas WebAssembly y hay que compilar tambien cargo-leptos. Lanzalo con screen
# o tmux si te preocupa perder la sesion SSH.
set -euo pipefail

VERSION="${1:-0.1.0}"
# Trabajos de compilacion en paralelo. Por defecto la mitad de los hilos, para
# que Jellyfin, Immich y AceStream sigan respondiendo mientras esto compila.
JOBS="${2:-4}"
IMAGE_NS="ipa-station"

cd "$(dirname "$0")/.."

echo "==> Comprobando requisitos"
command -v docker >/dev/null || { echo "Falta docker"; exit 1; }
docker info >/dev/null 2>&1 || { echo "El demonio de docker no responde"; exit 1; }

AVAIL_GB=$(df -BG --output=avail . | tail -1 | tr -dc '0-9')
if [ "${AVAIL_GB:-0}" -lt 15 ]; then
  echo "AVISO: quedan ${AVAIL_GB}G libres. Compilar Rust come disco; 15G es lo minimo comodo."
fi

# Nombres locales a proposito: estas imagenes no viven en ningun registro, ni
# falta que hace. Un nombre tipo ghcr.io/... daria a entender que se pueden
# descargar de algun sitio, y no es el caso. Los docker-compose.yml usan estos
# mismos nombres con pull_policy: never.
build () {
  local name="$1" context="$2"; shift 2
  echo
  echo "==> Compilando $name  (contexto: $context)"
  local t0=$SECONDS
  docker build "$@" \
    --tag "${IMAGE_NS}/${name}:${VERSION}" \
    --tag "${IMAGE_NS}/${name}:latest" \
    "$context"
  echo "==> $name listo en $(( (SECONDS - t0) / 60 )) min"
}

# El anisette primero: es el rapido, y si algo esta mal en el entorno se ve
# enseguida en vez de a la hora de compilar Rust.
build "anisette-v3-server" "docker/anisette"
build "jas"                "docker/jas" --build-arg "CARGO_JOBS=${JOBS}"

echo
echo "==> Imagenes disponibles"
docker images --filter "reference=${IMAGE_NS}/*" \
  --format '  {{.Repository}}:{{.Tag}}  {{.Size}}'

cat <<EOF

==> Hecho.

Ya puedes instalar IPA Station desde la tienda de Umbrel: encontrara las
imagenes en local y no necesitara descargar nada.

Si la instalacion falla igualmente con un error de descarga, es que Umbrel
esta forzando un pull. En ese caso anade esta linea a los servicios 'jas' y
'anisette' de umbrel/ismaeloul-ipa-station/docker-compose.yml:

    pull_policy: never

EOF
