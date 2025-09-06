# Configuración de PostgreSQL con pgvector para Immich

Este documento describe cómo crear y utilizar una imagen personalizada de PostgreSQL con la extensión pgvector, necesaria para el funcionamiento de Immich.

## Problema

Immich requiere la extensión `vector` de PostgreSQL para funcionar correctamente. Esta extensión no viene incluida en la imagen estándar de PostgreSQL y debe ser instalada manualmente.

## Solución

Hemos creado un Dockerfile y un script para construir una imagen personalizada de PostgreSQL que incluye la extensión pgvector.

### Archivos Creados

1. **`Dockerfile.postgres-pgvector`**: Define cómo construir la imagen personalizada.
2. **`build-postgres-pgvector.sh`**: Script para facilitar la construcción de la imagen.

## Pasos para Construir la Imagen

1. **Requisitos previos**:
   - Docker instalado y funcionando
   - Acceso a Internet para descargar las dependencias

2. **Construir la imagen**:
   ```bash
   # Navegar al directorio del proyecto
   cd /Users/daniel/git/homelab-config/cluster/immich

   # Ejecutar el script de construcción
   ./build-postgres-pgvector.sh
   ```

3. **Etiquetar y subir la imagen** (si se utiliza un registro privado):
   ```bash
   # Etiquetar la imagen
   docker tag postgres-pgvector:15-alpine tu-registro/postgres-pgvector:15-alpine

   # Subir la imagen
   docker push tu-registro/postgres-pgvector:15-alpine
   ```

## Utilizar la Imagen en Kubernetes

Para utilizar esta imagen en tu despliegue de Immich, necesitas modificar el archivo `deployment.yml`:

1. **Modificar el deployment de la base de datos**:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: immich-db
     namespace: immich
   spec:
     # ...
     template:
       # ...
       spec:
         containers:
           - name: immich-db
             # Reemplazar esta línea:
             # image: postgres:15-alpine
             # Con esta:
             image: tu-registro/postgres-pgvector:15-alpine
             # ...
   ```

2. **Aplicar los cambios**:
   ```bash
   kubectl apply -f /Users/daniel/git/homelab-config/cluster/immich/deployment.yml
   ```

3. **Verificar que la extensión está instalada**:
   ```bash
   # Conectarse a la base de datos
   kubectl exec -it -n immich $(kubectl get pods -n immich -l app=immich-db -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres -d immich

   # Verificar las extensiones instaladas
   \dx

   # Salir de PostgreSQL
   \q
   ```

## Notas Importantes

- La imagen construida incluye PostgreSQL 15 con pgvector v0.7.0.
- La construcción de la imagen puede tardar varios minutos, dependiendo de la velocidad de tu conexión a Internet y del rendimiento de tu máquina.
- Si necesitas actualizar la versión de pgvector, debes modificar el Dockerfile y reconstruir la imagen.
- Asegúrate de que los datos de PostgreSQL estén respaldados antes de cambiar la imagen, aunque el cambio no debería afectar a los datos almacenados.

## Solución Alternativa: Instalación Manual

Si no puedes o no quieres construir una imagen personalizada, puedes instalar pgvector manualmente en un contenedor existente:

```bash
# Conectarse al contenedor de PostgreSQL
kubectl exec -it -n immich $(kubectl get pods -n immich -l app=immich-db -o jsonpath='{.items[0].metadata.name}') -- bash

# Instalar dependencias
apt-get update && apt-get install -y git build-essential postgresql-server-dev-15

# Clonar y compilar pgvector
git clone --branch v0.7.0 https://github.com/pgvector/pgvector.git
cd pgvector
make
make install

# Crear la extensión en la base de datos
psql -U postgres -d immich -c 'CREATE EXTENSION IF NOT EXISTS vector;'

# Verificar que la extensión está instalada
psql -U postgres -d immich -c '\dx'

# Salir del contenedor
exit
```

Sin embargo, ten en cuenta que esta instalación manual se perderá si el pod se reinicia, por lo que es preferible utilizar la imagen personalizada.




