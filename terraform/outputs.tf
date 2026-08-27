output "ambiente" {
  description = "Workspace ativo (dev ou prod)"
  value       = terraform.workspace
}

output "instance_id" {
  description = "ID da instancia EC2 provisionada"
  value       = module.servidor.instance_id
}

output "ip_publico" {
  description = "IP publico da instancia"
  value       = module.servidor.public_ip
}

output "url_aplicacao" {
  description = "URL publica da getting-started-app"
  value       = "http://${module.servidor.public_ip}:3000"
}

output "comando_ssh" {
  description = "Comando SSH para inspecao manual (debug apenas)"
  value       = "ssh -i ${module.servidor.caminho_chave_privada} ubuntu@${module.servidor.public_ip}"
}

output "comando_ansible" {
  description = "Comando equivalente ao que o local-exec executa (util para rodar o Ansible manualmente)"
  value       = "cd ansible && ansible-playbook -i inventory/${terraform.workspace}.aws_ec2.yml playbook.yml --extra-vars ambiente=${terraform.workspace}"
}

output "vpc_id" {
  description = "ID da VPC"
  value       = module.rede.vpc_id
}
