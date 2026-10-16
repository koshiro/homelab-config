#!/bin/bash
# Arranque del contenedor claude del pod claude-remote. Idempotente: las herramientas quedan en ~/.local del NFS y
# solo se descargan si falta la versión fijada; los paquetes apt se reinstalan en cada arranque (capa efímera).
# Orden: paquetes → secretos → herramientas → esperar la sincronización de ~/.claude → repos → login → Remote Control.
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/node/bin:$PATH"
log() { echo "[bootstrap $(date '+%F %T')] $*"; }
trap 'log "SIGTERM: cerrando tmux"; tmux kill-server 2>/dev/null; exit 0' TERM INT

REPOS="homelab-config:homelab-config SAC:SAC cyano:cyanotype_curves_calculator"   # carpeta:repo de github.com/koshiro
KUBECTL_VER=v1.35.9      # = versión del servidor k3s
SOPS_VER=3.12.2
GH_VER=2.102.0
NODE_VER=v22.20.0
MARKS="$HOME/.local/share/bootstrap"

# 1. Paquetes del sistema
sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  tmux jq rsync ripgrep xz-utils python3-venv dnsutils iputils-ping >/dev/null || log "AVISO: apt falló"
# OpenSSH toma el home de /etc/passwd (/home/vscode), no de $HOME: sin esto ignora ~/.ssh/config.
sudo usermod -d "$HOME" vscode

# 2. Secretos y configuración (se reescriben en cada arranque desde el Secret y el ConfigMap)
mkdir -p ~/.local/bin "$MARKS" ~/git ~/.ssh ~/.config/sops/age ~/.config/homelab
chmod 700 ~/.ssh
install -m 600 /secrets/age-key ~/.config/sops/age/keys.txt
install -m 600 /secrets/ansible-vault-pass ~/.config/homelab/ansible-vault-pass
install -m 600 /secrets/ssh-key ~/.ssh/id_rsa
install -m 644 /secrets/ssh-key.pub ~/.ssh/id_rsa.pub
install -m 600 /files/ssh_config ~/.ssh/config

# 3. Herramientas fijadas (marca por versión en $MARKS)
fetch() {  # nombre versión comando...
  local name=$1 ver=$2; shift 2
  [ -f "$MARKS/$name-$ver" ] && return 0
  log "instalando $name $ver"
  if bash -c "$*"; then rm -f "$MARKS/$name-"*; touch "$MARKS/$name-$ver"; else log "AVISO: falló $name"; fi
}
fetch kubectl $KUBECTL_VER "curl -fsSLo ~/.local/bin/kubectl https://dl.k8s.io/release/$KUBECTL_VER/bin/linux/amd64/kubectl && chmod +x ~/.local/bin/kubectl"
fetch sops $SOPS_VER "curl -fsSLo ~/.local/bin/sops https://github.com/getsops/sops/releases/download/v$SOPS_VER/sops-v$SOPS_VER.linux.amd64 && chmod +x ~/.local/bin/sops"
fetch gh $GH_VER "curl -fsSL https://github.com/cli/cli/releases/download/v$GH_VER/gh_${GH_VER}_linux_amd64.tar.gz | tar -xz -C /tmp && mv /tmp/gh_${GH_VER}_linux_amd64/bin/gh ~/.local/bin/"
fetch node $NODE_VER "rm -rf ~/.local/node && mkdir -p ~/.local/node && curl -fsSL https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-linux-x64.tar.xz | tar -xJ -C ~/.local/node --strip-components=1"
fetch uv 1 "curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=\$HOME/.local/bin INSTALLER_NO_MODIFY_PATH=1 sh"
fetch ansible 1 "uv tool install --with-executables-from ansible-core ansible"
# Claude Code se actualiza solo; solo se instala si falta.
command -v claude >/dev/null || fetch claude 1 "curl -fsSL https://claude.ai/install.sh | bash"

# 4. git: HTTPS con GH_TOKEN (Secret) como credencial
git config --global user.name "Daniel Riquelme"
git config --global user.email "contacto@danielriquelme.cl"
git config --global init.defaultBranch main
git config --global pull.ff only
gh auth setup-git

# 5. Esperar la primera sincronización de ~/.claude desde el Mac antes de que Claude Code escriba ahí: si creara su
#    settings.json primero, Syncthing podría preferirlo al del Mac.
until [ -f ~/.claude/CLAUDE.md ]; do log "esperando la sincronización de ~/.claude desde el Mac (Syncthing)"; sleep 30 & wait $!; done

# 6. Repos (solo lo versionado: clone de GitHub)
for pair in $REPOS; do
  dir=${pair%%:*} repo=${pair#*:}
  [ -d ~/git/$dir/.git ] || { log "clonando $repo"; git clone -q "https://github.com/koshiro/$repo.git" ~/git/$dir; }
done

# 7. Plugins declarados en el settings.json sincronizado
for m in $(jq -r '.extraKnownMarketplaces // {} | to_entries[] | .value.source.repo // empty' ~/.claude/settings.json); do
  claude plugin marketplace add "$m" >/dev/null 2>&1 || true
done
for p in $(jq -r '.enabledPlugins // {} | to_entries[] | select(.value) | .key' ~/.claude/settings.json); do
  claude plugin install "$p" >/dev/null 2>&1 || true
done

# 8. Login (una vez, interactivo; el token queda en ~/.claude/.credentials.json, fuera de la lista blanca de Syncthing)
until claude auth status 2>/dev/null | jq -e .loggedIn >/dev/null; do
  log "sin sesión: kubectl -n claude-remote exec -it deploy/claude-remote -c claude -- bash -lc 'claude auth login'"
  sleep 60 & wait $!
done

# 9. Remote Control: una ventana tmux por repo, con reinicio automático. Inspeccionar con
#    kubectl -n claude-remote exec -it deploy/claude-remote -c claude -- tmux attach -t rc
tmux kill-server 2>/dev/null
tmux new-session -d -s rc -n shell -c ~/git
for pair in $REPOS; do
  dir=${pair%%:*}
  tmux new-window -t rc -n "$dir" -c ~/git/$dir \
    "while true; do claude remote-control --name $dir --spawn worktree --permission-mode auto; echo 'Remote Control terminó; reinicio en 15 s'; sleep 15; done"
done
log "Remote Control activo para: $(for p in $REPOS; do printf '%s ' "${p%%:*}"; done)"

# 10. Vigilancia: conflictos de Syncthing y pull de los repos limpios en main cada hora.
n=0
while tmux has-session -t rc 2>/dev/null; do
  if (( n % 60 == 0 )); then
    c=$(find ~/.claude -name '*.sync-conflict-*' -not -path '*/.stversions/*' 2>/dev/null)
    [ -n "$c" ] && log "AVISO: conflictos de Syncthing en ~/.claude:"$'\n'"$c"
    for pair in $REPOS; do
      d=~/git/${pair%%:*}
      [ "$(git -C "$d" branch --show-current)" = main ] && [ -z "$(git -C "$d" status --porcelain)" ] \
        && git -C "$d" pull -q --ff-only 2>/dev/null
    done
  fi
  n=$((n + 1))
  sleep 60 & wait $!
done
log "la sesión tmux rc terminó; saliendo para que Kubernetes reinicie el contenedor"
exit 1
