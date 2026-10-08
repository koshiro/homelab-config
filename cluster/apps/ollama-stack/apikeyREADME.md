# Ollama stack — acceso y API keys

Referencia rápida para conectar clientes (editores con API OpenAI-compatible, scripts) y usar Open WebUI.

## Qué hay desplegado

| Componente | Rol | Manifesto |
|------------|-----|-----------|
| **Ollama** | API de modelos (headless) | `deployment-ollama.yml` |
| **Open WebUI** | Interfaz web de chat y administración | `deployment-webui.yml`, `ingress.yml` |

Ollama **no** tiene panel web propio. La “configuración” de modelos se hace con `ollama pull` / `kubectl exec`, o desde Open WebUI (Settings → Models).

## Formas de acceso

### 1. NodePort + Tailscale (recomendado para API Ollama)

Patrón homelab: `NodePort` en todos los nodos + MagicDNS del tailnet (`k3s-node-0`, etc.). No hay operador Tailscale ni sidecar en el pod.

| Servicio | NodePort | Puerto contenedor | Uso |
|----------|----------|-------------------|-----|
| **Ollama API** | `31434` | `11434` | Inferencia, `/api/*`, `/v1/*` |
| **Open WebUI** | `30080` | `8080` | UI web |

Desde un dispositivo en el tailnet:

```bash
# Comprobar Ollama
curl -sS "http://k3s-node-0:31434/api/tags" | jq

# Open WebUI en el navegador
open "http://k3s-node-0:30080"
```

Si no usas MagicDNS, sustituye `k3s-node-0` por la IP Tailscale del nodo (`100.x.y.z`).

Dentro del clúster: `http://ollama.ollama-stack.svc.cluster.local:11434`.

### 2. Ingress (solo Open WebUI, no la API Ollama)

- **Host:** `http://chat.danielriquelme.cl`
- **Backend:** Service `open-webui:8080` vía Traefik (`ingressClassName: traefik`)
- **Ollama no tiene Ingress** — la API solo se expone por NodePort (o DNS interno del clúster).

### 3. Tailscale Serve

No está configurado en GitOps para este stack (a diferencia de ComfyUI, donde se documenta `tailscale serve` manual). El acceso remoto previsto es **NodePort + tailnet**, no Serve.

### 4. LAN directa

Open WebUI tiene `WEBUI_URL=http://192.168.1.15:30080` en el deployment (IP LAN del nodo). Útil en la red local sin Tailscale.

## API keys y autenticación

### Ollama (API nativa y `/v1`)

En el deployment **no** hay `OLLAMA_API_KEY`. La instancia es de confianza en red privada (tailnet/LAN); Ollama acepta peticiones sin validar la key.

| Cliente | Base URL | API Key |
|---------|----------|---------|
| **Editor o cliente OpenAI-compatible** | `http://k3s-node-0:31434/v1` | Cualquier placeholder, p. ej. `ollama` |
| **curl / scripts** | `http://k3s-node-0:31434` | No requerida |

Ejemplo de cliente OpenAI-compatible:

- **Override OpenAI Base URL:** `http://k3s-node-0:31434/v1`
- **API Key:** `ollama`
- **Modelo:** nombre exacto de `ollama list` en el pod (p. ej. `qwen2.5-coder:7b`)

### Open WebUI

- **Login web:** cuenta creada en el primer acceso a la UI (Settings → Account).
- **API key de Open WebUI** (para llamar a la UI como API, no a Ollama directo): Settings → **Account** → **API Keys** → generar una key.
- Open WebUI habla con Ollama por DNS interno (`OLLAMA_BASE_URL=http://ollama.ollama-stack.svc.cluster.local:11434`); no necesitas key de Ollama para eso.

### Endurecer con `OLLAMA_API_KEY` (opcional, no aplicado)

Si en el futuro quieres exigir Bearer token en Ollama:

1. Añadir en `deployment-ollama.yml`: `OLLAMA_API_KEY` (idealmente desde Secret SOPS).
2. Los clientes deben enviar `Authorization: Bearer <misma-key>`.
3. Open WebUI: configurar la misma key en su conexión a Ollama si la versión lo soporta en env.

Hoy el homelab **no** exige esto; el tráfico va solo por tailnet/LAN.

## Operaciones habituales

```bash
# Modelos en el pod
kubectl exec -n ollama-stack deploy/ollama -- ollama list
kubectl exec -n ollama-stack deploy/ollama -- ollama pull llama3.2

# Estado del stack
kubectl get pods,svc -n ollama-stack
```

## Resumen

| ¿Qué quieres? | Cómo acceder |
|---------------|--------------|
| API Ollama desde el Mac (editores, scripts) | Tailscale → `http://k3s-node-0:31434` o `.../v1` |
| UI de chat / admin Open WebUI | Tailscale → `:30080`, LAN → `192.168.1.15:30080`, o `chat.danielriquelme.cl` |
| Configurar modelos en Ollama | `kubectl exec ... ollama pull` o Open WebUI |
| API key Ollama | Placeholder (`ollama` / `ollama-local`); servidor sin auth hoy |
| API key Open WebUI | Generar en la UI (Account → API Keys) |

Manifiestos en esta carpeta (`deployment-ollama.yml`, `deployment-webui.yml`); acceso y almacenamiento en la tabla *Servicios* del README raíz.
