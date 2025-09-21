# Changelog - Homelab Configuration

## [2025-08-31] - Cluster Completamente Funcional

### 🔧 Fixes Críticos
- **DNS Search Domain Conflict**: Resuelto conflicto causado por Tailscale que interceptaba consultas DNS internas
- **qBittorrent P2P**: Configurado hostPort 6881 en k3s-node-1 para conectividad P2P directa
- **Comunicación Inter-Servicios**: Todos los servicios ARR pueden comunicarse correctamente

### 🚀 Mejoras
- **CoreDNS**: Configuración específica para separar DNS interno/externo
- **Node Labeling**: k3s-node-1 etiquetado como `p2p=true` para qBittorrent
- **Cloudflare Tunnel**: Configurado para usar `traefik.kube-system.svc.cluster.local:80`

### 📚 Documentación
- **CLUSTER_STATUS_CURRENT.md**: Estado completo del cluster
- **DNS_SEARCH_DOMAIN_SOLUTION.md**: Documentación detallada de la solución DNS
- **README.md**: Actualizado estado a "Completamente Funcional"
- **kustomization.yml**: Comentarios actualizados con estado actual

### 🗑️ Limpieza
- **service-peer.yml**: Eliminado (se usa hostPort directamente)
- **Archivos temporales**: Eliminados archivos de configuración temporal

### 🔍 Configuración Final
```yaml
# Servicios Funcionando
- Plex: ✅ https://plex.danielriquelme.cl
- Sonarr: ✅ https://sonarr.danielriquelme.cl  
- Radarr: ✅ https://radarr.danielriquelme.cl
- qBittorrent: ✅ https://qbittorrent.danielriquelme.cl (P2P funcional)
- Prowlarr: ✅ https://prowlarr.danielriquelme.cl
- Overseerr: ✅ https://overseerr.danielriquelme.cl

# Networking
- Router: Puerto 6881 → 192.168.1.131:6881 (qBittorrent P2P)
- Cloudflare: *.danielriquelme.cl → traefik.kube-system.svc.cluster.local:80
- DNS: CoreDNS configurado sin conflictos de search domain
```

### 🎯 Resultado
**Cluster completamente funcional con todos los servicios comunicándose correctamente y accesibles desde internet.**


