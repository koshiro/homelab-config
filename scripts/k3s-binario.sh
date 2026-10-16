#!/bin/sh
# Sube k3s reemplazando solo el binario (método manual de la documentación de k3s). No usa get.k3s.io porque este
# reescribe las unidades systemd y la de pibot lleva flags propios (--write-kubeconfig-mode, --node-ip).
# Uso (como root): k3s-binario.sh <versión> descargar|instalar
#   descargar: guarda el binario actual y baja <versión> verificada con sha256 a /var/lib/rancher/k3s-binarios
#   instalar:  reemplaza /usr/local/bin/k3s por <versión> y reinicia k3s (server) o k3s-agent
# Desde el Mac, por nodo y en orden (pibot, luego cada worker con drain/uncordon):
#   ansible k3s_nodes -i ansible/inventory -b -m script -a 'scripts/k3s-binario.sh v1.35.9+k3s1 descargar'
#   ansible pibot -i ansible/inventory -b -m script -a 'scripts/k3s-binario.sh v1.35.9+k3s1 instalar'
# Volver atrás en un nodo: instalar con la versión anterior (queda en /var/lib/rancher/k3s-binarios). El server no
# baja de menor si etcd ya migró: para eso, restaurar el snapshot pre-k3s-<menor> con el binario viejo.
set -eu
V="$1"
ACCION="$2"
case "$(uname -m)" in
  x86_64) SUF=""; ARCH=amd64 ;;
  aarch64) SUF="-arm64"; ARCH=arm64 ;;
  *) echo "arquitectura no soportada: $(uname -m)"; exit 1 ;;
esac
DIR=/var/lib/rancher/k3s-binarios
mkdir -p "$DIR"
F="$DIR/k3s-$V"
URL="https://github.com/k3s-io/k3s/releases/download/$(printf %s "$V" | sed 's/+/%2B/')"

if [ "$ACCION" = descargar ]; then
  ACTUAL=$(/usr/local/bin/k3s --version | awk 'NR==1{print $3}')
  [ -f "$DIR/k3s-$ACTUAL" ] || cp -p /usr/local/bin/k3s "$DIR/k3s-$ACTUAL"
  curl -fsSL -o "$F.tmp" "$URL/k3s$SUF"
  curl -fsSL -o "$F.sha" "$URL/sha256sum-$ARCH.txt"
  ESPERADO=$(awk -v n="k3s$SUF" '$2==n{print $1}' "$F.sha")
  REAL=$(sha256sum "$F.tmp" | awk '{print $1}')
  rm -f "$F.sha"
  if [ -z "$ESPERADO" ] || [ "$ESPERADO" != "$REAL" ]; then
    rm -f "$F.tmp"
    echo "sha256 no coincide (esperado=$ESPERADO real=$REAL)"
    exit 1
  fi
  chmod 755 "$F.tmp"
  mv "$F.tmp" "$F"
  echo "ok $(hostname) $("$F" --version | head -1) sha256=$REAL respaldo=$DIR/k3s-$ACTUAL"
elif [ "$ACCION" = instalar ]; then
  [ -x "$F" ] || { echo "falta $F: correr descargar primero"; exit 1; }
  install -m 755 "$F" /usr/local/bin/k3s.new
  mv /usr/local/bin/k3s.new /usr/local/bin/k3s
  if systemctl is-active --quiet k3s; then
    systemctl restart k3s
  else
    systemctl restart k3s-agent
  fi
  echo "ok $(hostname) $(/usr/local/bin/k3s --version | head -1)"
else
  echo "acción desconocida: $ACCION"
  exit 1
fi
