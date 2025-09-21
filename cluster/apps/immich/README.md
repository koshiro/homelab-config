# Immich - Self-hosted Photo and Video Backup

Immich es una aplicación de respaldo de fotos y videos auto-hospedada que proporciona una experiencia similar a Google Photos.

## Configuración

### Variables de Entorno

Las variables de entorno están configuradas en `03-configmap.yaml` y se aplican a través del deployment.

### Base de Datos

Immich utiliza PostgreSQL con la extensión `pgvector` para funcionalidades de IA.

### Redis

Redis se utiliza para el cache y la gestión de colas de trabajos.

### Machine Learning

El servicio de machine learning se ejecuta en un pod separado para procesar las imágenes.

## Despliegue

```bash
# Aplicar la configuración
kubectl apply -f cluster/apps/immich/

# Verificar el estado
kubectl get pods -n immich
kubectl get svc -n immich
kubectl get ingress -n immich
```

## Acceso

- **URL**: https://immich.danielriquelme.cl
- **API**: https://immich.danielriquelme.cl/api

## Troubleshooting

### Verificar logs
```bash
kubectl logs -n immich deployment/immich-server
kubectl logs -n immich deployment/immich-machine-learning
```

### Verificar conectividad a la base de datos
```bash
kubectl run postgres-test --image=postgres:15 --rm -it --restart=Never --env="PGPASSWORD=OC3A3kD7Q0yaTogfuWpIpsvUFwZ1DLgQHFLoAFAOu9mij9Sb33XeauMKuCl6Xbcw" -- psql -h homelab-postgres-rw.postgresql.svc.cluster.local -U immich -d immich -c "SELECT version();"
```

## Archivos de Configuración

- `00-deployment.yaml`: Deployment principal de Immich
- `01-secret.yaml`: Secretos de la base de datos
- `02-ingress.yaml`: Configuración de Ingress para acceso externo
- `03-configmap.yaml`: Variables de entorno y configuración
- `values.yaml`: Valores de configuración (referencia)
