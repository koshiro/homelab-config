# Guía de migración de Immich desde CasaOS a Kubernetes

Este documento detalla el proceso para migrar la instancia de Immich desde una Raspberry Pi CM4 con CasaOS a nuestro clúster Kubernetes, manteniendo la configuración y base de datos en almacenamiento local y las imágenes en TrueNAS.

## Prerrequisitos

1. Acceso SSH a la Raspberry Pi con Immich en CasaOS
2. Acceso al clúster Kubernetes
3. Acceso a TrueNAS para configurar los datasets
4. Herramientas: rsync, ssh, kubectl, sops, git

## Paso 1: Crear datasets en TrueNAS

1. Acceder a la interfaz web de TrueNAS (192.168.1.20)
2. Crear los siguientes datasets:
   - `homelab-storage/media/immich_library`: Para la biblioteca de imágenes
   - `homelab-storage/media/immich_upload`: Para las cargas temporales

3. Configurar permisos en ambos datasets:
   - Usuario: 1000
   - Grupo: 1000
   - Permisos: 0755

Alternativamente, esto se puede hacer automáticamente a través del job de configuración incluido en el despliegue.

## Paso 2: Respaldar datos de Immich en CasaOS

1. **Identificar contenedores y volúmenes**: En la Raspberry Pi, ejecutar:
   ```bash
   cd /path/to/immich
   docker-compose ps
   docker-compose config
   ```

2. **Respaldar la base de datos PostgreSQL**:
   ```bash
   # Identificar el contenedor de PostgreSQL
   POSTGRES_CONTAINER=$(docker ps -qf name=immich-postgres)
   
   # Respaldar la base de datos
   docker exec $POSTGRES_CONTAINER pg_dump -U postgres -d immich > immich_backup.sql
   
   # Transferir el respaldo a una ubicación segura
   scp immich_backup.sql usuario@servidor:/ruta/segura/
   ```

3. **Respaldar archivos de configuración**:
   ```bash
   # Copiar archivos de configuración relevantes
   cp .env immich_env_backup
   cp docker-compose.yml immich_compose_backup.yml
   
   # Transferir los respaldos a una ubicación segura
   scp immich_env_backup immich_compose_backup.yml usuario@servidor:/ruta/segura/
   ```

4. **Migrar imágenes y otros archivos a TrueNAS**:
   ```bash
   # Ubicar la ruta de los volúmenes de datos
   LIBRARY_PATH=$(docker inspect -f '{{ range .Mounts }}{{ if eq .Destination "/usr/src/app/library" }}{{ .Source }}{{ end }}{{ end }}' $IMMICH_CONTAINER)
   UPLOAD_PATH=$(docker inspect -f '{{ range .Mounts }}{{ if eq .Destination "/usr/src/app/upload" }}{{ .Source }}{{ end }}{{ end }}' $IMMICH_CONTAINER)
   
   # Sincronizar datos a TrueNAS usando rsync
   rsync -avz --progress $LIBRARY_PATH/ usuario@192.168.1.20:/mnt/homelab-storage/media/immich_library/
   rsync -avz --progress $UPLOAD_PATH/ usuario@192.168.1.20:/mnt/homelab-storage/media/immich_upload/
   ```

## Paso 3: Configurar Kubernetes para Immich

1. **Crear secretos encriptados**:
   ```bash
   # Obtener contraseña de la DB del archivo .env de CasaOS
   DB_PASSWORD=$(grep DB_PASSWORD immich_env_backup | cut -d '=' -f2)
   
   # Crear archivo de secretos
   cp cluster/immich/secrets.sops.yml.example cluster/immich/secrets.sops.yml
   sed -i "s/contraseña_segura_de_postgres/$DB_PASSWORD/g" cluster/immich/secrets.sops.yml
   
   # Encriptar secretos con SOPS
   sops -e -i cluster/immich/secrets.sops.yml
   ```

2. **Aplicar configuración al clúster**:
   ```bash
   # Desplegar los recursos en el clúster
   kubectl apply -k cluster/immich/
   ```

## Paso 4: Restaurar la base de datos en la instancia de Kubernetes

1. **Esperar a que los pods estén listos**:
   ```bash
   watch kubectl get pods -n immich
   ```

2. **Restaurar base de datos**:
   ```bash
   # Identificar el pod de PostgreSQL
   POSTGRES_POD=$(kubectl get pod -n immich -l app=immich-db -o jsonpath='{.items[0].metadata.name}')
   
   # Copiar el respaldo al pod
   kubectl cp /ruta/segura/immich_backup.sql immich/$POSTGRES_POD:/tmp/
   
   # Restaurar la base de datos
   kubectl exec -it -n immich $POSTGRES_POD -- sh -c "psql -U postgres -d immich < /tmp/immich_backup.sql"
   ```

## Paso 5: Verificar la migración

1. **Ejecutar el script de verificación**:
   ```bash
   ./scripts/verify-immich.sh
   ```

2. **Verificar acceso web**:
   - Abrir https://immich.danielriquelme.cl en el navegador
   - Iniciar sesión con tus credenciales existentes
   - Verificar que todas las imágenes y álbumes estén presentes

## Paso 6: Eliminar la instancia original en CasaOS

Una vez que hayas verificado que la nueva instancia funciona correctamente:

1. **Detener y eliminar los contenedores en CasaOS**:
   ```bash
   cd /path/to/immich
   docker-compose down
   ```

2. **Eliminar la aplicación en la interfaz de CasaOS**

## Paso 7: Convertir la Raspberry Pi en nodo del clúster

1. **Instalar sistema operativo limpio**:
   - Formatear la tarjeta/almacenamiento
   - Instalar un sistema operativo compatible con Kubernetes (Ubuntu Server recomendado)

2. **Instalar dependencias de Kubernetes**:
   - Seguir guías oficiales para configurar un nodo trabajador
   - Unirlo al clúster existente

3. **Etiquetar el nodo para cargas de trabajo específicas**:
   ```bash
   kubectl label node pibot.local workload-type=lightweight
   ```

## Problemas comunes y soluciones

### La base de datos no se restaura correctamente
- Verificar que la versión de PostgreSQL sea compatible
- Intentar restaurar solo esquema y datos por separado

### Las imágenes no aparecen después de la migración
- Verificar permisos en los datasets de TrueNAS
- Comprobar que los volúmenes persistentes están montados correctamente
- Revisar logs del servidor: `kubectl logs -n immich -l app=immich-server`

### Problemas de red en el clúster
- Verificar políticas de red
- Comprobar conectividad entre componentes: `kubectl exec -it -n immich <pod> -- nc -zv <servicio> <puerto>`

## Referencias
- Documentación oficial de Immich: https://immich.app/docs/install/kubernetes
- Documentación de migración de Docker a Kubernetes: https://kubernetes.io/docs/tasks/configure-pod-container/translate-compose-kubernetes/
