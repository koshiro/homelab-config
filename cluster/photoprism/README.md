# PhotoPrism en Kubernetes

Este directorio contiene la configuración necesaria para desplegar PhotoPrism en Kubernetes como alternativa a Immich.

## Descripción

PhotoPrism es una aplicación de gestión de fotos y vídeos de código abierto impulsada por IA. Proporciona funciones de organización automática, etiquetado, búsqueda y visualización de fotos y vídeos.

## Componentes

- **PhotoPrism**: La aplicación principal para la gestión de fotos.
- **MariaDB**: Base de datos para almacenar metadatos y configuración.
- **Volúmenes persistentes**: Para almacenar fotos originales, archivos importados y datos de la aplicación.

## Estructura de directorios

- `/photoprism/originals`: Directorio para almacenar las fotos originales.
- `/photoprism/import`: Directorio para importar nuevas fotos.
- `/photoprism/storage`: Directorio para almacenar datos de la aplicación, como miniaturas y cachés.

## Instalación

1. Crear los volúmenes persistentes y claims:
   ```bash
   kubectl apply -f namespace.yaml
   kubectl apply -f pv.yaml
   kubectl apply -f pvc.yaml
   ```

2. Crear el secreto con las contraseñas:
   ```bash
   kubectl apply -f secret.yaml
   ```

3. Desplegar PhotoPrism y MariaDB:
   ```bash
   kubectl apply -f deployment.yaml
   kubectl apply -f service.yaml
   kubectl apply -f ingress.yaml
   ```

4. Migrar las imágenes de Immich a PhotoPrism:
   ```bash
   kubectl apply -f migration-job.yaml
   ```

## Acceso

Una vez desplegado, PhotoPrism estará disponible en:
- https://photoprism.danielriquelme.cl

La autenticación se realiza a través de Authelia.

## Migración desde Immich

El job de migración copia las imágenes desde la instancia de Immich en CasaOS a PhotoPrism. El proceso es el siguiente:

1. Genera una clave SSH temporal.
2. Establece una conexión SSH con el servidor de Immich.
3. Copia las imágenes desde la ubicación de Immich a PhotoPrism.

## Configuración

PhotoPrism está configurado con las siguientes opciones:

- Autenticación con contraseña
- Idioma por defecto: Español
- Tema por defecto: Default
- Detección de NSFW desactivada
- WebDAV activado
- Backups activados
- TensorFlow activado

## Recursos

- [Documentación oficial de PhotoPrism](https://docs.photoprism.app/)
- [Repositorio de GitHub de PhotoPrism](https://github.com/photoprism/photoprism)
- [Imagen Docker de PhotoPrism](https://hub.docker.com/r/photoprism/photoprism)
