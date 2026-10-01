# Canon MP250 — CUPS + AirPrint (mDNS) en k3s

## Qué resuelve esto

- **IPP** (URL `ipp://…`) basta para conectar a mano, pero **AirPrint** (lo que usa el iPhone y el asistente de “impresoras cercanas” en macOS) exige **anuncio Bonjour/mDNS** del servicio `_ipp._tcp` (puerto **UDP 5353** y multidifusión).  
- La imagen anterior (`olbat/cupsd`) **no** llevaba Avahi; el descubrimiento “tipo AirPrint” no funcionaba.  
- Ahora el despliegue usa **[chuckcharlie/cups-avahi-airprint](https://github.com/chuckcharlie/cups-avahi-airprint)**: CUPS + **Avahi** con D-Bus **dentro** del contenedor (no montes `/var/run/dbus` del host: en v2+ rompe el D-Bus del nodo).

## Nodo y red

- Nodo fijo: **`pibot`** (equivalente a tu `k3s-node-0` en Magic DNS).
- **`hostNetwork: true`**: imprescindible para **multicast** y mDNS en la LAN.
- **Persistencia** en el host: **`/var/lib/homelab-canon-mp250-cups`**, montada en el contenedor como **`/config`** ( `printers.conf`, `cupsd.conf`, `ppd/` ).

## Credenciales y variables

| Variable         | Valor en el manifiesto | Uso                          |
|------------------|-------------------------|------------------------------|
| `CUPSADMIN`      | `print`                 | Usuario consola CUPS         |
| `CUPSPASSWORD`   | `print`                 | Contraseña consola CUPS      |
| `AVAHI_HOSTNAME` | `canon-homelab-mp250`   | `host-name` mDNS; si ves `nombre-2`, `nombre-3` es **conflicto** en la red. Cambia este valor a otra cosa **única** (ej. `impresora-daniel-lan`) y aplica. |

### Por qué el nombre acaba en `-2`, `-3` (`pibot-cups-3`, etc.)

Avahi publica un `host-name=…`. Si en el Wi‑Fi o cable ya existe **otro** anuncio con el mismo nombre (caché, otro dispositivo, intento previo, avahi en el **host**), añade sufijo. No es un fallo de Kubernetes, es **resolución de nombres en mDNS**. Tras **cambiar** `AVAHI_HOSTNAME` en [deployment.yml](deployment.yml) y re-crear el pod, debería verse algo como `Canon … @ canon-homelab-mp250` (o el que hayas puesto). En el Mac, a veces hace falta: olvidar la impresora vieja, o reiniciar `mDNSResponder` (`sudo killall -HUP mDNSResponder`).

Consola: **`http://<IP-LAN-pibot>:631`**

## Red local (LAN / Wi‑Fi)

1. Crea la cola en CUPS, driver Gutenprint para la MP250, y **comparte** la impresora (Share).  
2. Tras un minuto, en el iPhone / Mac debería aparecer en **Impresoras** (AirPrint). Si no, reinicia el pod una vez.  
3. **Conflicto UDP 5353**: si en `pibot` el **sistema** tiene `avahi-daemon` (o similar), solo uno puede escuchar. **Síntoma**: en logs del contenedor, “Address in use” o AirPrint inestable. **Opción A**: en el host, `sudo systemctl disable --now avahi-daemon` (o el servicio mDNS de tu distro). **Opción B** (avanzada): otra `AVAHI_HOSTNAME` y, si aún choca, macvlan (ver [README de la imagen](https://github.com/chuckcharlie/cups-avahi-airprint)).  
4. El **CUPS** del **host** debe seguir apagado si comparte el **631** con el contenedor (`systemctl disable --now cups`).

## Tailscale (tailnet)

- **IPP directo** al **100.x** de `pibot` suele funcionar: `ipp://<100.x>:631/printers/<cola>`.  
- **AirPrint por descubrimiento mDNS a través de Tailnet** a menudo **no** es fiable: muchos iPhones/Mac no reciben Bonjour entre “subredes lógicas” aun con Tailscale. Lo habitual es: **Añadir impresora** por **IPP** y la URL con el **100.x**, o [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) / otra ruta de acceso, no contar con la lista “AirPrint” vía tailnet.  
- Si exiges AirPrint puro en tailnet, hace falta replicar/reflejar mDNS o topología (no incluida en este manifiesto).

## `ServerName` e init

Un `initContainer` añade **`ServerName`** con la IP del nodo en `cupsd.conf` persistido, para que los atributos IPP no sigan apuntando a `127.0.0.1` en el cliente. La **primera** puesta en marcha puede no tener aún `cupsd.conf` en el disco; vuelve a `kubectl delete pod` una vez creada la config.

## Aplicar

```bash
kubectl apply -k cluster/apps/canon-mp250-airprint/
kubectl -n canon-mp250-airprint delete pod -l app=cups-airprint
```

## Service (NodePort 31631)

Sigue existiendo; con `hostNetwork` en `pibot` lo natural es `http://<ip-pibot>:631`.

## Resolución

| Problema              | Causa habitual                                      |
|-----------------------|----------------------------------------------------|
| No veo “AirPrint”     | Faltaba Avahi (o conflicto 5353 con el host)      |
| Sí IPP, no listado   | mDNS; usa URL IPP o resuelve conflicto Avahi       |
| iPhone y Tailnet      | mDNS no cruza; usa IPP con 100.x                   |
| Aparece en Bonjour pero “no se puede conectar” a `._ipps._tcp` | **CUPS** con `DefaultEncryption IfRequested` anuncia **IPPS** (TLS). El Mac elige `_ipps._tcp` y falla si en 631 no hay TLS. El init del despliegue fuerza **`DefaultEncryption Never`** y **`Encryption Never`** en `<Location />` en el `cupsd.conf` persistido. Tras `kubectl apply`, borra el pod para re-ejecutar el init. |
| `Validate-Job client-error-not-found` (en `access_log`) con el **Mac** | Hay **tres** causas ya reproducidas con `ipptool` contra CUPS 2.4: **(1)** Ruta **`/ipp/print/…`**: CUPS **solo** admite `printer-uri` con **`/printers/<nombre_cola>`** o `/classes/…` en el *path*; `/ipp/print/...` responde `client-error-not-found` (código: `cupsdValidateDest` en el scheduler). **(2) Espacios en el nombre de cola en la URI:** el anuncio Bonjour dice *«Canon MP250 series @ …»* y la **cola CUPS** se llama **`Canon_MP250_series`** (sin espacios; CUPS no permite espacios en el nombre de cola). Si el cliente fabrica `…/printers/Canon%20MP250%20series` o similar, el servidor **no** encuentra la cola → el mismo `not-found` que viste con el Mac en **100.x**. **(3) Cola aceptando trabajos** (`Accepting No`) da otro tipo de error; el `not-found` no es eso. **Qué usar en el Mac:** borra entradas viejas; añade **IPP** manual con URL exacta `ipp://<IP pibot en la red por la que imprimes>:631/printers/Canon_MP250_series` (IP LAN **o** 100.x de Tailscale, según dónde enrutéis el tráfico). Comprueba el nombre con `lpstat -p` en el pod. **Comprobación desde una máquina con `ipptool`:** `…/printers/Canon_MP250_series` → `successful-ok`; `…/ipp/print/…` o `…/printers/Canon%20MP250%20series` → `client-error-not-found`. |
| Bonjour inestable / nombres `…-35`, `…-36` en Avahi, logs `Host name conflict` y `pibot.local` | El **demonio mDNS en el nodo (pibot)** y el del **contenedor** pisan el mismo **UDP 5353** / el mismo universo de nombres. Sigue [la documentación de la imagen](https://github.com/chuckcharlie/cups-avahi-airprint): desactivar en el **host** `avahi-daemon` (o el equivalente) **o** usar otra arquitectura (p. ej. **macvlan**, ver README upstream). Mientras haya conflictos, el anuncio **AirPrint** puede quedar alineado mal con el URI que CUPS acepta. |
