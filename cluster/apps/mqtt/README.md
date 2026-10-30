# MQTT (Mosquitto) para Meshtastic

Une mallas Meshtastic separadas por distancia (casa ↔ Temuco) a través de internet. Cada sitio tiene un nodo
**gateway** con WiFi que publica y recibe el canal privado en este broker. Configuración de los nodos: skill
`meshtastic` (`flota.yaml`, perfil `base`/`gateway`).

| | |
|---|---|
| Broker | `eclipse-mosquitto:2.0.22`, solo TLS en **8883**, sin anónimos, un usuario por gateway (`roof`, `temuco`, `papo`, `laptop`, `dnto`, `xiaonrf`) |
| Desde la LAN | `192.168.1.15:8883` (o cualquier nodo k3s: ServiceLB publica en todos) |
| Desde internet | `mqtt.danielriquelme.cl:8883` (DNS only, actualizado por el sidecar `cloudflare-ddns`) |
| Certificado | Let's Encrypt por cert-manager (`certificate.yml`: Issuer DNS-01 en Cloudflare con `CF_API_TOKEN`, secreto `mqtt-tls`); se renueva solo y Mosquitto lo recarga con SIGHUP. Hace falta para las apps con MQTT Client Proxy (Mac/iPhone validan: con el autofirmado daban `kCFStreamErrorDomainSSL -9807`). El autofirmado de 10 años queda en `secret.sops.yaml` como respaldo |
| Raíz de tópicos | `msh/acevedo` (configurada en cada gateway) |
| Secretos | `secret.sops.yaml`: `passwd` (en claro, el initContainer lo pasa a hash), `tls.crt`, `tls.key`, `CF_API_TOKEN` |
| Claves de los nodos | también en `~/.config/meshtastic-fleet/secretos.yaml` (`mqtt_pass_roof`, `mqtt_pass_temuco`) |

## Reenvío en el router (lo hace el usuario)

1. IP fija (reserva DHCP) para pibot `192.168.1.15` si no la tiene.
2. Reenvío de puerto: **WAN TCP 8883 → 192.168.1.15:8883**. Solo TCP, solo ese puerto.
3. Verificar desde fuera de la casa (datos móviles):
   `openssl s_client -connect mqtt.danielriquelme.cl:8883 -servername mqtt.danielriquelme.cl </dev/null | head -5`
   debe mostrar `CN = mqtt.danielriquelme.cl`.

El AcevedoRoof se conecta por la LAN (`192.168.1.15`): con un broker de IP privada el firmware sube también los
paquetes de otros nodos sin exigir `ok_to_mqtt`. El gateway de Temuco entra por `mqtt.danielriquelme.cl`; para que
suba los paquetes de los nodos de allá, esos nodos llevan `lora.config_ok_to_mqtt true` (ya en `flota.yaml`).

## Agregar un gateway nuevo

1. Agregar `usuario:clave` a `passwd` (`sops cluster/apps/mqtt/secret.sops.yaml`) y su bloque en el `acl` del
   ConfigMap.
2. PR y merge. Cambiar el ConfigMap o el Secret no reinicia el pod: después del merge,
   `kubectl -n mqtt rollout restart deploy/mosquitto --field-manager=reinicio-manual`.

## Probar

```bash
# Suscribirse a todo (desde la LAN; mosquitto_sub de brew)
mosquitto_sub -h 192.168.1.15 -p 8883 --cafile ~/.config/meshtastic-fleet/mqtt-ca.crt --insecure \
  -u roof -P "<clave>" -t 'msh/#' -v | head
kubectl -n mqtt logs deploy/mosquitto -c mosquitto --tail=30
```
