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
kubectl apply -k cluster/apps/immich/
# El secreto va aparte: python3 -I .claude/skills/homelab/hl.py sops apply cluster/apps/immich/01-secret.sops.yaml

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
# La contraseña se lee del secret homelab-postgres-app (nunca escribirla aquí)
DBPASS=$(kubectl -n immich get secret homelab-postgres-app -o go-template --template '{{.data.password | base64decode}}')
kubectl run postgres-test --image=postgres:15 --rm -it --restart=Never --env=PGPASSWORD=$DBPASS -- \
  psql -h homelab-postgres-rw.postgresql.svc.cluster.local -U immich -d immich -c 'SELECT version();'
```

## Archivos de Configuración

- `00-deployment.yaml`: Deployment principal de Immich
- `01-secret.sops.yaml`: Secretos de la base de datos (SOPS)
- `02-ingress.yaml`: Configuración de Ingress para acceso externo
- `03-configmap.yaml`: Variables de entorno y configuración
