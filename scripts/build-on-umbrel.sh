#!/usr/bin/env bash
# Compila las dos imagenes EN EL PROPIO UMBREL y las publica en un registro
# local que tambien corre en el NAS. Nada sale de la maquina.
#
# Uso, por SSH en el Umbrel:
#
#   git clone https://github.com/Ismaeloul/ipa-station.git
#   cd ipa-station
#   bash scripts/build-on-umbrel.sh
#
# Tarda. En un N300 cuenta entre 40 y 90 minutos la primera vez: jas es Rust
# mas WebAssembly y hay que compilar tambien cargo-leptos. Lanzalo con nohup
# si te preocupa perder la sesion SSH.
#
# POR QUE HACE FALTA UN REGISTRO LOCAL
# Umbrel no arranca la app con `docker compose up` a secas: antes hace un
# `docker pull` de cada `image:` del compose, uno por uno, y si alguno falla
# aborta la instalacion (umbreld: apps/app.ts pull(), utilities/docker-pull.ts).
# Ese pull IGNORA `pull_policy: never`, asi que no basta con tener la imagen en
# local: tiene que existir un registro del que descargarla. El registro va
# atado a 127.0.0.1, o sea que no se expone a la red, y Docker acepta
# localhost como registro inseguro sin tener que configurar nada.
set -euo pipefail

VERSION="${1:-0.1.0}"
# Trabajos de compilacion en paralelo. Por defecto la mitad de los hilos, para
# que Jellyfin, Immich y AceStream sigan respondiendo mientras esto compila.
JOBS="${2:-4}"

REGISTRY="localhost:5000"
IMAGE_NS="${REGISTRY}/ipa-station"
REGISTRY_CONTAINER="ipa-station-registry"

cd "$(dirname "$0")/.."

echo "==> Comprobando requisitos"
command -v docker >/dev/null || { echo "Falta docker"; exit 1; }
docker info >/dev/null 2>&1 || { echo "El demonio de docker no responde"; exit 1; }

AVAIL_GB=$(df -BG --output=avail . | tail -1 | tr -dc '0-9')
if [ "${AVAIL_GB:-0}" -lt 15 ]; then
  echo "AVISO: quedan ${AVAIL_GB}G libres. Compilar Rust come disco; 15G es lo minimo comodo."
fi

# ---------------------------------------------------------------------------
# Registro local
# ---------------------------------------------------------------------------
ensure_registry () {
  if [ -n "$(docker ps -q -f "name=^${REGISTRY_CONTAINER}$")" ]; then
    echo "==> Registro local ya en marcha"
    return
  fi
  if [ -n "$(docker ps -aq -f "name=^${REGISTRY_CONTAINER}$")" ]; then
    echo "==> Arrancando el registro local existente"
    docker start "${REGISTRY_CONTAINER}" >/dev/null
  else
    echo "==> Creando el registro local en ${REGISTRY}"
    docker run -d \
      --name "${REGISTRY_CONTAINER}" \
      --restart unless-stopped \
      -p 127.0.0.1:5000:5000 \
      -v ipa-station-registry-data:/var/lib/registry \
      registry:2 >/dev/null
  fi
  # Darle un momento antes del primer push
  for _ in $(seq 1 15); do
    curl -fsS http://127.0.0.1:5000/v2/ >/dev/null 2>&1 && return
    sleep 1
  done
  echo "El registro local no responde en ${REGISTRY}"; exit 1
}

# ---------------------------------------------------------------------------
# Build + push
# ---------------------------------------------------------------------------
build () {
  local name="$1" context="$2"; shift 2
  echo
  echo "==> Compilando $name  (contexto: $context)"
  local t0=$SECONDS
  docker build "$@" \
    --tag "${IMAGE_NS}/${name}:${VERSION}" \
    --tag "${IMAGE_NS}/${name}:latest" \
    "$context"
  echo "==> Publicando $name en el registro local"
  docker push -q "${IMAGE_NS}/${name}:${VERSION}"
  docker push -q "${IMAGE_NS}/${name}:latest"
  echo "==> $name listo en $(( (SECONDS - t0) / 60 )) min"
}

ensure_registry

# El anisette primero: es el rapido, y si algo esta mal en el entorno se ve
# enseguida en vez de a la hora de compilar Rust.
build "anisette-v3-server" "docker/anisette"
build "jas"                "docker/jas" --build-arg "CARGO_JOBS=${JOBS}"

echo
echo "==> Imagenes publicadas"
docker images --filter "reference=${IMAGE_NS}/*" \
  --format '  {{.Repository}}:{{.Tag}}  {{.Size}}'

cat <<EOF

==> Hecho.

Ya puedes instalar IPA Station desde la tienda de Umbrel.

El registro local (contenedor ${REGISTRY_CONTAINER}) tiene que seguir en
marcha: Umbrel descarga de ahi cada vez que instala, actualiza o recrea la
app. Arranca solo con Docker gracias a restart: unless-stopped.

EOF
