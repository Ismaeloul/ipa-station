# Cuando algo falla

Los nombres de contenedor son los de la app de Umbrel
(`ismaeloul-ipa-station_*`). Si lo levantaste con el compose de la raíz, son
`ipa-station_jas` y `ipa-station_anisette`.

Antes de nada, los logs:

```bash
docker logs --tail 100 ismaeloul-ipa-station_jas_1
docker logs --tail 100 ismaeloul-ipa-station_anisette_1
```

---

## El anisette deja de provisionar

**Síntomas:** al añadir el Apple ID o al firmar, un error de autenticación
contra Apple. En los logs del anisette aparecen códigos negativos tipo
`-45054`, `-45061`, o un error de provisioning.

**Qué está pasando.** El anisette guarda un estado de "provisionamiento" que
negocia con Apple. Ese estado se corrompe, o Apple está de mantenimiento, o el
servidor no pudo escribir su carpeta.

**Por orden:**

1. **¿Es la imagen correcta?** Si en algún momento cambiaste a
   `dadoum/anisette-v3-server:latest` de Docker Hub, vuelve a la nuestra. Esa
   imagen se publicó por última vez el 13-abr-2025 y **le faltan justo los
   arreglos de provisioning de 2026**, incluido el del `-45054`.

   ```bash
   docker inspect --format '{{.Config.Image}}' ismaeloul-ipa-station_anisette_1
   ```

   Tiene que decir `ipa-station/anisette-v3-server`.

2. **¿Apple está caído?** Es una causa conocida y no depende de ti. Espera un
   rato y reintenta antes de tocar nada.

3. **Reprovisionar desde cero.** Último recurso: borra el estado y deja que lo
   negocie otra vez. **No pierdes apps instaladas ni la sesión de Apple**, solo
   ese estado.

   ```bash
   docker stop ismaeloul-ipa-station_anisette_1
   docker volume rm ismaeloul-ipa-station_anisette_data
   docker start ismaeloul-ipa-station_anisette_1
   ```

   (El nombre exacto del volumen sale con `docker volume ls | grep anisette`.)

4. **Comprobar que contesta:**

   ```bash
   docker exec ismaeloul-ipa-station_anisette_1 curl -s http://127.0.0.1:6969/v3/client_info
   ```

---

## jas no usa mi anisette, usa uno público

En los logs de arranque hay una línea `Anisette server: ...`. Si dice
`https://ani.stikstore.app`, la siembra automática no llegó a tiempo.

Arréglalo desde el panel: **Settings → Anisette Server** →
`http://ismaeloul-ipa-station_anisette_1:6969`. El cambio es inmediato y
persiste.

La siembra solo actúa con la base de datos recién creada, precisamente para no
pisar lo que hayas puesto tú.

---

## El fichero de emparejamiento ha caducado

**Síntomas:** funcionaba y de repente todas las operaciones fallan al conectar.
Errores de `RPPairing`, de handshake TLS o de `CDTunnel`.

Los ficheros de emparejamiento caducan. La documentación de SideStore lo dice
sin rodeos: pasa al actualizar o resetear el iPhone, **y también en momentos
aleatorios**. Es cosa de Apple.

**Solución:** regenerar. Cable, `idevice_pair`, tipo **RPPairing** otra vez, y
en el panel **Devices → tu iPhone** subes el nuevo. No hace falta borrar el
dispositivo ni reinstalar nada.

Ojo con dos cosas:

- Un fichero de **antes de iOS 26.4 no vale**. Apple los invalidó ahí.
- Un fichero de tipo **lockdown tampoco**. jas solo habla RPPairing; lo dice en
  sus *non-goals*: los dispositivos que solo tienen lockdown quedan fuera.

---

## El iPhone no responde

**Síntomas:** al registrar el dispositivo o al instalar, `TCP connect to
<ip>:49152 timed out`.

Diagnóstico en un comando, desde el Umbrel:

```bash
bash scripts/check-umbrel.sh 192.168.1.50
```

Causas por probabilidad:

