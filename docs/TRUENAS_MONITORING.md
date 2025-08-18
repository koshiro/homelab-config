# Monitoreo de TrueNAS con Prometheus y Grafana

Este documento describe cómo configurar el monitoreo de TrueNAS en el clúster de Kubernetes usando Prometheus y Grafana.

## 🎯 Objetivo

Configurar un sistema de monitoreo completo para TrueNAS que incluya:
- Métricas del sistema (CPU, memoria, disco, red)
- Dashboard de Grafana con visualizaciones en tiempo real
- Alertas configurables
- Integración con el stack de monitoreo existente

## 🏗️ Arquitectura

```
TrueNAS (192.168.1.20) ←→ node_exporter ←→ Prometheus ←→ Grafana
```

### Componentes

1. **node_exporter**: Exporta métricas del sistema operativo de TrueNAS
2. **Prometheus**: Recopila y almacena las métricas
3. **Grafana**: Visualiza las métricas en dashboards
4. **ServiceMonitor**: Configura el scraping automático de Prometheus

## 📁 Archivos de Configuración

### 1. Exporter de TrueNAS
- **Archivo**: `cluster/monitoring/truenas-node-exporter.yml`
- **Función**: Despliega node_exporter en el namespace de monitoring
- **Puerto**: 9100

### 2. Dashboard de Grafana
- **Archivo**: `cluster/monitoring/grafana-dashboard-truenas-simple.yml`
- **Función**: Define el dashboard "TrueNAS System Metrics"
- **Métricas**: CPU, memoria, disco, red

### 3. Credenciales
- **Archivo**: `cluster/monitoring/secret-truenas-credentials.sops.yml`
- **Función**: Almacena credenciales de acceso a TrueNAS
- **Contenido**: Usuario, contraseña y API key

## 🚀 Despliegue

### 1. Aplicar la configuración

```bash
# Desde el directorio raíz del proyecto
kubectl apply -k cluster/monitoring/
```

### 2. Verificar el despliegue

```bash
# Verificar que el exporter esté corriendo
kubectl get pods -n monitoring -l app=truenas-node-exporter

# Verificar el servicio
kubectl get service truenas-node-exporter -n monitoring

# Verificar el ServiceMonitor
kubectl get servicemonitor truenas-node-exporter-monitor -n monitoring
```

### 3. Verificar métricas

```bash
# Port-forward para acceder a las métricas
kubectl port-forward -n monitoring svc/truenas-node-exporter 9100:9100

# En otra terminal, verificar métricas
curl http://localhost:9100/metrics | grep node_cpu_seconds_total
```

## 📊 Dashboard de Grafana

### Acceso
- **URL**: https://grafana.danielriquelme.cl
- **Dashboard**: TrueNAS System Metrics
- **UID**: `truenas-system`

### Paneles Incluidos

1. **CPU Usage**: Uso de CPU en porcentaje
2. **Memory Usage**: Uso de memoria en porcentaje
3. **Root Disk Usage**: Uso del disco raíz en porcentaje
4. **Network Traffic**: Tráfico de red por interfaz

### Métricas Principales

- `node_cpu_seconds_total`: Tiempo de CPU por modo
- `node_memory_MemAvailable_bytes`: Memoria disponible
- `node_memory_MemTotal_bytes`: Memoria total
- `node_filesystem_avail_bytes`: Espacio disponible en disco
- `node_filesystem_size_bytes`: Tamaño total del disco
- `node_network_receive_bytes_total`: Bytes recibidos por interfaz
- `node_network_transmit_bytes_total`: Bytes transmitidos por interfaz

## 🔧 Configuración Avanzada

### Personalizar Métricas

Para agregar más métricas, edita el archivo `truenas-node-exporter.yml`:

```yaml
args:
  - --collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)
  - --collector.filesystem.ignored-fs-types=^(sys|proc|auto)fs$$
  # Agregar más collectors según sea necesario
```

### Alertas

El dashboard incluye alertas preconfiguradas:
- CPU > 80%
- Memoria > 80%
- Disco > 80%

Para personalizar alertas, edita el dashboard en Grafana o crea reglas de Prometheus.

## 🧪 Verificación

### Script de Verificación

```bash
# Ejecutar el script de verificación
./scripts/verify-truenas-monitoring.sh
```

### Verificaciones Manuales

1. **Estado del Pod**:
   ```bash
   kubectl get pods -n monitoring -l app=truenas-node-exporter
   ```

2. **Logs del Exporter**:
   ```bash
   kubectl logs -n monitoring -l app=truenas-node-exporter
   ```

3. **Métricas en Prometheus**:
   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   # Acceder a http://localhost:9090 y buscar "truenas-node-exporter"
   ```

4. **Dashboard en Grafana**:
   - Acceder a Grafana
   - Buscar dashboard "TrueNAS System Metrics"
   - Verificar que las métricas se muestren correctamente

## 🐛 Troubleshooting

### Problemas Comunes

#### 1. Pod no inicia
```bash
# Verificar logs
kubectl logs -n monitoring -l app=truenas-node-exporter

# Verificar eventos
kubectl describe pod -n monitoring -l app=truenas-node-exporter
```

#### 2. Métricas no aparecen en Prometheus
```bash
# Verificar ServiceMonitor
kubectl get servicemonitor truenas-node-exporter-monitor -n monitoring

# Verificar targets en Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Ir a Status > Targets
```

#### 3. Dashboard no muestra datos
```bash
# Verificar que el ConfigMap esté aplicado
kubectl get configmap truenas-dashboard-simple -n monitoring

# Verificar que Grafana esté scrapeando el ConfigMap
kubectl get configmap -n monitoring -l grafana_dashboard=1
```

### Logs Útiles

```bash
# Logs del exporter
kubectl logs -n monitoring -l app=truenas-node-exporter

# Logs de Prometheus
kubectl logs -n monitoring -l app=prometheus

# Logs de Grafana
kubectl logs -n monitoring -l app=grafana
```

## 📈 Escalabilidad

### Agregar Más Nodos TrueNAS

Para monitorear múltiples nodos TrueNAS:

1. Duplicar el deployment con diferentes nombres
2. Configurar diferentes ServiceMonitors
3. Actualizar el dashboard para mostrar métricas de todos los nodos

### Métricas Personalizadas

Para métricas específicas de TrueNAS (pools ZFS, servicios, etc.):

1. Crear un exporter personalizado
2. Usar la API de TrueNAS para obtener métricas específicas
3. Integrar con el dashboard existente

## 🔒 Seguridad

### Credenciales

- Las credenciales se almacenan en secretos de Kubernetes
- Usar SOPS para encriptar credenciales sensibles
- Rotar credenciales regularmente

### Acceso a Métricas

- Las métricas solo son accesibles desde dentro del clúster
- Usar NetworkPolicies para restringir acceso si es necesario
- Considerar autenticación para endpoints de métricas

## 📚 Referencias

- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)
- [Grafana Dashboard JSON](https://grafana.com/docs/grafana/latest/dashboards/json-model/)
- [Kubernetes ServiceMonitor](https://prometheus-operator.dev/docs/kubernetes/operator/api/#servicemonitor)
- [TrueNAS API Documentation](https://www.truenas.com/docs/api/)

## 🤝 Contribuciones

Para mejorar el monitoreo de TrueNAS:

1. Fork del repositorio
2. Crear rama para feature
3. Implementar cambios
4. Crear Pull Request con descripción detallada

## 📞 Soporte

Si encuentras problemas:

1. Revisar la documentación
2. Ejecutar el script de verificación
3. Revisar logs y eventos
4. Crear issue en el repositorio con detalles del problema
