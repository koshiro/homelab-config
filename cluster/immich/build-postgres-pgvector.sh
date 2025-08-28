#!/bin/bash

# Script para construir la imagen de PostgreSQL con pgvector
# Asegúrate de tener Docker instalado y funcionando

# Directorio actual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Nombre de la imagen
IMAGE_NAME="postgres-pgvector:15-alpine"

# Construir la imagen
echo "Construyendo imagen $IMAGE_NAME..."
docker build -t $IMAGE_NAME -f $SCRIPT_DIR/Dockerfile.postgres-pgvector $SCRIPT_DIR

# Verificar si la construcción fue exitosa
if [ $? -eq 0 ]; then
    echo "Imagen $IMAGE_NAME construida exitosamente."
    echo "Para usar esta imagen en tu clúster, puedes:"
    echo "1. Etiquetar la imagen: docker tag $IMAGE_NAME tu-registro/postgres-pgvector:15-alpine"
    echo "2. Subir la imagen: docker push tu-registro/postgres-pgvector:15-alpine"
    echo "3. Actualizar el deployment para usar esta imagen"
else
    echo "Error al construir la imagen $IMAGE_NAME."
    exit 1
fi
