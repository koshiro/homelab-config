#!/usr/bin/env bash
# Renderiza cada kustomization de cluster/ y valida el resultado con kubeconform -strict, con los schemas de los CRD
# del catálogo de datree. También valida los manifiestos de Flux que todavía no entran en una kustomization.
# Uso: scripts/flux/validar.sh   (KUBECONFORM=/ruta/kubeconform si no está en el PATH). Lo corre el CI en cada PR.
set -euo pipefail

raiz="$(cd "$(dirname "$0")/../.." && pwd)"
kc="${KUBECONFORM:-kubeconform}"
k8s="${K8S_VERSION:-1.35.0}"
catalogo='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
if command -v kustomize >/dev/null; then render=(kustomize build); else render=(kubectl kustomize); fi

# Los CRD vienen de manifiestos upstream (cert-manager, Barman Cloud) y no hay schema para validarlos.
kc_args=(-strict -summary -output text -kubernetes-version "$k8s" -skip CustomResourceDefinition
         -schema-location default -schema-location "$catalogo")
fallas=0

while IFS= read -r k; do
  dir="$(dirname "$k")"
  rel="${dir#"$raiz"/}"
  [[ "$rel" == cluster/components/* ]] && continue
  # Los Component solo-flux/ no se construyen solos (y usan ../, que kubectl kustomize no acepta): sus SOPS los
  # revisa revisar_sops.py y el HelmRelease de cnpg se valida abajo.
  grep -q '^kind: Component' "$k" && continue
  if ! salida="$("${render[@]}" "$dir" 2>&1)"; then
    echo "FALLA render $rel: ${salida##*$'\n'}"
    fallas=$((fallas + 1))
    continue
  fi
  if ! res="$(printf '%s\n' "$salida" | "$kc" "${kc_args[@]}" - 2>&1)"; then
    echo "FALLA $rel"
    printf '%s\n' "$res" | grep -v '^Summary' | sed 's/^/    /'
    fallas=$((fallas + 1))
  else
    echo "ok    $rel: ${res##*$'\n'}"
  fi
done < <(find "$raiz/cluster" -name 'kustomization.y*ml' | sort)

# Manifiestos que solo aplica Flux (Component solo-flux/) y que no son secretos.
for f in "$raiz"/cluster/00-infrastructure/cnpg/helmrelease.yaml; do
  [[ -f "$f" ]] || continue
  if ! res="$("$kc" "${kc_args[@]}" "$f" 2>&1)"; then
    echo "FALLA ${f#"$raiz"/}"; printf '%s\n' "$res" | sed 's/^/    /'; fallas=$((fallas + 1))
  else
    echo "ok    ${f#"$raiz"/}: ${res##*$'\n'}"
  fi
done

echo "carpetas con fallas: $fallas"
[[ "$fallas" -eq 0 ]]
