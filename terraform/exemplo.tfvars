# Configuracao deste ambiente de execucao (Windows + Ansible no WSL).
# Em Linux/macOS remova as tres linhas abaixo: os defaults ja funcionam.

comando_ansible    = "bash ../scripts/ansible-wsl.sh"
dir_chaves_ansible = "/root/.ssh/iac-final"
ansible_no_wsl     = true
