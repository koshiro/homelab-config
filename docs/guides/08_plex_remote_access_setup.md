# Guía de Configuración de Acceso Remoto para Plex con Cloudflare Tunnel

## Arquitectura de la Solución

La configuración actual utiliza Cloudflare Tunnel para exponer Plex de forma segura a internet sin necesidad de abrir puertos en el firewall. El tráfico fluye de la siguiente manera:

`Usuario -> DNS de Cloudflare -> Red de Cloudflare -> Cloudflare Tunnel (pod 'cloudflared') -> Servicio de Plex (ClusterIP) -> Pod de Plex`

Esta arquitectura elimina la necesidad de un Ingress Controller como Traefik para el acceso externo de Plex, simplificando la configuración y mejorando la seguridad.

## Configuración Implementada

### 1. Deployment de Plex (`deployment.yml`)

El cambio más importante fue ajustar las variables de entorno para que Plex se anuncie correctamente y escuche en todas las interfaces de red dentro del contenedor.

```yaml
# ... extracto del deployment.yml ...
        env:
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        - name: TZ
          value: "America/Santiago"
        - name: VERSION
          value: "docker"
        - name: PLEX_CLAIM
          value: ""
        # Anuncia la URL externa correcta
        - name: PLEX_ADVERTISE_URL
          value: "https://plex.danielriquelme.cl"
        # --- Clave para el acceso remoto ---
        # Fuerza a Plex a escuchar en todas las interfaces (0.0.0.0) dentro del contenedor
        - name: PLEX_ANNOUNCE_SERVER_ANNOUNCE_IP
          value: "0.0.0.0"
# ... resto del fichero ...
```

### 2. Servicio de Plex (`service.yml`)

Se utiliza un servicio estándar de tipo `ClusterIP` para exponer Plex dentro del clúster. Es el destino al que apunta el túnel de Cloudflare.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: plex
  namespace: plex
spec:
  type: ClusterIP
  ports:
  - port: 32400
    targetPort: 32400
    protocol: TCP
    name: http
  selector:
    app: plex
```

### 3. Túnel de Cloudflare (`configmap-tunnel.yml`)

El `ConfigMap` del túnel en el namespace `cloudflared` se configuró para apuntar directamente al servicio `ClusterIP` de Plex.

```yaml
# ... extracto de config.yml en el ConfigMap ...
    ingress:
      # ... otras reglas ...
      - hostname: plex.danielriquelme.cl
        service: http://plex.plex.svc.cluster.local:32400
        originRequest:
          noTLSVerify: true
      - service: http_status:404
```

### 4. Políticas de Red (`networkpolicy-ingress.yml`)

Se consolidó toda la lógica de ingreso en una única `NetworkPolicy` que permite la comunicación desde los namespaces necesarios:
- **`cloudflared`**: Para el acceso externo.
- **`arr-suite`**: Para que servicios como Sonarr, Radarr y Overseerr puedan comunicarse con Plex.
- **`default`**: Para permitir pruebas de conectividad interna.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-plex-ingress
  namespace: plex
spec:
  podSelector:
    matchLabels:
      app: plex
  policyTypes:
  - Ingress
  ingress:
  # Permite ingreso desde el túnel de Cloudflare
  - from:
    - namespaceSelector:
        matchLabels:
          name: cloudflared
  # Permite ingreso desde la suite *arr y Overseerr
  - from:
    - namespaceSelector:
        matchLabels:
          arr-suite: "true"
  # Permite ingreso desde el namespace 'default' para diagnóstico
  - from:
    - namespaceSelector:
        matchLabels:
          name: default
```
*Nota: Se eliminaron todas las demás políticas de ingreso y los manifiestos de Ingress de Traefik para Plex, ya que eran redundantes.*

## Verificación del Estado

Para asegurar que todo funciona correctamente:

1.  **Verificar el Pod de Plex:**
    ```bash
    kubectl get pods -n plex
    # El pod debe estar en estado 'Running'
    ```

2.  **Verificar los Logs de Plex:**
    Confirmar que Plex está escuchando en `0.0.0.0`.
    ```bash
    # Reemplaza <plex-pod-name> con el nombre real del pod
    kubectl exec -n plex <plex-pod-name> -- cat /proc/net/tcp | grep 7E90
    ```
    La salida debe mostrar una entrada con la dirección local `00000000:7E90`, que corresponde a `0.0.0.0:32400`.

3.  **Verificar el Túnel de Cloudflare:**
    ```bash
    kubectl logs -f deployment/cloudflared -n cloudflared
    # No deberían aparecer errores de conexión hacia el servicio de Plex.
    ```

4.  **Verificar Acceso Externo:**
    Accede a `https://plex.danielriquelme.cl`. La interfaz de Plex debe cargar correctamente y el acceso remoto en la configuración de Plex debe aparecer en verde.

## Conclusión

La configuración actual es robusta, segura y más simple que la anterior. El acceso remoto de Plex es estable y funciona a la máxima velocidad, y la comunicación interna para servicios como Overseerr está garantizada por la nueva política de red.
