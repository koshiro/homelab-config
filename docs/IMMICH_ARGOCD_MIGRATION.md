# Configuración de la migración de Immich mediante ArgoCD

## Introducción

Este documento describe los pasos necesarios para sincronizar la configuración de Immich con el clúster a través de ArgoCD y completar la migración desde la instancia de CasaOS.

## Requisitos previos

1. Acceso a la interfaz web de ArgoCD
2. Los archivos de configuración de Immich ya están en el repositorio Git
3. El respaldo de la base de datos ya está creado en pibot.local

## Pasos para sincronizar Immich con ArgoCD

1. **Acceder a la interfaz de ArgoCD**:
   - Abre tu navegador web
   - Ingresa la URL de ArgoCD (normalmente https://argocd.yourdomain.com)
   - Inicia sesión con tus credenciales

2. **Sincronizar la aplicación principal**:
   - En la vista principal, localiza la aplicación "homelab" (o el nombre de tu aplicación principal)
   - Haz clic en "Sync" (Sincronizar)
   - Asegúrate de que la casilla "Prune" esté marcada para eliminar recursos obsoletos
   - Haz clic en "Synchronize" para iniciar la sincronización

3. **Verificar la sincronización**:
   - Espera a que se complete la sincronización
   - Verifica que aparezca el namespace "immich" y sus recursos asociados
   - Si hay errores, revisa los logs en la interfaz de ArgoCD para diagnosticar el problema

## Completar la migración de datos

Una vez que los recursos de Immich estén desplegados en el clúster, es necesario completar la migración de datos:

1. **Verificar el estado del job de migración**:
   - En la interfaz de ArgoCD, navega hasta el namespace "immich"
   - Localiza el job "immich-migration"
   - Verifica su estado y logs

2. **Obtener la clave pública SSH generada por el job**:
   - Accede a los logs del pod del job de migración
   - Copia la clave pública SSH que se muestra en los logs

3. **Autorizar la clave SSH en pibot.local**:
   - Conéctate a pibot.local: `ssh daniel@pibot.local`
   - Crea el directorio .ssh si no existe: `mkdir -p ~/.ssh`
   - Agrega la clave pública al archivo authorized_keys: `echo "CLAVE_PUBLICA" >> ~/.ssh/authorized_keys`
   - Ajusta los permisos: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`

4. **Monitorear el progreso de la migración**:
   - Vuelve a la interfaz de ArgoCD y sigue los logs del job
   - La migración se completará automáticamente una vez que se haya establecido la conexión SSH
   - Verifica los mensajes de progreso en los logs

5. **Verificar la integridad de los datos**:
   - Una vez completada la migración, accede a Immich a través de la URL configurada (https://immich.yourdomain.com)
   - Inicia sesión con tus credenciales habituales
   - Verifica que todas las imágenes y datos estén presentes

## Solución de problemas

Si encuentras problemas durante la migración:

1. **Problemas de conexión SSH**:
   - Verifica que la clave pública esté correctamente añadida en pibot.local
   - Comprueba los permisos de los archivos y directorios SSH
   - Asegúrate de que el servicio SSH esté funcionando en pibot.local

2. **Errores en la restauración de la base de datos**:
   - Verifica los logs del job de migración para identificar el error específico
   - Asegúrate de que el respaldo de la base de datos esté correctamente formateado
   - Si es necesario, realiza un nuevo respaldo de la base de datos

3. **Problemas de red**:
   - Comprueba que pibot.local esté accesible desde el clúster
   - Verifica que no haya reglas de firewall bloqueando la conexión SSH

## Conclusión

Una vez que la migración se haya completado correctamente, podrás acceder a tu instancia de Immich en el clúster Kubernetes. La configuración y los datos se habrán transferido correctamente desde la instancia de CasaOS en pibot.local.




