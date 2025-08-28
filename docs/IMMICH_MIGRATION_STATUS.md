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

### En Progreso

1. **Despliegue en Kubernetes**
   - Los recursos de Immich han sido aplicados al clúster
   - Se ha corregido la política de red para permitir comunicación interna
   - Se está trabajando en la instalación de la extensión pgvector en PostgreSQL

2. **Migración de Datos**
   - El job de migración está esperando a que el servidor de Immich esté disponible

## Problemas Detectados

1. **Políticas de Red**
   - Se detectó que la política de red original bloqueaba el tráfico egress entre pods del mismo namespace
   - Se ha aplicado una corrección para permitir este tráfico

2. **Inicialización de la Base de Datos**
   - El servidor de Immich falla al iniciar porque falta la extensión "vector" en PostgreSQL
   - Se ha creado un job para instalar la extensión pgvector

3. **Problemas de Conectividad**
   - Se están experimentando problemas intermitentes de conexión con el clúster
   - Posible sobrecarga del API server o problemas de red

## Próximos Pasos

1. **Resolver Problemas de Conectividad**
   - Verificar el estado del clúster cuando la conexión se restablezca
   - Considerar reiniciar componentes del plano de control si es necesario

2. **Completar la Instalación de pgvector**
   - Verificar que el job para instalar pgvector se ha completado correctamente
   - Reiniciar los pods de Immich para que utilicen la nueva extensión

3. **Completar la Migración de Datos**
   - Verificar que el job de migración puede conectarse a la Raspberry Pi
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

# Verificar los logs del job de instalación de pgvector
kubectl logs -n immich $(kubectl get pods -n immich -l job-name=immich-fix-postgres-pgvector -o jsonpath='{.items[0].metadata.name}')

# Reiniciar los pods de Immich después de instalar pgvector
kubectl rollout restart deployment -n immich immich-server immich-microservices immich-web

# Verificar el estado del job de migración
kubectl logs -n immich $(kubectl get pods -n immich -l job-name=immich-migration-fixed -o jsonpath='{.items[0].metadata.name}')
```

## Notas y Recomendaciones

- Los problemas de conectividad pueden deberse a la sobrecarga del API server del clúster
- La instalación de pgvector es necesaria para que Immich pueda funcionar correctamente
- Una vez que la extensión pgvector esté instalada, los pods de Immich deberían iniciarse correctamente
- Si persisten los problemas, considerar recrear los pods de Immich uno por uno

Este documento será actualizado a medida que avance la migración.
