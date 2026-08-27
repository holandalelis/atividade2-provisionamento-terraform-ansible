variable "projeto" {
  description = "Nome base do projeto, usado como prefixo dos recursos"
  type        = string
}

variable "ambiente" {
  description = "Ambiente logico (workspace do Terraform: dev ou prod)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet publica onde a instancia sera criada"
  type        = string
}

variable "security_group_id" {
  description = "Security group aplicado a instancia"
  type        = string
}

variable "instance_type" {
  description = "Tipo da instancia EC2 (t3.micro conforme requisito da atividade)"
  type        = string
  default     = "t3.micro"
}

variable "caminho_chave_privada" {
  description = "Caminho onde a chave privada gerada sera gravada para uso do Ansible"
  type        = string
}

variable "tags_comuns" {
  description = "Tags aplicadas a todos os recursos do modulo"
  type        = map(string)
  default     = {}
}
