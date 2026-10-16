#!/usr/bin/env bash
# Valida y compara cluster/flux con flate (renderiza como Flux, sin cluster: kustomize, components, Helm).
# flate salta las Kustomizations suspendidas, así que trabaja sobre una copia temporal sin los `suspend: true`:
# valida lo que Flux aplicaría al quitarlos (fase 4 de docs/PLAN-FLUX.md) sin tocar el checkout.
#   scripts/flux/flate.sh test          las Kustomizations de cluster/flux, el HelmRelease de cnpg y su fuente
#   scripts/flux/flate.sh diff [ref]    lo que cambia contra ref (origin/main por defecto), en formato GitHub
# FLATE=/ruta/flate si no está en el PATH ni en ~/.cache/flux-plan/bin. Lo corre el CI (validar.yml).
set -euo pipefail

raiz="$(cd "$(dirname "$0")/../.." && pwd)"
flate="${FLATE:-$(command -v flate || echo "$HOME/.cache/flux-plan/bin/flate")}"
export FLATE_KUBE_VERSION="${FLATE_KUBE_VERSION:-1.35.9}"  # la de prod (hechos.md); subirla junto con k3s
export FLATE_NO_PROGRESS=1
unset FLATE_BASE  # la action de flate lo exporta y pasaría el test a «solo lo cambiado»
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# copia <destino> [ref]: cluster/ del árbol de trabajo (o de ref) sin suspend, dentro de un repo git vacío
# (flate resuelve los ./cluster/... desde la raíz del repo). Sin cluster/flux en ref devuelve 1.
copia() {
  local dst="$1" ref="${2:-}"
  mkdir -p "$dst"
  if [[ -z "$ref" ]]; then
    cp -R "$raiz/cluster" "$dst/"
  else
    git -C "$raiz" archive "$ref" cluster | tar -x -C "$dst"
  fi
  [[ -d "$dst/cluster/flux" ]] || return 1
  git init -q "$dst"
  find "$dst/cluster/flux" -name '*.yaml' -exec sed -i.orig '/^  suspend: true$/d' {} +
  find "$dst/cluster/flux" -name '*.orig' -delete
}

case "${1:-}" in
  test)
    copia "$tmp/pr"
    "$flate" test all --path "$tmp/pr/cluster/flux"
    ;;
  diff)
    ref="${2:-origin/main}"
    copia "$tmp/pr"
    if ! copia "$tmp/base" "$ref"; then
      echo "$ref no tiene cluster/flux: nada que comparar."
      exit 0
    fi
    "$flate" diff all -o github --path "$tmp/pr/cluster/flux" --path-orig "$tmp/base/cluster/flux"
    ;;
  *)
    sed -n '2,7p' "$0"
    exit 2
    ;;
esac
