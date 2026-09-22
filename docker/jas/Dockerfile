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

# isideload con reintentos ante el 429 de Apple.
#
# Desde septiembre de 2026 el borde de gsa.apple.com contesta 429 a una parte
# de las peticiones bien formadas, al azar y en ventanas de segundos a pocos
# minutos. No va por cuenta ni por IP: doce peticiones identicas seguidas dan
# mitad 200 y mitad 429 (medido en nab138/isideload#19). Un login son dos
# peticiones mas las del 2FA, e isideload se rendia al primer 429, asi que
# iniciar sesion fallaba casi siempre.
#
# El parche es ese PR portado al fork que usa jas (jkcoxson/isideload, rama
# feature/rsd, el mismo commit que ya fija el Cargo.lock de jas): reintenta
# solo los 429, esperando 1, 2, 4, 8 y 16 s, en el login, en la bolsa de URLs
# y en las peticiones del 2FA. Cualquier otro codigo llega igual que antes.
ARG ISIDELOAD_REF=c380f27f93bccf5bc5cce2a7cef62479207cc012
COPY patches/isideload-429-retry.patch /tmp/isideload-429-retry.patch
RUN git clone https://github.com/jkcoxson/isideload.git /isideload \
 && cd /isideload \
 && git checkout "${ISIDELOAD_REF}" \
 && git apply /tmp/isideload-429-retry.patch \
 && printf '\n[patch."https://github.com/jkcoxson/isideload"]\nisideload = { path = "/isideload/isideload" }\n' >> /src/Cargo.toml

# Compilar isideload solo, antes que jas: si el parche no compila, el build
# falla en minutos en vez de al final de la hora larga de jas.
#
# Con el Cargo.lock de jas, no con el suyo: el de isideload en c380f27 esta
# desfasado (apple-codesign 0.29.4, que arrastra x509-certificate 0.25) y no
# compila por su cuenta. El de jas fija 0.29.7 con x509 0.26, que es lo que
# de verdad se va a compilar.
RUN cp /src/Cargo.lock /isideload/Cargo.lock \
 && cargo check --manifest-path /isideload/isideload/Cargo.toml \
      --no-default-features --features install

# jas guarda la cuenta desde el hilo del login, no desde la peticion web que
# espera. Con los reintentos del 429 un login puede tardar mas que esa espera
# (30 s tras el codigo 2FA, 2 s sin el), y antes terminaba bien en Apple y se
# perdia sin guardarse. Tambien deja de pedir un codigo cuando Apple no lo ha
# pedido: espera a que el login acabe o pida el 2FA de verdad.
COPY patches/jas-login-finalize.patch /tmp/jas-login-finalize.patch
RUN cd /src && git apply /tmp/jas-login-finalize.patch

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
