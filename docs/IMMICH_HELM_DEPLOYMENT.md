# Despliegue de Immich en Kubernetes usando Helm

Este documento detalla el proceso de despliegue de Immich en Kubernetes utilizando el Helm Chart oficial.

## Configuración realizada

1. **Creación de estructura de directorios**:
   ```bash
   mkdir -p /Users/daniel/git/homelab-config/cluster/immich-helm
   ```

2. **Configuración de valores personalizados**:
   Se creó un archivo `values.yaml` con la siguiente configuración:
   - Uso de PersistentVolumeClaims existentes para la biblioteca y uploads
   - Configuración de la base de datos PostgreSQL existente
   - Configuración de Ingress con Traefik y Authelia
   - Configuración de recursos para cada componente
   - Configuración de NetworkPolicy para seguridad

3. **Inicialización de volúmenes persistentes**:
   Se creó un Job para inicializar la estructura de directorios y permisos en los volúmenes persistentes:
   ```yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: immich-init-volumes
     namespace: immich
   spec:
     template:
       spec:
         securityContext:
           runAsUser: 0
           runAsGroup: 0
           fsGroup: 0
         containers:
         - name: init-volumes
           image: busybox:1.36
           command: ["/bin/sh", "-c"]
           args:
           - |
             # Crear estructura de directorios para upload
             mkdir -p /usr/src/app/upload/encoded-video
             mkdir -p /usr/src/app/upload/profile
             mkdir -p /usr/src/app/upload/library
             mkdir -p /usr/src/app/upload/upload
             
             # Crear archivos .immich para verificación de integridad
             touch /usr/src/app/upload/.immich
             touch /usr/src/app/upload/encoded-video/.immich
             touch /usr/src/app/upload/profile/.immich
             touch /usr/src/app/upload/library/.immich
             touch /usr/src/app/upload/upload/.immich
             
             # Crear estructura de directorios para library
             mkdir -p /usr/src/app/library
             touch /usr/src/app/library/.immich
             
             # Establecer permisos adecuados
             chmod -R 777 /usr/src/app/upload
             chmod -R 777 /usr/src/app/library
             
             echo "Inicialización de volúmenes completada."
           volumeMounts:
           - name: library
             mountPath: /usr/src/app/library
           - name: upload
             mountPath: /usr/src/app/upload
         volumes:
         - name: library
           persistentVolumeClaim:
             claimName: immich-library-pvc
         - name: upload
           persistentVolumeClaim:
             claimName: immich-upload-pvc
         restartPolicy: Never
     backoffLimit: 1
   ```

4. **Eliminación de recursos existentes**:
   Para evitar conflictos con la instalación de Helm, se eliminaron los recursos existentes:
   ```bash
   kubectl delete -n immich deployment.apps/immich-server deployment.apps/immich-web deployment.apps/immich-microservices service/immich-server service/immich-web
   kubectl delete -n immich ingress immich
   ```

5. **Instalación con Helm**:
   ```bash
   helm install immich immich/immich -n immich -f values.yaml
   ```

## Problemas encontrados y soluciones

1. **Error con el subchart de PostgreSQL**:
   - **Problema**: El subchart de PostgreSQL está deprecado en el Helm Chart de Immich.
   - **Solución**: Deshabilitar el subchart de PostgreSQL (`postgresql.enabled: false`) y configurar la conexión a la base de datos existente.

2. **Conflicto con recursos existentes**:
   - **Problema**: Los recursos existentes (deployments, services, ingress) impedían la instalación con Helm.
   - **Solución**: Eliminar los recursos existentes antes de instalar con Helm.

3. **Inicialización de volúmenes persistentes**:
   - **Problema**: Immich requiere una estructura específica de directorios y archivos `.immich` para la verificación de integridad.
   - **Solución**: Crear un Job para inicializar los volúmenes persistentes con la estructura requerida.

## Estado actual

Immich ha sido desplegado exitosamente usando el Helm Chart oficial. La aplicación está configurada para:

1. Usar volúmenes persistentes existentes para la biblioteca y uploads.
2. Usar la base de datos PostgreSQL existente con la extensión pgvector.
3. Usar Redis para caché.
4. Exponer la aplicación a través de Ingress con Traefik y autenticación con Authelia.
5. Aplicar políticas de red para seguridad.

## Próximos pasos

1. Verificar el funcionamiento de Immich una vez que se restablezca la conexión con el clúster.
2. Eliminar la instancia de Immich en CasaOS.
3. Configurar la Raspberry Pi CM4 como nodo del clúster.
