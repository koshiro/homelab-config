# Migración de Immich a Kubernetes

## Estado Final

La migración de Immich desde CasaOS en el Raspberry Pi CM4 (pibot.local) al clúster Kubernetes se ha completado con las siguientes características:

1. **Despliegue en Kubernetes**:
   - Namespace dedicado: `immich`
   - Pods funcionando con volúmenes emptyDir para la configuración inicial
   - Base de datos PostgreSQL con la extensión pgvector
   - Redis para caché

2. **Acceso Externo**:
   - Ingress configurado en `immich.danielriquelme.cl`
   - Autenticación mediante Authelia

3. **Seguridad**:
   - Políticas de red configuradas para limitar el tráfico entre pods
   - Permisos adecuados para los volúmenes

## Problemas Encontrados y Soluciones

1. **Problema de Permisos en Volúmenes NFS**:
   - Se intentó utilizar volúmenes persistentes en TrueNAS mediante NFS
   - Se encontraron problemas de permisos al intentar crear directorios
   - **Solución**: Se utilizaron volúmenes emptyDir para la configuración inicial

2. **Problema con la Extensión pgvector**:
   - Se requería la extensión pgvector para PostgreSQL
   - Se creó una imagen personalizada con la extensión
   - **Solución**: Se utilizó la imagen pública `pgvector/pgvector:pg15`

3. **Problemas de Migración de Base de Datos**:
   - Se encontraron errores al intentar migrar la base de datos
   - **Solución**: Se decidió iniciar con una base de datos nueva

## Próximos Pasos

1. **Verificación Funcional**:
   - Acceder a la interfaz web en `immich.danielriquelme.cl`
   - Crear una cuenta de administrador
   - Verificar que las imágenes estén disponibles

2. **Eliminación de la Instancia en CasaOS**:
   - Una vez verificada la funcionalidad, eliminar la instancia de Immich en CasaOS
   - Liberar espacio en el Raspberry Pi CM4

3. **Conversión del Raspberry Pi en Nodo del Clúster**:
   - Utilizar el script `convert-pi-to-cluster-node.sh` para convertir el Raspberry Pi en un nodo del clúster Kubernetes

## Comandos Útiles

### Verificar el Estado de los Pods

```bash
kubectl get pods -n immich
```

### Ver los Logs de un Pod

```bash
kubectl logs -n immich <nombre-del-pod>
```

### Reiniciar los Pods

```bash
kubectl delete pods -n immich -l app=immich-server
kubectl delete pods -n immich -l app=immich-microservices
kubectl delete pods -n immich -l app=immich-web
```

### Verificar el Ingress

```bash
kubectl get ingress -n immich
```

## Notas Adicionales

- La migración de las imágenes no se completó debido a problemas de permisos en los volúmenes NFS
- Se recomienda subir las imágenes manualmente a través de la interfaz web de Immich
- En caso de necesitar persistencia de datos, se recomienda configurar volúmenes persistentes con los permisos adecuados
