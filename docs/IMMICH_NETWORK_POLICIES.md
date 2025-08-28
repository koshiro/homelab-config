# Solución a problemas de red en Immich en Kubernetes

## Problema

Al intentar acceder a Immich a través de la URL `https://immich.danielriquelme.cl`, se presentaba un error 404. Después de investigar a fondo, se identificaron varios problemas relacionados con las políticas de red y la configuración de Ingress.

## Causas identificadas

1. **Falta de NetworkPolicy para permitir acceso desde Traefik al API de Immich**: Aunque existía una política para permitir acceso a `immich-web` desde Traefik, no había una política similar para permitir acceso a `immich-server` en el puerto 3001, que es donde se encuentra el API.

2. **Falta de NetworkPolicy para permitir tráfico entre immich-web e immich-server**: El componente web de Immich necesita comunicarse con el componente server para funcionar correctamente. Los logs mostraban errores de conexión rechazada entre estos componentes.

3. **Configuración de Ingress incompleta**: La configuración del Ingress no estaba completamente alineada con la configuración de otros servicios en el cluster.

## Soluciones implementadas

### 1. NetworkPolicy para permitir acceso desde Traefik al API de Immich

Se creó una política de red para permitir que Traefik acceda al API de Immich:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-ingress
  namespace: immich
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: traefik
      podSelector:
        matchLabels:
          app.kubernetes.io/name: traefik
    ports:
    - port: 3001
      protocol: TCP
  podSelector:
    matchLabels:
      app: immich-server
  policyTypes:
  - Ingress
```

### 2. NetworkPolicy para permitir tráfico entre immich-web e immich-server

Se creó una política de red para permitir que el componente web se comunique con el componente server:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-server
  namespace: immich
spec:
  podSelector:
    matchLabels:
      app: immich-server
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: immich-web
    ports:
    - protocol: TCP
      port: 3001
  policyTypes:
  - Ingress
```

### 3. Verificación de la configuración de Ingress

Se verificó que la configuración del Ingress estuviera alineada con otros servicios en el cluster, especialmente en cuanto a:

- Uso de `ingressClassName: traefik`
- Anotaciones correctas para Traefik
- Configuración de middleware para Authelia

## Estado actual

A pesar de implementar estas soluciones, los pods de Immich siguen teniendo problemas para iniciarse correctamente. Los logs muestran que el componente web sigue sin poder conectarse al componente server, lo que sugiere que puede haber problemas adicionales que necesitan ser investigados.

## Próximos pasos

1. Investigar por qué los pods de Immich no se están registrando correctamente en los endpoints
2. Verificar si hay problemas con los volúmenes o la configuración de almacenamiento
3. Considerar una revisión completa de la configuración de Immich, posiblemente utilizando la configuración oficial como referencia
