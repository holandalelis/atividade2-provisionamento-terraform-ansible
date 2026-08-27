variable "projeto" {
  description = "Nome base do projeto, usado como prefixo dos recursos"
  type        = string
}

variable "ambiente" {
  description = "Ambiente logico (workspace do Terraform: dev ou prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
}

variable "subnet_cidr" {
  description = "Bloco CIDR da subnet publica"
  type        = string
}

variable "portas_liberadas" {
  description = "Portas TCP liberadas no security group (22 para SSH do Ansible, 3000 para a aplicacao)"
  type        = list(number)
  default     = [22, 3000]
}

variable "cidr_ssh" {
  description = "CIDR autorizado a abrir SSH. Restrinja ao seu IP em uso real."
  type        = string
}

variable "tags_comuns" {
  description = "Tags aplicadas a todos os recursos do modulo"
  type        = map(string)
  default     = {}
}
