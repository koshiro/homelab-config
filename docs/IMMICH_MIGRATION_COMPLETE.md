# Guía completa: Migración de Immich desde CasaOS a Kubernetes

Esta guía documenta el proceso completo para migrar una instancia de Immich que se ejecuta en una Raspberry Pi CM4 con CasaOS a un clúster Kubernetes, almacenando la configuración y la base de datos en almacenamiento local, y las imágenes en TrueNAS.

## Visión general del proceso

El proceso de migración se divide en las siguientes etapas:

1. Preparación y análisis del entorno actual
2. Creación de la infraestructura necesaria en Kubernetes
3. Migración de datos
4. Verificación y pruebas
5. Limpieza y configuración final

## Prerrequisitos

- Acceso SSH a la Raspberry Pi CM4 (pibot.local)
- Acceso al clúster Kubernetes
- Acceso a la interfaz web de ArgoCD
- TrueNAS configurado y accesible
- Git configurado y acceso al repositorio de configuración

## 1. Preparación y análisis del entorno actual

### 1.1 Estructura de Immich en CasaOS

Immich en CasaOS utiliza la siguiente estructura:
- Base de datos PostgreSQL: `/DATA/AppData/immich/pgdata`
- Redis: `/DATA/AppData/immich/redis`
- Datos de imágenes: `/DATA/Gallery/immich/upload` y `/DATA/Gallery/immich/library`

### 1.2 Respaldo de la base de datos

```bash
# Conectarse a la Raspberry Pi
ssh daniel@pibot.local

# Crear un respaldo de la base de datos PostgreSQL
sudo docker exec immich-postgres pg_dumpall -U postgres > /tmp/immich_db_backup.sql
```

### 1.3 Análisis de la configuración

Examinar las variables de entorno y la configuración para replicarlas en Kubernetes:

```bash
sudo docker exec immich-server env | grep -v PATH | grep -v HOME
```

## 2. Creación de la infraestructura en Kubernetes

### 2.1 Estructura de directorios en el repositorio

```
cluster/immich/
├── deployment.yml        # Despliegue de componentes de Immich
├── ingress.yml           # Configuración de ingress para acceso externo
├── job-configure-truenas.yml # Job para configurar TrueNAS
├── kustomization.yml     # Configuración de kustomize
├── migration-job.yml     # Job para migración de datos
├── namespace.yml         # Namespace de Immich
├── networkpolicy-*.yml   # Políticas de red
├── pv.yml                # Volúmenes persistentes
├── pvc.yml               # Claims de volúmenes
├── secrets.sops.yml      # Secretos cifrados con SOPS
└── service.yml           # Definición de servicios
```

### 2.2 Crear datasets en TrueNAS

Se crean automáticamente mediante el job de configuración, que utiliza la API de TrueNAS:
- `homelab-storage/media/immich_library`
- `homelab-storage/media/immich_upload`

### 2.3 Configuración de volúmenes persistentes

- **Configuración y base de datos**: Almacenados localmente usando `local-path`
- **Datos de imágenes**: Almacenados en TrueNAS usando `nfs-csi`

### 2.4 Implementación en Git y ArgoCD

1. Añadir los archivos de configuración al repositorio Git
2. Hacer commit y push al repositorio
3. Sincronizar a través de ArgoCD

## 3. Migración de datos

### 3.1 Migrar archivos de imágenes

Las imágenes se migran directamente a TrueNAS:

```bash
# En la Raspberry Pi
sudo rsync -av --progress /DATA/Gallery/immich/ /tmp/immich_backup/
```

### 3.2 Job de migración de datos

El job de migración realiza las siguientes tareas:
1. Establece una conexión SSH con la Raspberry Pi
2. Copia el respaldo de la base de datos
3. Restaura la base de datos en la nueva instancia

Para completar este proceso, es necesario seguir los siguientes pasos:
1. Obtener la clave pública SSH generada por el job
2. Añadirla a la Raspberry Pi en `~/.ssh/authorized_keys`
3. Monitorizar el progreso en los logs del job

## 4. Verificación y pruebas

### 4.1 Script de verificación

Se proporciona un script de verificación que comprueba:
- Estado de los pods
- Conectividad de red
- Acceso a la base de datos
- Montaje de volúmenes
- Acceso externo

```bash
./scripts/verify-immich.sh
```

### 4.2 Pruebas manuales

Una vez que la migración se haya completado, se deben realizar las siguientes pruebas:
- Acceder a la interfaz web de Immich
- Verificar que todas las imágenes están presentes
- Comprobar la funcionalidad de búsqueda
- Verificar que la generación de miniaturas funciona correctamente

## 5. Limpieza y configuración final

### 5.1 Eliminar la instancia de CasaOS

Una vez que la verificación sea exitosa, se puede eliminar la instancia de Immich en CasaOS.

### 5.2 Convertir la Raspberry Pi en un nodo del clúster

Utilizando el script proporcionado:

```bash
./scripts/convert-pi-to-cluster-node.sh
```

Este script:
1. Detiene los servicios de CasaOS
2. Desinstala CasaOS y Docker
3. Configura los cgroups necesarios para Kubernetes
4. Instala K3s como agente
5. Une la Raspberry Pi al clúster existente

## Solución de problemas

### Problemas de conexión con TrueNAS
- Verificar que TrueNAS es accesible desde el clúster
- Comprobar la API key y permisos
- Verificar que el servicio NFS está activo

### Errores en la restauración de la base de datos
- Verificar la compatibilidad de versiones de PostgreSQL
- Comprobar que el respaldo es válido
- Verificar permisos de acceso

### Problemas de red
- Verificar las políticas de red en Kubernetes
- Comprobar la configuración de Ingress
- Verificar la configuración de DNS

## Conclusión

La migración de Immich desde una Raspberry Pi CM4 con CasaOS a un clúster Kubernetes proporciona mayor escalabilidad, resistencia y opciones de gestión. El uso de TrueNAS para el almacenamiento de imágenes garantiza un almacenamiento seguro y escalable, mientras que la ejecución en Kubernetes permite una mejor gestión de recursos y alta disponibilidad.




