# Despliegue de Immich en Kubernetes usando Helm

Este directorio contiene la configuración necesaria para desplegar Immich en Kubernetes utilizando el Helm Chart oficial.

## Prerrequisitos

- Kubernetes cluster (K3s, K8s, etc.)
- Helm v3 instalado
- StorageClass `local-path` para datos de PostgreSQL y Redis
- StorageClass `nfs-csi` para almacenamiento de imágenes y videos
- PersistentVolumeClaims `immich-library-pvc` y `immich-upload-pvc` ya creados
- Traefik como Ingress Controller
- Authelia configurado para autenticación

## Instalación

1. Añadir el repositorio de Helm de Immich:

```bash
helm repo add immich https://immich-app.github.io/immich-charts
helm repo update
```

2. Instalar Immich usando los valores personalizados:

```bash
helm install immich immich/immich -n immich --create-namespace -f values.yaml
```

## Configuración

El archivo `values.yaml` contiene la configuración personalizada para nuestro despliegue de Immich:

- Uso de StorageClass `local-path` para PostgreSQL y Redis
- Uso de StorageClass `nfs-csi` para almacenamiento de imágenes y videos
- Configuración de Ingress con Traefik y Authelia
- Habilitación del componente de Machine Learning
- Configuración de recursos para cada componente
- Configuración de NetworkPolicy para seguridad

## Volúmenes persistentes

Antes de instalar Immich, asegúrate de que los siguientes PVCs estén creados:

- `immich-library-pvc`: Para almacenamiento de la biblioteca de imágenes
- `immich-upload-pvc`: Para almacenamiento de las imágenes subidas

## Acceso

Una vez desplegado, Immich estará disponible en:

- https://immich.danielriquelme.cl

La autenticación se realiza a través de Authelia.

## Notas importantes

1. La base de datos PostgreSQL incluye la extensión pgvector necesaria para las funcionalidades de búsqueda avanzada de Immich.
2. Se han configurado NetworkPolicies para permitir solo el tráfico necesario entre los componentes.
3. Los volúmenes persistentes para la biblioteca y las imágenes subidas deben ser creados previamente y tener los permisos adecuados.

## Migración de datos

Para migrar datos desde una instalación existente de Immich:

1. Crea un trabajo de Kubernetes para copiar las imágenes:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: immich-migration
  namespace: immich
spec:
  template:
    spec:
      containers:
      - name: rsync
        image: instrumentisto/rsync-ssh:alpine
        command: ["/bin/sh", "-c"]
        args:
        - |
          mkdir -p ~/.ssh
          echo "StrictHostKeyChecking no" > ~/.ssh/config
          chmod 600 ~/.ssh/config
          ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
          echo "Clave pública generada:"
          cat ~/.ssh/id_rsa.pub
          # Esperar a que se agregue la clave SSH
          sleep 30
          # Migrar imágenes
          rsync -avz --progress usuario@origen:/ruta/origen/biblioteca/ /usr/src/app/library/
          rsync -avz --progress usuario@origen:/ruta/origen/subidas/ /usr/src/app/upload/
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
```

2. Importar las imágenes desde la interfaz de usuario de Immich una vez que la migración haya finalizado.
