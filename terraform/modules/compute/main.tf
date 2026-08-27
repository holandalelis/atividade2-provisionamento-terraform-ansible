# ---------------------------------------------------------------------------
# Modulo de compute: par de chaves SSH e a instancia EC2.
# A instancia sobe "crua": nenhum software e instalado aqui.
# Toda a configuracao interna e responsabilidade do Ansible.
# ---------------------------------------------------------------------------

locals {
  prefixo = "${var.projeto}-${var.ambiente}"
}

# AMI Ubuntu 24.04 LTS oficial da Canonical, resolvida dinamicamente.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Chave SSH gerada em codigo: nenhuma chave e criada manualmente na console.
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${local.prefixo}-key"
  public_key = tls_private_key.ssh.public_key_openssh

  tags = merge(var.tags_comuns, {
    Name = "${local.prefixo}-key"
  })
}

# A chave privada e gravada em disco apenas para o Ansible conseguir
# abrir a sessao SSH. O arquivo esta no .gitignore e nunca e commitado.
resource "local_sensitive_file" "chave_privada" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = var.caminho_chave_privada
  file_permission = "0600"
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.this.key_name

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # As tags abaixo nao sao decorativas: o inventario dinamico do Ansible
  # (amazon.aws.aws_ec2) filtra as instancias exatamente por elas.
  tags = merge(var.tags_comuns, {
    Name            = "${local.prefixo}-web"
    Projeto         = var.projeto
    Ambiente        = var.ambiente
    Funcao          = "webserver"
    Provisionamento = "terraform"
  })
}
