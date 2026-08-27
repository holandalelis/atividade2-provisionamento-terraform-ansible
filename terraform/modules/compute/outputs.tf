output "instance_id" {
  description = "ID da instancia EC2"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "IP publico da instancia"
  value       = aws_instance.web.public_ip
}

output "public_dns" {
  description = "DNS publico da instancia"
  value       = aws_instance.web.public_dns
}

output "caminho_chave_privada" {
  description = "Caminho da chave privada gravada em disco"
  value       = local_sensitive_file.chave_privada.filename
}

output "ami_id" {
  description = "AMI Ubuntu resolvida dinamicamente"
  value       = data.aws_ami.ubuntu.id
}