1. **Le ha cambiado la IP.** La más común. Mira la IP real en el iPhone
   (**Ajustes → Wi-Fi → (i)**) y compárala con la que tiene el panel. Si no
   coincide, haz la reserva DHCP en el router y pon la dirección Wi-Fi privada
   en **Fija** — con "Rotativa" el router lo trata como un aparato nuevo cada
   pocos días.
2. **Aislamiento de clientes en el router** (a veces se llama *AP isolation* o
   está activo en la red de invitados). Impide que dos aparatos de la misma
   Wi-Fi se vean. Desactívalo o pásalos a la misma red.
3. **Redes distintas.** Si el iPhone está en la Wi-Fi de invitados o en 5 GHz
   con VLAN separada, no hay ruta hasta el NAS.
4. **El host lo alcanza pero el contenedor no.** Raro, pero si el script lo
   señala, reinicia la app desde Umbrel para recrear la red bridge.

Si tras todo esto sigue sin ir, activa **Modo Desarrollador** en el iPhone
(**Ajustes → Privacidad y seguridad → Modo Desarrollador**, requiere reiniciar).
No debería hacer falta para instalar, pero desbloquea servicios del dispositivo
y no cuesta nada probarlo.

---

## Apple responde 503 al iniciar sesión

**Síntomas:** el panel no deja entrar con el Apple ID y el error termina en

```
Received error response from grandslam
HTTP status server error (503 Service Temporarily Unavailable)
for url (https://gsa.apple.com/grandslam/GsService2)
```

Y antes de eso, con la sesión que ya tenías guardada, un
`Developer error 1100: Your session has expired. Please log in.`

**Qué pasa.** Desde septiembre de 2026 Apple rechaza en el borde cualquier
petición de GrandSlam cuya cabecera `X-Mme-Client-Info` diga
`com.apple.dt.Xcode`: contesta un HTML de 190 bytes con un 503 en vez del
plist de siempre. No es una caída de Apple ni un problema del NAS — la
petición ni siquiera llega al servicio.

Esa cabecera no la inventa jas: isideload pide el client info al servidor
anisette (`/v3/client_info`) y lo copia tal cual. O sea que el arreglo está en
la imagen del anisette, no en el panel.

**Comprobarlo** (desde el NAS, sin tocar nada):

```bash
# Lo que publica tu anisette ahora mismo
curl -s http://<ip-del-contenedor-anisette>:6969/v3/client_info

# Los dos client info contra Apple, con la misma petición
for ci in "com.apple.dt.Xcode/3594.4.19" "com.apple.akd/1.0"; do
  curl -sk -o /dev/null -w "$ci -> %{http_code}\n" -X POST \
    -H "Content-Type: text/x-xml-plist" \
    -H "X-Mme-Client-Info: <MacBookPro13,2> <macOS;13.1;22C65> <com.apple.AuthKit/1 ($ci)>" \
    -H "User-Agent: akd/1.0 CFNetwork/808.1.4" \
    --data "<plist></plist>" https://gsa.apple.com/grandslam/GsService2
done
```

El de Xcode contesta `503` y el de akd no: ahí está el diagnóstico.

> El `-k` es necesario y no es una señal de nada: `gsa.apple.com` se presenta
> con un certificado de la CA privada de Apple, que no está en el almacén del
> sistema. isideload lleva ese root incrustado; `curl` no.

**Arreglo.** `docker/anisette/Dockerfile` fija `ANISETTE_REF` en `ae48fa1`
("Xcode -> authkitd"), que es donde upstream cambió el client info a
`com.apple.akd`. Si vienes de una imagen anterior, recompila solo el anisette
y sube la etiqueta en el compose de la app:

```bash
cd ~/ipa-station && git pull
bash scripts/build-on-umbrel.sh 0.1.1 4 anisette
```

Son minutos, no hace falta tocar jas. Luego actualiza la app desde la tienda
de Umbrel y vuelve a iniciar sesión con el Apple ID: el token viejo ya estaba
caducado de todos modos.

