#!/bin/bash
# Kit de recuperación: las dos raíces de confianza del homelab, que sin copia solo existen en este Mac.
#   - clave age de SOPS (~/.config/sops/age/keys.txt): descifra todos los *.sops.* del repo y su historial
#   - contraseña del vault de Ansible (~/.config/homelab/ansible-vault-pass): abre ansible/vars/vault.yml, que guarda
#     el token de Cloudflare y la contraseña del respaldo restic en R2
# Copia A: dos entradas en Contraseñas de Apple (llavero de iCloud, cifrado de extremo a extremo).
# Copia B: un tar cifrado con `age -p` en r2://homelab-recuperacion/homelab-kit.age (fuera del bucket de restic).
#
# Uso (en una terminal propia: age pide la frase por teclado):
#   scripts/kit-recuperacion.sh notas                     copia cada raíz al portapapeles para pegarla en Contraseñas
#   scripts/kit-recuperacion.sh cifrar                    empaqueta, cifra con tu frase y sube a R2
#   scripts/kit-recuperacion.sh verificar-notas           pega las dos notas y prueba en una carpeta vacía
#   scripts/kit-recuperacion.sh verificar-archivo [kit]   baja el kit de R2 (o usa [kit]), lo descifra y prueba
#   scripts/kit-recuperacion.sh restaurar <kit|notas>     Mac nuevo: deja las raíces en ~/.config (no sobrescribe)
# «Probar» = en una carpeta vacía, con HOME apuntando a ella y sin variables heredadas, `sops -d` de un secreto del
# repo y `ansible-vault view` del vault usando solo esa copia.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
AGE_KEY="$HOME/.config/sops/age/keys.txt"
VAULT_PASS="$HOME/.config/homelab/ansible-vault-pass"
VAULT="$REPO/ansible/vars/vault.yml"
HL="$REPO/.claude/skills/homelab/hl.py"
BUCKET=homelab-recuperacion
OBJETO=homelab-kit.age
NOTA_AGE="homelab · clave age (SOPS)"
NOTA_VAULT="homelab · contraseña vault Ansible"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

probar() {  # $1 = carpeta con keys.txt y ansible-vault-pass
  local d=$1 secreto fallo=0
  secreto=$(cd "$REPO" && git ls-files '*.sops.yml' '*.sops.yaml' | head -1)
  if (cd "$d" && env -i PATH="$PATH" HOME="$d" SOPS_AGE_KEY_FILE="$d/keys.txt" sops -d "$REPO/$secreto" >/dev/null); then
    echo "sops -d: OK ($secreto)"
  else
    echo "sops -d: FALLA"; fallo=1
  fi
  if (cd "$d" && env -i PATH="$PATH" HOME="$d" ansible-vault view "$VAULT" --vault-password-file "$d/ansible-vault-pass" >/dev/null); then
    echo "ansible-vault view: OK"
  else
    echo "ansible-vault view: FALLA"; fallo=1
  fi
  return $fallo
}

desde_portapapeles() {  # deja en $1 las dos notas, pegadas desde Contraseñas
  read -r -p "Copia el contenido de «$NOTA_AGE» y presiona Enter… "
  pbpaste > "$1/keys.txt"
  read -r -p "Copia el contenido de «$NOTA_VAULT» y presiona Enter… "
  pbpaste > "$1/ansible-vault-pass"
  printf '' | pbcopy
  chmod 600 "$1/keys.txt" "$1/ansible-vault-pass"
  grep -q '^AGE-SECRET-KEY-' "$1/keys.txt" || { echo "la primera nota no trae una línea AGE-SECRET-KEY-"; exit 1; }
}

desde_kit() {  # descifra el kit $1 (pide la frase) y deja las raíces en $2
  age -d -o "$TMP/kit.tgz" "$1"
  tar -C "$TMP" -xzf "$TMP/kit.tgz"
  cp -p "$TMP/kit/keys.txt" "$TMP/kit/ansible-vault-pass" "$2/"
}

case "${1:-}" in
  notas)
    pbcopy < "$AGE_KEY"
    echo "1/2 Clave age copiada. En Contraseñas: + (nueva), título «$NOTA_AGE», pégala en Notas y guarda."
    read -r -p "Enter para seguir… "
    pbcopy < "$VAULT_PASS"
    echo "2/2 Contraseña del vault copiada. Nueva entrada «$NOTA_VAULT», pégala en Notas y guarda."
    read -r -p "Enter para limpiar el portapapeles… "
    printf '' | pbcopy
    echo "Listo. Comprueba con: $0 verificar-notas"
    ;;
  cifrar)
    mkdir "$TMP/kit"
    cp "$AGE_KEY" "$TMP/kit/keys.txt"
    cp "$VAULT_PASS" "$TMP/kit/ansible-vault-pass"
    cat > "$TMP/kit/LEEME.txt" <<EOF
Kit de recuperación del homelab (creado $(date +%F)).
keys.txt            -> ~/.config/sops/age/keys.txt (chmod 600). Clave pública: $(grep -o 'age1[0-9a-z]*' "$AGE_KEY" | head -1)
ansible-vault-pass  -> ~/.config/homelab/ansible-vault-pass (chmod 600)
Con el repo clonado: scripts/kit-recuperacion.sh restaurar <este .age>. Procedimiento: README.md § Operación.
EOF
    tar -C "$TMP" -czf "$TMP/kit.tgz" kit
    echo "Elige una frase que recuerdes y anótala en papel (age la pide dos veces; vacía = age genera una)."
    age -p -o "$TMP/$OBJETO" "$TMP/kit.tgz"
    python3 -I "$HL" r2 put "$BUCKET" "$TMP/$OBJETO" "$OBJETO" --apply
    echo "Comprueba con: $0 verificar-archivo"
    ;;
  verificar-notas)
    mkdir "$TMP/copia"
    desde_portapapeles "$TMP/copia"
    probar "$TMP/copia"
    ;;
  verificar-archivo)
    kit=${2:-}
    if [ -z "$kit" ]; then
      kit="$TMP/$OBJETO"
      python3 -I "$HL" r2 get "$BUCKET" "$OBJETO" "$kit"
    fi
    mkdir "$TMP/copia"
    desde_kit "$kit" "$TMP/copia"
    probar "$TMP/copia"
    ;;
  restaurar)
    origen=${2:?indica el kit .age o «notas»}
    if [ -e "$AGE_KEY" ] || [ -e "$VAULT_PASS" ]; then
      echo "ya existen $AGE_KEY o $VAULT_PASS; no se sobrescriben"; exit 1
    fi
    mkdir "$TMP/copia"
    if [ "$origen" = notas ]; then desde_portapapeles "$TMP/copia"; else desde_kit "$origen" "$TMP/copia"; fi
    probar "$TMP/copia"
    mkdir -p "$(dirname "$AGE_KEY")" "$(dirname "$VAULT_PASS")"
    install -m 600 "$TMP/copia/keys.txt" "$AGE_KEY"
    install -m 600 "$TMP/copia/ansible-vault-pass" "$VAULT_PASS"
    echo "Restaurado en $AGE_KEY y $VAULT_PASS"
    ;;
  *)
    sed -n '2,17p' "$0"; exit 1 ;;
esac
