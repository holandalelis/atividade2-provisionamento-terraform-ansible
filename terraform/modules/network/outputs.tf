output "vpc_id" {
  description = "ID da VPC criada"
  value       = aws_vpc.this.id
}

output "subnet_id" {
  description = "ID da subnet publica onde a EC2 e criada"
  value       = aws_subnet.publica.id
}

output "security_group_id" {
  description = "ID do security group da aplicacao"
  value       = aws_security_group.app.id
}