La máquina ya provisionada sigue valiendo: el cambio es solo la cabecera que
se manda, no los datos que genera el anisette.

Ojo con una cosa si algún día hay que **volver a provisionar**: el
`serverFriendlyDescription` se escribe en `device.json` la primera vez que
arranca el servidor y ya no se vuelve a tocar, así que un volumen viejo sigue
diciendo `com.apple.dt.Xcode` por dentro aunque `/v3/client_info` ya devuelva
el nuevo. Si aparecen errores de provisioning (`-45054` y compañía) o un 503
al crear la máquina, vacía el volumen `anisette_data` como explica la sección
de arriba: al nacer de cero, `device.json` se escribe ya con `com.apple.akd`.

---

## "He borrado un MacBook de mi cuenta y desde entonces no entra"

Ese MacBook era el Umbrel.

El servidor anisette se presenta ante Apple como un Mac — literalmente
`<MacBookPro13,2> <macOS;13.1;22C65>` — porque es lo que Apple espera ver
haciendo estas peticiones. Así que en **Apple ID → Dispositivos** aparece un
"MacBook Pro" que no tienes en ninguna mesa: es el NAS.

Si lo borras de ahí, Apple revoca esa sesión al instante. El panel empieza a
dar `Developer error 1100: Your session has expired` y el refresco automático
deja de funcionar, aunque la contraseña sea correcta y no hayas tocado nada.

**Arreglo:** volver a iniciar sesión en el panel. Aparecerá un MacBook Pro
nuevo en la lista de dispositivos — **ese es IPA Station, déjalo ahí**. Si
vuelves a borrarlo, vuelve a pasar lo mismo.

---

## Apple responde 429 al iniciar sesión

**Síntomas:** el error ya no es un 503 sino

```
Failed to send proof login request
HTTP status client error (429 Too Many Requests)
```

**Qué no es.** No es un límite de tu cuenta ni de tu IP, aunque lo parezca.
Lo delata que cambiar de Apple ID no lo arregla, ni cambiar de identidad del
anisette, ni esperar horas.

