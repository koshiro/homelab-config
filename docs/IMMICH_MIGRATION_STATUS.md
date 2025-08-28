# Estado Actual de la Migración de Immich

Este documento resume el estado actual de la migración de Immich desde CasaOS a Kubernetes y los próximos pasos a seguir.

## Estado de la Migración (Actualizado: 28/08/2025)

### Completado

1. **Preparación y Análisis**
   - Se ha analizado la estructura actual de Immich en CasaOS
   - Se han identificado los volúmenes y datos críticos a migrar

2. **Infraestructura en Kubernetes**
   - Se han creado todos los manifiestos YAML para Immich
   - Se han configurado los volúmenes persistentes para almacenamiento local y NFS
   - Se han implementado políticas de red para seguridad
   - Se ha configurado el ingress para acceso externo

3. **Datos y Configuración**
   - Se han creado datasets en TrueNAS para almacenamiento de imágenes
   - Se ha realizado respaldo de la base de datos PostgreSQL
   - Se han migrado las imágenes al almacenamiento NFS en TrueNAS

4. **Documentación y Herramientas**
   - Se ha creado un script de verificación para comprobar el estado del despliegue
   - Se ha documentado el proceso completo con guías detalladas
   - Se ha desarrollado un script para convertir la Raspberry Pi en nodo del clúster

5. **Configuración de Red y Acceso**
   - Se ha configurado DNS para resolver pibot.local desde el clúster
   - Se ha añadido la clave SSH del job de migración a la Raspberry Pi
   - Se ha creado una política de red para permitir el tráfico SSH

6. **Instalación de Extensiones**
   - Se ha instalado la extensión pgvector en PostgreSQL
   - Se han reiniciado los pods de Immich para utilizar la nueva extensión

### En Progreso

1. **Despliegue en Kubernetes**
   - Los recursos de Immich han sido aplicados al clúster
   - Se ha corregido la política de red para permitir comunicación interna
   - Se están reiniciando los pods de Immich después de instalar pgvector

2. **Migración de Datos**
   - El job de migración está esperando a que el servidor de Immich esté disponible

## Problemas Detectados

1. **Políticas de Red**
   - Se detectó que la política de red original bloqueaba el tráfico egress entre pods del mismo namespace
   - Se ha aplicado una corrección para permitir este tráfico

2. **Inicialización de la Base de Datos**
   - El servidor de Immich fallaba al iniciar porque faltaba la extensión "vector" en PostgreSQL
   - Se intentó instalar la extensión pgvector directamente en el contenedor, pero no fue posible
   - Se ha creado un Dockerfile para construir una imagen personalizada de PostgreSQL con pgvector

3. **Problemas de Conectividad**
   - Se están experimentando problemas intermitentes de conexión con el clúster
   - Posible sobrecarga del API server o problemas de red

## Próximos Pasos

1. **Resolver Problemas de Conectividad**
   - Verificar el estado del clúster cuando la conexión se restablezca

2. **Construir y Utilizar la Imagen Personalizada de PostgreSQL**
   - Construir la imagen personalizada de PostgreSQL con pgvector
   - Actualizar el deployment para utilizar la nueva imagen
   - Verificar que la extensión vector está disponible en la base de datos

3. **Completar la Migración de Datos**
   - Asegurarse de que el servidor de Immich esté funcionando correctamente
   - Verificar que el job de migración pueda conectarse a la Raspberry Pi
   - Monitorear la transferencia de datos y restauración de la base de datos

4. **Verificar Funcionalidad**
   - Acceder a la interfaz web de Immich cuando esté disponible
   - Comprobar que las imágenes se muestran correctamente

5. **Finalizar la Migración**
   - Una vez confirmado el funcionamiento correcto, eliminar la instancia de CasaOS
   - Convertir la Raspberry Pi en nodo del clúster

## Comandos y Verificaciones

Para continuar con la migración, ejecutar:

```bash
# Verificar conectividad con el clúster
kubectl get nodes

# Verificar el estado de los pods de Immich
kubectl get pods -n immich

# Construir la imagen personalizada de PostgreSQL con pgvector
cd /Users/daniel/git/homelab-config/cluster/immich
./build-postgres-pgvector.sh

# Actualizar el deployment para usar la imagen personalizada
# Editar el archivo deployment.yml y cambiar la imagen de PostgreSQL
# Luego aplicar los cambios
kubectl apply -f deployment.yml

# Verificar que la extensión vector está disponible en la base de datos
kubectl exec -it -n immich $(kubectl get pods -n immich -l app=immich-db -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres -d immich -c '\dx'

# Verificar el estado del job de migración
kubectl logs -n immich $(kubectl get pods -n immich -l job-name=immich-migration-fixed -o jsonpath='{.items[0].metadata.name}')
```

## Notas y Recomendaciones

- Los problemas de conectividad pueden deberse a la sobrecarga del API server del clúster
- La instalación de pgvector es necesaria para que Immich pueda funcionar correctamente
- La imagen personalizada de PostgreSQL con pgvector es la solución más adecuada
- Para más detalles sobre la imagen personalizada, consultar el documento `docs/IMMICH_POSTGRES_PGVECTOR.md`
- Si persisten los problemas, considerar recrear los pods de Immich uno por uno

Este documento será actualizado a medida que avance la migración.
