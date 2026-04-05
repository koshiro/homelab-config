# Re-análisis: deployment Minecraft y path NFS

**Actualización:** El repo se alineó al path que usa el cluster en vivo: **`/mnt/homelab-storage/minecraft-server`**. Deployment, scripts y documentación apuntan a ese path.

---

## Contexto

El servidor Minecraft está **funcionando** en el cluster con un mundo avanzado y respaldos en TrueNAS. En un cambio anterior se modificó el deployment para usar el path NFS `/mnt/homelab-storage/minecraft` (en lugar de `minecraft-server`), basándose en que la API `filesystem/listdir` mostró datos en `minecraft` y vacío en `minecraft-server`.  

Si el deployment en el cluster **ya estaba funcionando** antes de ese cambio, es importante aclarar qué path está usando realmente el cluster en vivo y no asumir que el cambio fue correcto sin verificación.

## Qué verificar en el cluster en vivo

Para saber **qué path NFS está usando ahora mismo** el pod de Minecraft:

```bash
kubectl get deployment minecraft -n minecraft -o yaml | grep -A5 "nfs:"
```

O el volumen completo:

```bash
kubectl get deployment minecraft -n minecraft -o jsonpath='{.spec.template.spec.volumes[*]}' | jq
```

- Si ves `path: /mnt/homelab-storage/minecraft` → el cluster ya está alineado con este repo (deployment apunta a `minecraft`).
- Si ves `path: /mnt/homelab-storage/minecraft-server` → el cluster en vivo sigue usando `minecraft-server`; en ese caso el “mundo avanzado” está en **minecraft-server** y no se debe cambiar el deployment a `minecraft` sin migrar/copiar datos o confirmar que ambos paths son el mismo dataset.

## Estado de este repositorio

En este repo el deployment está definido así:

- **Volumen NFS:** `server: 192.168.1.20`, `path: /mnt/homelab-storage/minecraft`
- **Documentación y scripts:** `DATA-SAFETY.md`, `fix-nfs-and-mount.sh`, `mount-nfs.sh` y `deployment.yml` referencian `/mnt/homelab-storage/minecraft`.

Es decir: la **fuente de verdad en git** es el path `minecraft`, no `minecraft-server`.

## Posibles escenarios

1. **Cluster ya actualizado**  
   Si ya aplicaste el cambio (kubectl apply del deployment de este repo), el cluster usa `minecraft` y el mundo avanzado está en ese dataset. No hace falta revertir nada; solo mantener respaldos (snapshots TrueNAS) de `homelab-storage/minecraft`.

2. **Cluster sigue con minecraft-server**  
   Si el deployment en el cluster sigue usando `minecraft-server`, entonces el mundo avanzado está en ese dataset. En ese caso:
   - **No** cambiar el deployment a `minecraft` sin antes:
     - Hacer snapshot/respaldo de `homelab-storage/minecraft-server`, y
     - O migrar datos de `minecraft-server` a `minecraft` y luego cambiar el deployment.
   - Opción segura: dejar el deployment apuntando a `minecraft-server` y actualizar este repo para que coincida (path y docs) con lo que está en vivo.

3. **Mismo dataset, dos nombres**  
   Si en TrueNAS `minecraft` y `minecraft-server` son el mismo dataset o uno es un enlace, entonces da igual cuál path uses; aun así conviene que repo y cluster usen el mismo path para evitar confusiones.

## Respaldo antes de cualquier cambio

- Script de snapshot (vía API TrueNAS): `./backup-snapshot-truenas.sh`  
  Crea snapshots de `homelab-storage/minecraft` y `homelab-storage/minecraft-server` (si existen). Si la API devuelve error, crear el snapshot manualmente en TrueNAS: **Storage → Snapshots → Add**.
- Los snapshots automáticos de TrueNAS para esos datasets también cuentan como respaldo; comprueba que estén configurados y que se ejecuten.

## Conclusión

- **Primero:** ejecutar el respaldo (script o snapshot manual en TrueNAS).
- **Segundo:** comprobar en el cluster el path NFS real con los comandos de arriba.
- **Tercero:** alinear este repo con la realidad del cluster (mismo path en `deployment.yml`, DATA-SAFETY, scripts y docs) y no cambiar el path en el deployment sin respaldo y sin saber dónde están realmente los datos del mundo avanzado.
