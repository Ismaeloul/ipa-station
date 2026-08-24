#!/usr/bin/env bash
# Compila las dos imagenes EN EL PROPIO UMBREL, sin pasar por GitHub Actions
# ni por GHCR. Util si Actions no esta disponible, o si prefieres no depender
# de infraestructura ajena para nada.
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
REGISTRY_NS="ghcr.io/ismaeloul"

cd "$(dirname "$0")/.."

echo "==> Comprobando requisitos"
command -v docker >/dev/null || { echo "Falta docker"; exit 1; }
docker info >/dev/null 2>&1 || { echo "El demonio de docker no responde"; exit 1; }

AVAIL_GB=$(df -BG --output=avail . | tail -1 | tr -dc '0-9')
if [ "${AVAIL_GB:-0}" -lt 15 ]; then
  echo "AVISO: quedan ${AVAIL_GB}G libres. Compilar Rust come disco; 15G es lo minimo comodo."
fi

# Las imagenes se etiquetan con el MISMO nombre que tendrian en GHCR, para que
# los docker-compose.yml funcionen sin tocar una linea. Docker usa la imagen
# local y no intenta descargarla mientras exista.
build () {
  local name="$1" context="$2"
  echo
  echo "==> Compilando $name  (contexto: $context)"
  local t0=$SECONDS
  docker build \
    --tag "${REGISTRY_NS}/${name}:${VERSION}" \
    --tag "${REGISTRY_NS}/${name}:latest" \
    "$context"
  echo "==> $name listo en $(( (SECONDS - t0) / 60 )) min"
}

# El anisette primero: es el rapido, y si algo esta mal en el entorno se ve
# enseguida en vez de a la hora de compilar Rust.
build "anisette-v3-server" "docker/anisette"
build "jas"                "docker/jas"

echo
echo "==> Imagenes disponibles"
docker images --filter "reference=${REGISTRY_NS}/*" \
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
