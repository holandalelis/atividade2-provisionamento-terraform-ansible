variable "aws_region" {
  description = "Regiao AWS onde a infraestrutura sera criada"
  type        = string
  default     = "us-east-1"
}

variable "projeto" {
  description = "Nome base do projeto, prefixo de todos os recursos"
  type        = string
  default     = "iac-final"
}

variable "instance_type" {
  description = "Tipo da instancia EC2. A atividade exige t3.micro (Free Tier)."
  type        = string
  default     = "t3.micro"
}

variable "cidr_ssh" {
  description = "CIDR autorizado a abrir SSH na instancia"
  type        = string
  default     = "0.0.0.0/0"
}

variable "executar_ansible" {
  description = "Quando true, o terraform apply dispara o ansible-playbook via local-exec"
  type        = bool
  default     = true
}

variable "comando_ansible" {
  description = "Executavel do Ansible. Em Windows use o wrapper WSL definido no README."
  type        = string
  default     = "ansible-playbook"
}

# Cada workspace tem sua propria faixa de rede, evitando sobreposicao
# caso dev e prod venham a ser conectados no futuro.
variable "cidrs_por_ambiente" {
  description = "Blocos CIDR de VPC e subnet por workspace"
  type = map(object({
    vpc    = string
    subnet = string
  }))
  default = {
    dev = {
      vpc    = "10.10.0.0/16"
      subnet = "10.10.1.0/24"
    }
    prod = {
      vpc    = "10.20.0.0/16"
      subnet = "10.20.1.0/24"
    }
  }
}

variable "ansible_no_wsl" {
  description = <<-DESC
    Marque como true quando o Terraform roda no Windows e o Ansible roda no WSL.
    Nesse caso o caminho da chave gravado no inventario e convertido de
    "C:/..." para "/mnt/c/...". Em Linux/macOS deixe false.
  DESC
  type        = bool
  default     = false
}

variable "dir_chaves_ansible" {
  description = <<-DESC
    Diretorio onde o Ansible encontra a chave privada. Deixe vazio para usar o
    mesmo caminho gerado pelo Terraform. Ao rodar o Ansible no WSL a partir do
    Windows, use "/root/.ssh/iac-final" -- o wrapper scripts/ansible-wsl.sh copia
    a chave para la, porque /mnt/c nao aceita a permissao 0600 exigida pelo SSH.
  DESC
  type        = string
  default     = ""
}