**Qué es.** Desde septiembre de 2026 el borde de `gsa.apple.com` contesta 429
a una parte de las peticiones bien formadas, al azar y en ventanas de segundos
a pocos minutos. Está medido en
[nab138/isideload#19](https://github.com/nab138/isideload/pull/19): doce
peticiones idénticas seguidas, mitad 200 y mitad 429, sin tocar ninguna
cuenta. Un login son dos peticiones —más las del 2FA— e isideload se rendía
al primer 429, así que iniciar sesión fallaba casi siempre.

**Arreglo.** La imagen de jas 0.1.1 compila isideload con
`docker/jas/patches/isideload-429-retry.patch`: reintenta solo los 429,
esperando 1, 2, 4, 8 y 16 segundos, en el login, en la bolsa de URLs y en el
2FA. Con eso el login puede tardar hasta medio minuto más, pero entra.

```bash
cd ~/ipa-station && git pull
bash scripts/build-on-umbrel.sh 0.1.1 4 jas
```

**Mientras no tengas esa imagen:** reintentar a mano sí sirve, al contrario
de lo que parece. Cada intento es una tirada nueva; deja un minuto entre uno y
otro para salir de la ventana mala.

---

## El 2FA de Apple no pasa

- **El código llega y lo rechaza:** normalmente es que se metió tarde. Caducan
  rápido. Vuelve a empezar el alta y ten el teléfono en la mano.
- **No llega ningún código:** revisa que el Apple ID no tenga verificación por
  SMS a un número que ya no uses.
- **Dice contraseña incorrecta y sabes que es correcta:** casi siempre es el
  anisette, no la contraseña. Mira la sección de arriba.
- **Apple bloquea la cuenta:** puede pasar con muchos intentos seguidos.
  Recupérala en [iforgot.apple.com](https://iforgot.apple.com) y espera un rato
  antes de reintentar. Otra razón para usar una cuenta dedicada.

---

## "Ya no puedo crear más App IDs"

Apple deja **10 App IDs por semana** en las cuentas gratuitas. Cada app nueva
gasta uno. Los refrescos de las que ya tienes **no gastan**.

En **Accounts → App IDs** ves los que has usado y el máximo del equipo, con sus
fechas. La ventana es deslizante: se van liberando solos.

---

## Una app instalada deja de abrirse

- **Han pasado más de 7 días y el refresco no corrió.** Mira si el interruptor
  de *refresh* está encendido y si el IPA está guardado en el servidor: en modo
  efímero, el temporizador se salta la app a propósito porque no tiene el
  fichero para volver a firmarla.
- **Se revocó el certificado.** Si le diste a *Revoke Certs*, o si instalaste
  las mismas apps desde otra herramienta con la misma cuenta, todo lo firmado
  con ese certificado deja de arrancar. Se arregla reinstalando desde el panel.
- **Superaste las 3 apps.** Apple deja de validar la cuarta. Quita una o pásate
  a LiveContainer.

---

## La instalación falla al descargar las imágenes

**Síntoma:** instalar desde la tienda no hace nada, o `apps.install` devuelve
`false`.

Umbrel hace un `docker pull` de cada imagen antes de arrancar la app, y ese
pull ignora `pull_policy`. Si el registro local está parado, no hay de dónde
bajarlas y la instalación aborta.

```bash
docker ps -f name=ipa-station-registry
```

Si no aparece, arráncalo:

```bash
docker start ipa-station-registry
```

Y comprueba que las imágenes siguen dentro:

```bash
curl -s http://127.0.0.1:5000/v2/_catalog
```

Si el catálogo sale vacío, vuelve a lanzar `bash scripts/build-on-umbrel.sh`
(con la caché de Docker tarda segundos, no vuelve a compilar).

## "No such image" al arrancar

Las imágenes no están construidas, o se construyeron con otro nombre o versión.
Mira qué hay:

```bash
docker images --filter "reference=ipa-station/*"
```

Tienen que aparecer `ipa-station/jas` y `ipa-station/anisette-v3-server`, y la
etiqueta debe coincidir con la del compose (`0.1.0`). Si falta alguna, vuelve a
lanzar `bash scripts/build-on-umbrel.sh`.

## La compilación falla

Se compila en el NAS, así que los logs están en `~/build.log`.

- **Se queda sin espacio:** Rust más WASM comen bastante disco. Libera y
  reintenta; `docker system prune -f` recupera lo de builds anteriores.
- **Se queda sin memoria (`Killed`, `signal: 9`):** baja los hilos de
  compilación. `bash scripts/build-on-umbrel.sh 0.1.0 2`.
- **Error de `sqlx` sobre una base de datos:** falta `SQLX_OFFLINE=true`. Ya
  está en el Dockerfile; si lo tocaste, devuélvelo.
- **`cargo leptos` no encontrado:** el `cargo install --locked cargo-leptos`
  falló, casi siempre por red. Reintenta.
- **Rompe al compilar jas:** upstream movió `master` y el commit fijado ya no
  encaja con alguna dependencia git (`isideload` va por rama, no por versión).
  Vuelve al SHA que funcionaba en `docker/jas/Dockerfile`.

## El JIT no va (emuladores)

Esto no es del stack. iOS 26 rompió el JIT otra vez y **en 26.6 solo funciona
con unas pocas apps**, incluso con StikDebug actualizado.

Afecta a emuladores y máquinas virtuales, que lo necesitan para ir rápido.
Instalar y firmar apps normales no tiene nada que ver y funciona igual.

---

## Empezar de cero

Sin tocar el iPhone:

```bash
docker stop ismaeloul-ipa-station_jas_1
rm -rf /home/umbrel/umbrel/app-data/ismaeloul-ipa-station/data
docker start ismaeloul-ipa-station_jas_1
```

Esto borra dispositivos, cuentas, IPAs guardados **y la clave de cifrado**.
Habrá que volver a subir el fichero de emparejamiento y a iniciar sesión. Las
apps que ya estén en el iPhone siguen funcionando hasta que caduque su
certificado.
