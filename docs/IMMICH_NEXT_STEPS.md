# Próximos Pasos para la Migración de Immich

Este documento describe los próximos pasos a seguir para completar la migración de Immich desde CasaOS a Kubernetes una vez que se resuelvan los problemas de conectividad con el clúster.

## 1. Verificar la Instalación de pgvector

El primer paso es verificar si la extensión pgvector se ha instalado correctamente en la base de datos PostgreSQL:

```bash
# Verificar el estado del job de instalación de pgvector
kubectl logs -n immich immich-fix-postgres-pgvector-5cddb

# Si el job ha fallado o no se ha completado, ejecutar:
kubectl delete job -n immich immich-fix-postgres-pgvector
kubectl apply -f /Users/daniel/git/homelab-config/cluster/immich/fix-postgres-pgvector.yml
```

## 2. Verificar la Extensión en PostgreSQL

Una vez que el job se haya completado, verificar que la extensión vector está instalada en la base de datos:

```bash
# Conectarse a la base de datos PostgreSQL
kubectl exec -it -n immich immich-db-65b544fc-4sxfg -- psql -U postgres -d immich

# Dentro de PostgreSQL, verificar las extensiones instaladas
\dx

# La extensión "vector" debería aparecer en la lista
# Salir de PostgreSQL
\q
```

## 3. Reiniciar los Pods de Immich

Una vez que la extensión pgvector esté instalada, reiniciar los pods de Immich para que utilicen la nueva extensión:

```bash
# Reiniciar los deployments de Immich
kubectl rollout restart deployment -n immich immich-server immich-microservices immich-web

# Verificar que los pods se están reiniciando
kubectl get pods -n immich -w
```

## 4. Verificar el Estado de los Pods

Esperar a que todos los pods estén en estado "Running":

```bash
# Verificar el estado de los pods
kubectl get pods -n immich

# Verificar los logs del servidor de Immich
kubectl logs -n immich $(kubectl get pods -n immich -l app=immich-server -o jsonpath='{.items[0].metadata.name}')
```

## 5. Verificar el Job de Migración

Una vez que el servidor de Immich esté funcionando correctamente, verificar el estado del job de migración:

```bash
# Verificar el estado del job de migración
kubectl logs -n immich immich-migration-fixed-ws8z7

# Si el job está esperando a que el servidor de Immich esté listo, debería continuar automáticamente
# Si el job ha fallado, puede ser necesario eliminarlo y recrearlo:
kubectl delete job -n immich immich-migration-fixed
kubectl apply -f /Users/daniel/git/homelab-config/cluster/immich/migration-job-updated.yml
```

## 6. Preparar la Base de Datos en la Raspberry Pi

Antes de ejecutar el job de migración, es necesario crear un dump de la base de datos en la Raspberry Pi:

```bash
# Conectarse a la Raspberry Pi
ssh daniel@pibot.local

# Crear un dump de la base de datos
sudo docker exec immich-postgres pg_dump -U postgres -d immich > /tmp/immich_db_backup.sql

# Verificar que el dump se ha creado correctamente
ls -la /tmp/immich_db_backup.sql

# Salir de la Raspberry Pi
exit
```

## 7. Verificar la Funcionalidad de Immich

Una vez que la migración se haya completado, verificar que Immich funciona correctamente:

```bash
# Verificar que el ingress está configurado correctamente
kubectl get ingress -n immich

# Acceder a la interfaz web de Immich en https://immich.danielriquelme.cl
# Verificar que todas las imágenes se muestran correctamente
```

## 8. Eliminar la Instancia de CasaOS

Si todo funciona correctamente, eliminar la instancia de Immich en CasaOS:

```bash
# Conectarse a la Raspberry Pi
ssh daniel@pibot.local

# Detener los contenedores de Immich
sudo docker stop immich-server immich-microservices immich-web immich-postgres immich-redis

# Eliminar los contenedores
sudo docker rm immich-server immich-microservices immich-web immich-postgres immich-redis

# Salir de la Raspberry Pi
exit
```

## 9. Convertir la Raspberry Pi en Nodo del Clúster

Finalmente, convertir la Raspberry Pi en un nodo del clúster Kubernetes:

```bash
# Conectarse a la Raspberry Pi
ssh daniel@pibot.local

# Ejecutar el script de conversión
curl -sfL https://raw.githubusercontent.com/koshiro/homelab-config/main/scripts/convert-pi-to-cluster-node.sh | sudo bash

# Verificar que el nodo se ha unido al clúster
kubectl get nodes
```

## Notas Importantes

- Si en algún momento se pierde la conexión con el clúster, esperar unos minutos e intentar nuevamente.
- Si los pods de Immich siguen fallando después de instalar pgvector, puede ser necesario modificar la imagen de Immich para incluir la extensión pgvector.
- Asegurarse de hacer copias de seguridad de los datos importantes antes de eliminar la instancia de CasaOS.

Este documento será actualizado a medida que avance la migración.




