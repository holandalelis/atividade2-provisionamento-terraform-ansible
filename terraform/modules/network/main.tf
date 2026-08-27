# ---------------------------------------------------------------------------
# Modulo de rede: VPC, subnet publica, internet gateway, rota e security group.
# Responsabilidade exclusiva do Terraform (infraestrutura).
# ---------------------------------------------------------------------------

locals {
  prefixo = "${var.projeto}-${var.ambiente}"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags_comuns, {
    Name = "${local.prefixo}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags_comuns, {
    Name = "${local.prefixo}-igw"
  })
}

# Subnet publica: map_public_ip_on_launch garante IP publico na EC2,
# que e o endereco usado pelo inventario dinamico do Ansible.
resource "aws_subnet" "publica" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.disponiveis.names[0]

  tags = merge(var.tags_comuns, {
    Name = "${local.prefixo}-subnet-publica"
  })
}

data "aws_availability_zones" "disponiveis" {
  state = "available"
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags_comuns, {
    Name = "${local.prefixo}-rt-publica"
  })
}

resource "aws_route_table_association" "publica" {
  subnet_id      = aws_subnet.publica.id
  route_table_id = aws_route_table.publica.id
}

resource "aws_security_group" "app" {
  name        = "${local.prefixo}-sg"
  description = "Libera SSH (Ansible) e a porta 3000 (getting-started-app)"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags_comuns, {
    Name = "${local.prefixo}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Regras declaradas como recursos separados: evita o conflito classico entre
# blocos ingress inline e alteracoes feitas fora do Terraform.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.app.id
  description       = "SSH usado pelo Ansible para configurar a instancia"
  cidr_ipv4         = var.cidr_ssh
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app" {
  security_group_id = aws_security_group.app.id
  description       = "Porta HTTP da getting-started-app"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "saida" {
  security_group_id = aws_security_group.app.id
  description       = "Saida liberada (apt, Docker Hub, GitHub)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
