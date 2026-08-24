# syntax=docker/dockerfile:1
#
# JAS (Jackson's App Sensei) - https://github.com/jkcoxson/jas
#
# Upstream no publica imagen de Docker, asi que la construimos aqui.
# Es un binario unico de Leptos: hace falta el ejecutable Y la carpeta
# target/site con los assets, apuntada por LEPTOS_SITE_ROOT.

############################################################
# 1. Build
############################################################
FROM rust:1.98.0-bookworm AS builder

# Commit fijado a proposito: jas es un proyecto personal sin releases, y
# `master` puede romper la compilacion cualquier dia. Para actualizar,
# cambia este SHA (y solo este) tras comprobar que compila.
ARG JAS_REF=b8613f139ac12327bd1d5222dfe543a76e03dd10

RUN apt-get update && apt-get install --no-install-recommends -y \
      git pkg-config libssl-dev clang \
 && rm -rf /var/lib/apt/lists/*

RUN rustup target add wasm32-unknown-unknown
RUN cargo install --locked cargo-leptos

WORKDIR /src
RUN git clone https://github.com/jkcoxson/jas.git . \
 && git checkout "${JAS_REF}"

# sqlx valida las queries en tiempo de compilacion contra una base de datos
# real salvo que se le den los metadatos precalculados. El repo trae .sqlx/
# commiteado, asi que en modo offline compila sin necesitar SQLite arrancado.
ENV SQLX_OFFLINE=true

# El N300 tiene 8 hilos, pero si se compila en el propio NAS esa maquina esta
# a la vez sirviendo Jellyfin, Immich y AceStream. Con 4 trabajos el build
# tarda algo mas pero no deja el resto pidiendo limosna. En CI se puede subir.
ARG CARGO_JOBS=4
ENV CARGO_BUILD_JOBS=${CARGO_JOBS}

RUN cargo leptos build --release

############################################################
# 2. Runtime
############################################################
FROM debian:bookworm-slim

# sqlite3: lo usa el entrypoint para sembrar la URL del anisette en el primer
# arranque y para generar la clave de cifrado. curl: healthcheck.
RUN apt-get update && apt-get install --no-install-recommends -y \
      ca-certificates libssl3 sqlite3 curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /src/target/release/jas /app/jas
COPY --from=builder /src/target/site        /app/site
COPY entrypoint.sh                          /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh /app/jas

# Leptos lee su configuracion del entorno en tiempo de ejecucion.
ENV LEPTOS_OUTPUT_NAME=jas \
    LEPTOS_SITE_ROOT=/app/site \
    LEPTOS_SITE_PKG_DIR=pkg \
    LEPTOS_SITE_ADDR=0.0.0.0:3000 \
    LEPTOS_ENV=PROD \
    JAS_CONFIG=/app/jas.toml \
    JAS_DB=/data/jas.db \
    JAS_IPA_DIR=/data/ipas \
    JAS_BIND=0.0.0.0:3000 \
    JAS_LOG_LEVEL=info \
    ANISETTE_URL=http://anisette:6969

# mDNS necesita multicast, que no cruza una red bridge de Docker. Lo dejamos
# apagado y el iPhone se registra con IP fija: jas conecta al 49152 fijo, asi
# que el descubrimiento es solo un atajo, no un requisito.
ENV JAS_MDNS_ENABLED=false

EXPOSE 3000
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3000/ >/dev/null || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
