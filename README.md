# IPA Station

Una app para tu Umbrel que instala y **refirma sola** apps de iPhone, usando tu
Apple ID gratuito. Arrastras un IPA al panel web y aparece en el telefono. Sin
cable, sin ordenador encendido y sin los 99 euros al ano de Apple.

---

## Como funciona

```
                      ┌───────────────────────────────────┐
   Tu navegador ─────▶│  IPA Station (Umbrel, 24/7)       │
   (movil o PC)       │                                   │
                      │   jas ──── panel web + firmador   │
                      │    │                              │
                      │    └── anisette ──▶ Apple         │
                      └──────────────┬────────────────────┘
                                     │  red local, puerto 49152
                                     ▼
                              ┌─────────────┐
                              │   iPhone    │  sin apps que instalar,
                              │  iOS 26.6   │  sin VPN, sin cable
                              └─────────────┘
```

**Las dos piezas:**

- **jas** ([jkcoxson/jas](https://github.com/jkcoxson/jas)) — el panel. Pide el
  certificado a Apple con tu Apple ID, firma el IPA y se lo manda al iPhone por
  la red. Un temporizador revisa cada 2 horas qué apps están a punto de caducar
  y las refirma con 3 días de margen.
- **anisette** ([Dadoum/anisette-v3-server](https://github.com/Dadoum/anisette-v3-server))
  — le demuestra a Apple que la petición viene de un dispositivo suyo. Sin esto
  un Apple ID gratuito no puede sacar certificados. Es tuyo, así que no dependes
  de ningún servidor público de terceros.

**Por qué el iPhone no instala nada:** el servidor llama al teléfono, no al
revés. Eso evita el choque de VPNs de iOS (solo puede haber un túnel activo, así
que SideStore y Tailscale no pueden convivir) y además **te deja libre uno de los
tres huecos de apps** que permite Apple.

### Los límites de Apple, que siguen ahí

| Límite | Valor | Cómo se lleva |
|---|---|---|
| Apps simultáneas | 3 | Con LiveContainer se esquiva (ver más abajo) |
| App IDs por semana | 10 | Cada app nueva gasta uno; los refrescos no |
| Vida del certificado | 7 días | El servidor refirma solo, tú no haces nada |

---

## Lo que necesitas

- El Umbrel encendido y con acceso por SSH.
- Este PC con Windows y un cable, **una sola vez**, para emparejar el iPhone.
- **Apple Devices** (Microsoft Store) o iTunes instalado en Windows: aporta el
  driver USB que necesita la herramienta de emparejamiento.
- Un Apple ID. Recomendación: **crea uno aparte solo para esto**. Firmar apps
  gasta App IDs y deja rastro en la cuenta; no mezcles con tu Apple ID personal.

---

## Parte A — Publicar las imágenes

jas no publica imagen de Docker, así que la construimos nosotros. Se compila en
GitHub Actions, no en el NAS: son Rust y WebAssembly y dejarían el N300 frito
durante media hora.

1. Sube esta carpeta a un repositorio de GitHub (por ejemplo `Ismaeloul/ipa-station`).
2. En GitHub: pestaña **Actions** → **Build images** → **Run workflow**, versión
   `0.1.0`.
3. Espera. La primera vez tarda **entre 20 y 35 minutos** (compilar `cargo-leptos`
   y todas las dependencias). Las siguientes van con caché y bajan mucho.
4. **Paso que se olvida siempre:** los paquetes de GHCR nacen privados y el
   Umbrel no tiene credenciales para bajarlos. Ve a tu perfil de GitHub →
   **Packages** → `jas` → *Package settings* → **Change visibility → Public**.
   Repite con `anisette-v3-server`.

Al terminar tendrás:

```
ghcr.io/ismaeloul/jas:0.1.0
ghcr.io/ismaeloul/anisette-v3-server:0.1.0
```

> **Sobre las versiones fijadas.** Los dos Dockerfile clavan un commit concreto
> de upstream (`JAS_REF` y `ANISETTE_REF`). jas no tiene releases y su `master`
> puede romper la compilación cualquier día, así que actualizar es cambiar ese
> SHA a conciencia, no arrastrar lo que haya ese día.

---

## Parte B — Instalar la app en Umbrel

Mismo flujo que Ace Player Neo.

```bash
cp -r umbrel/ismaeloul-ipa-station <ruta>/umbrel-app-store/
cd <ruta>/umbrel-app-store
git add ismaeloul-ipa-station
git commit -m "Anade IPA Station"
git push
```

Y en la UI de Umbrel: tu tienda → actualizar → instalar **IPA Station**.

El panel queda en `http://umbrel.local:7795` (o `http://192.168.1.188:7795`),
detrás del login de Umbrel.

> **Puerto:** el 7795 está libre en tu NAS. Ocupados: 7788 nutritrack,
> 7791/7792 Ace Player, 8449 CraftDeck, 8095 AdGuard, 3005 umbrel-share,
> 8621/8622 los motores de AceStream y 11434 Ollama.

Si quieres probarlo antes por SSH sin pasar por la tienda, el
`docker-compose.yml` de la raíz levanta exactamente lo mismo.

Comprobación rápida desde el Umbrel:

```bash
bash scripts/check-umbrel.sh
```

---

## Parte C — Preparar el iPhone

### C.1 — Darle una IP fija

jas guarda la IP del iPhone y siempre le conecta ahí. Si el router se la cambia,
deja de encontrarlo.

1. En el iPhone: **Ajustes → Wi-Fi → (i) en tu red → Dirección Wi-Fi privada →
   Fija**. Con "Rotativa" el router lo ve como un aparato distinto cada pocos
   días y la reserva no agarra.
2. En el router: reserva DHCP para el iPhone. Apunta la IP, por ejemplo
   `192.168.1.50`.

### C.2 — Generar el fichero de emparejamiento

Es la credencial que autoriza al Umbrel a hablar con el teléfono. Se hace una
vez.

1. Descarga **`idevice_pair--windows-x86_64.exe`** de
   [idevice_pair v1.1.0](https://github.com/jkcoxson/idevice_pair/releases).
2. Conecta el iPhone por cable y acepta **Confiar** en el teléfono.
3. Abre el programa y genera el fichero de tipo **Remote Pairing (RPPairing)**.
   No vale el de tipo *lockdown*: en iOS 17.4 en adelante hace falta el remoto,
   y es el único que jas acepta.
4. Guarda el `.plist` que te da. Trátalo como una contraseña.

> Si ya tenías un fichero de emparejamiento de antes de iOS 26.4, **no sirve**.
> Apple los invalidó en esa versión. Genera uno nuevo.

Ya puedes desenchufar el cable. No vuelve a hacer falta.

---

## Parte D — Primer uso del panel

### D.1 — Dar de alta el iPhone

**Devices → añadir dispositivo**: le pones la IP (`192.168.1.50`) y subes el
`.plist`. jas se conecta y rellena solo el nombre y el UDID del teléfono.

Si falla aquí, comprueba la conexión desde el propio Umbrel:

```bash
bash scripts/check-umbrel.sh 192.168.1.50
```

### D.2 — Añadir el Apple ID

**Accounts → añadir cuenta**. Correo y contraseña; cuando Apple pida el código
de 6 dígitos, sale un campo en la misma página para meterlo.

La contraseña se usa solo en ese momento y **no se guarda en ningún sitio**. Lo
único que queda en la base de datos es el token de sesión, cifrado con AES-256.
La clave de cifrado se genera sola en el primer arranque y vive en
`data/secret.key`, dentro del volumen de la app.

### D.3 — Instalar tu primer IPA

Entra en el dispositivo desde **Devices** y sube el IPA. Verás el progreso en
vivo: firma, subida y `installation_proxy`. Cuando termine, el icono ya está en
la pantalla de inicio.

No hay que ir a *Ajustes → General → VPN y gestión de dispositivos* a confiar en
nada: el perfil es de desarrollo y lleva dentro el UDID de tu iPhone.

Deja el interruptor de **refresh** encendido y guarda el IPA en el servidor
(no uses el modo efímero) — el refresco automático necesita el fichero para
volver a firmarlo.

---

## Parte E — Comprobar que el refresco funciona

No hace falta esperar 7 días. En el dashboard, cada app muestra su fecha de
caducidad; el temporizador se despierta cada 2 horas y actúa cuando quedan 3
días o menos. Para verlo en marcha:

```bash
docker logs -f ismaeloul-ipa-station_jas_1
```

Busca las líneas del scheduler. Y en la ficha del dispositivo tienes
**Refresh All** para forzarlo a mano cuando quieras.

Si el NAS pasa un par de días apagado no pasa nada: con 3 días de margen sobre
7, hay varios intentos de colchón.

---

## Saltarse el límite de 3 apps

**LiveContainer** corre varias apps dentro de un único hueco. El panel te da lo
que necesita:

**Accounts → Export LC Cert** te descarga el certificado de desarrollo como
fichero `.p` con su contraseña al lado. Renómbralo a `.p12` desde la app
Archivos del iPhone y impórtalo en LiveContainer.

---

## Estructura del proyecto

```
IPAs/
├── docker/
│   ├── jas/            Dockerfile + entrypoint del panel
│   └── anisette/       Dockerfile del servidor anisette
├── umbrel/
│   └── ismaeloul-ipa-station/    lo que se copia a tu tienda
├── scripts/            utilidades de diagnóstico
├── docker-compose.yml  el stack suelto, para probar por SSH
└── .github/workflows/  compilación y publicación en GHCR
```

### Sitio para la Fase 2

Un servicio nuevo (por ejemplo firmar tus propias builds) entra como
`docker/<servicio>/` más su bloque en los dos compose. Nada de lo de arriba
cambia.

Ahora bien, sobre el plan de **zsign + `itms-services://`**, un aviso para que no
inviertas tiempo en un callejón sin salida: **la instalación OTA no funciona con
un Apple ID gratuito**. Necesita un perfil ad-hoc o enterprise, y una cuenta
gratuita no puede emitir ninguno de los dos. zsign solo tiene sentido el día que
tengas un certificado de pago.

Lo que sí encaja a coste cero: **subir tus builds al propio IPA Station**. Ya
firma con tu Apple ID y ya las refresca. Si además quieres una lista bonita de
tus apps, un contenedor con nginx sirviendo un JSON de tipo *AltStore Source* y
los IPAs se monta en un rato, y el panel se los traga igual.

---

## Seguridad

- **El Apple ID no está en ningún fichero** de este repositorio ni en el
  compose. Se introduce en el panel y solo persiste el token, cifrado.
- **El fichero de emparejamiento da acceso al iPhone.** Está en el `.gitignore`;
  que siga así.
- **El panel no tiene contraseña propia** — upstream lo dice claramente. En
  Umbrel va detrás del login gracias a `PROXY_AUTH_ADD: "true"`. No lo publiques
  en internet tal cual.
- **jas es un proyecto personal.** Su autor escribe literalmente que lo use cada
  uno bajo su responsabilidad. Funciona y está muy vivo, pero no es software de
  empresa. Licencia MIT para uso no comercial.

---

## Si algo falla

Está todo en [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Créditos

- [jkcoxson/jas](https://github.com/jkcoxson/jas) y
  [jkcoxson/idevice_pair](https://github.com/jkcoxson/idevice_pair)
- [nab138/isideload](https://github.com/nab138/isideload), la librería que firma
- [Dadoum/anisette-v3-server](https://github.com/Dadoum/anisette-v3-server)
