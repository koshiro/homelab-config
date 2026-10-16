# SOPS y las raíces de confianza

Estado al 2026-10-15. Reemplaza la versión de ArgoCD + KSOPS (agosto de 2025): ArgoCD se retiró el 2025-09-06 y el
namespace `argocd`, con su Secret `sops-age`, ya no existe. Con Flux (`docs/PLAN-FLUX.md`, fase 3) la clave vuelve
al cluster como `flux-system/sops-age`.

## Clave age

- **Pública** (destinatario de todos los `*.sops.*` del repo):
  `age1ga4dqzwv2wrf5c0dduz0vsjkzlda9xzrp787u2mnhhj6zh5qxaws4mlhhs`.
- **Obsoleta:** `age1ah9fskpkhm4v6jpagc20gjd6z3tfhtqvyae9uq58fwecrvtvjf5qrdj60v` (hasta 2025-08-21; la privada se
  perdió).
- **Privada**, dónde vive:

| Lugar | Para qué | ¿Sirve si se pierde el Mac? |
|-------|----------|-----------------------------|
| Mac: `~/.config/sops/age/keys.txt` y `.age-key` en la raíz del repo (ignorado por git; mismo contenido, mismo disco) | Uso diario | No |
| Secret `claude-remote/claude-remote`, clave `age-key` (sale de `cluster/apps/claude-remote/secret.sops.yml`) | Pod de Claude remoto | Solo si el cluster sigue vivo; en git está cifrado con esta misma clave |
| Kit A: Contraseñas de Apple, «homelab · clave age (SOPS)» | Recuperación | Sí |
| Kit B: `r2://homelab-recuperacion/homelab-kit.age`, cifrado con `age -p` | Recuperación | Sí |

## Contraseña del vault de Ansible

`~/.config/homelab/ansible-vault-pass` abre `ansible/vars/vault.yml`, que guarda el token completo de Cloudflare
(`vault_cloudfare_full_api_token`), el de R2 y `vault_restic_r2_password` (sin ella no se lee el respaldo offsite).
Tiene las mismas copias que la clave: el Secret de `claude-remote` (`ansible-vault-pass`) y los kits A y B.

Cómo crear, comprobar y restaurar el kit: `README.md` § Operación, «Kit de recuperación»
(`scripts/kit-recuperacion.sh`).

## Uso

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops <archivo>.sops.yml                                  # editar en el lugar
.claude/skills/homelab/hl.py sops encrypt <secret.yaml>  # cifrar data/stringData en el lugar
```

Formato: YAML estructurado con `--encrypted-regex '^(data|stringData)$'` (reglas en `.sops.yaml` de la raíz; revisar
con `python3 -I scripts/flux/sops_formato.py`). Aplicar = mergear: Flux descifra los `*.sops.*` que entran por el
Component `solo-flux/` de cada carpeta, con el secret `sops-age` del namespace `flux-system`.

## Si se pierde la clave y no hay kit

Los archivos cifrados y todo su historial en git quedan ilegibles. Lo que esté aplicado se puede rescatar del cluster
(`kubectl get secret -o yaml`). Después: generar una clave nueva con `age-keygen`, volver a cifrar todos los
`*.sops.*` y rehacer el kit.
