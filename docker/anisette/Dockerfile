# syntax=docker/dockerfile:1
#
# anisette-v3-server - https://github.com/Dadoum/anisette-v3-server
#
# POR QUE COMPILAMOS EN VEZ DE HACER PULL:
# la imagen oficial de Docker Hub (dadoum/anisette-v3-server:latest) se
# publico por ultima vez el 13-abr-2025 y le faltan los arreglos de 2026 del
# provisioning: el mkdir de tmpProvisioningPath que causaba el error -45054,
# "Allow v1ADI to not be provisioned on startup" y la bajada de version de
# Debian en el builder. Con la imagen de Docker Hub el servidor puede negarse
# a provisionar contra Apple.
#
# Reproduce el Dockerfile de upstream anadiendo el clone con commit fijado.

############################################################
# 1. Build
############################################################
FROM debian:stable-20250520-slim AS builder

ARG ANISETTE_REF=2ef18d7da2abe3a6d070aa478f774538b947aaa2

RUN apt-get update && apt-get install --no-install-recommends -y \
      ca-certificates ldc git clang dub libz-dev libssl-dev libplist-dev libplist-2.0-4 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/
RUN git clone https://github.com/Dadoum/anisette-v3-server.git . \
 && git checkout "${ANISETTE_REF}"

RUN DC=ldc2 dub build -c "static" --build-mode allAtOnce -b release --compiler=ldc2

############################################################
# 2. Runtime
############################################################
FROM debian:stable-20250520-slim

RUN apt-get update && apt-get install --no-install-recommends -y \
      ca-certificates curl libplist-dev libplist-2.0-4 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/
COPY --from=builder /opt/anisette-v3-server /opt/anisette-v3-server

RUN mkdir -p /opt/anisette-v3/provisioning

# Usuario sin privilegios, igual que upstream. El estado va a un volumen con
# nombre para que Docker herede el propietario de la imagen: si se monta un
# bind desde el host, la carpeta es de root y el proceso no puede escribir.
RUN useradd -ms /bin/bash Alcoholic \
 && mkdir -p /home/Alcoholic/.config/anisette-v3/lib/ \
 && chown -R Alcoholic /home/Alcoholic/ \
 && chmod -R +wx /home/Alcoholic/ \
 && chown -R Alcoholic /opt/ \
 && chmod -R +wx /opt/

USER Alcoholic
EXPOSE 6969

# /v3/client_info es barato. La raiz sirve el protocolo v1, que provisiona de
# verdad contra Apple: no conviene llamarla cada 30 segundos.
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -fsS http://127.0.0.1:6969/v3/client_info >/dev/null || exit 1

ENTRYPOINT [ "/opt/anisette-v3-server" ]
