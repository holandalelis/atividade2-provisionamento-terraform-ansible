#!/bin/bash
# ===========================================================================
# Wrapper que permite ao Terraform rodando no Windows chamar o ansible-playbook
# dentro do WSL. Em Linux/macOS este wrapper e desnecessario: basta deixar a
# variavel comando_ansible com o valor padrao "ansible-playbook".
#
# Uso (via Terraform, ja configurado em terraform.tfvars):
#   comando_ansible = "bash ../scripts/ansible-wsl.sh"
#
# Uso manual:
#   bash scripts/ansible-wsl.sh -i inventory/dev.aws_ec2.yml playbook.yml
#
# Por que este wrapper existe alem da simples chamada ao WSL:
#   O drive C: e montado no WSL com permissao fixa (0644 para arquivos).
#   O SSH recusa chaves privadas que não estejam em 0600, e essa permissao
#   nao pode ser aplicada em /mnt/c. Por isso a chave e copiada para o
#   filesystem nativo do WSL antes de cada execucao.
# ===========================================================================
set -euo pipefail

DISTRO="${WSL_DISTRO:-Ubuntu-24.04}"
ANSIBLE_BIN="${ANSIBLE_BIN:-/opt/ansible-venv/bin/ansible-playbook}"
COLLECTIONS="${ANSIBLE_COLLECTIONS:-/opt/ansible-collections}"

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_ANSIBLE_WIN="$(cd "$DIR_SCRIPT/../ansible" && pwd)"
DIR_CHAVES_WIN="$(cd "$DIR_SCRIPT/../terraform" && pwd)/.chaves"

# Converte um caminho para o formato que o WSL enxerga (/mnt/c/...).
# Aceita os tres formatos possiveis, dependendo de onde o script e chamado:
#   C:/Users/...   (PowerShell / cmd)
#   /c/Users/...   (Git Bash)
#   /mnt/c/...     (ja convertido)
para_wsl() {
  local caminho="$1"
  caminho="${caminho//\\//}"

  if [[ "$caminho" == /mnt/* ]]; then
    printf '%s' "$caminho"
  elif [[ "$caminho" =~ ^([A-Za-z]):(.*)$ ]]; then
    printf '/mnt/%s%s' "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')" "${BASH_REMATCH[2]}"
  elif [[ "$caminho" =~ ^/([A-Za-z])/(.*)$ ]]; then
    printf '/mnt/%s/%s' "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')" "${BASH_REMATCH[2]}"
  else
    printf '%s' "$caminho"
  fi
}

DIR_ANSIBLE_WSL="$(para_wsl "$DIR_ANSIBLE_WIN")"
DIR_CHAVES_WSL="$(para_wsl "$DIR_CHAVES_WIN")"
DIR_AWS_WSL="$(para_wsl "${USERPROFILE:-$HOME}/.aws")"

wsl.exe -d "$DISTRO" -u root -- bash -lc "
  set -euo pipefail

  export ANSIBLE_COLLECTIONS_PATH='$COLLECTIONS'
  export ANSIBLE_HOST_KEY_CHECKING=False
  export ANSIBLE_DEPRECATION_WARNINGS=False
  # O inventario dinamico amazon.aws.aws_ec2 precisa das credenciais da AWS.
  export AWS_SHARED_CREDENTIALS_FILE='$DIR_AWS_WSL/credentials'
  export AWS_CONFIG_FILE='$DIR_AWS_WSL/config'

  # Copia as chaves para o filesystem nativo do WSL, onde 0600 e respeitado.
  mkdir -p /root/.ssh/iac-final
  chmod 700 /root/.ssh/iac-final
  if compgen -G '$DIR_CHAVES_WSL/*.pem' > /dev/null; then
    cp '$DIR_CHAVES_WSL'/*.pem /root/.ssh/iac-final/
    chmod 600 /root/.ssh/iac-final/*.pem
  fi

  cd '$DIR_ANSIBLE_WSL'
  exec '$ANSIBLE_BIN' $*
"
