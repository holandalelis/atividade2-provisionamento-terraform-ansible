# ===========================================================================
# Raiz do projeto: Terraform provisiona, Ansible configura.
#
# Fronteira de responsabilidade:
#   - Terraform: VPC, subnet, IGW, rotas, security group, chave e EC2.
#   - Ansible:   Docker Engine, imagem e container da aplicacao.
#
# Nao existe provisioner "remote-exec" neste projeto. O unico provisioner
# e um "local-exec" (recurso ansible_apply, abaixo) que roda na maquina do
# operador e apenas ORQUESTRA a chamada ao ansible-playbook -- ele nao
# executa nenhum comando dentro do servidor remoto.
# ===========================================================================

locals {
  ambiente = terraform.workspace

  # Falha cedo e com mensagem clara se alguem rodar no workspace "default".
  cidrs = lookup(
    var.cidrs_por_ambiente,
    local.ambiente,
    null
  )

  raiz_projeto  = abspath("${path.module}/..")
  dir_ansible   = "${local.raiz_projeto}/ansible"
  caminho_chave = "${local.raiz_projeto}/terraform/.chaves/${var.projeto}-${local.ambiente}.pem"

  # O Terraform pode rodar no Windows enquanto o Ansible roda no WSL. O caminho
  # gravado no inventario precisa estar no formato que o Ansible enxerga:
  #   C:/Users/fulano/proj/chave.pem  ->  /mnt/c/Users/fulano/proj/chave.pem
  caminho_chave_posix = replace(local.caminho_chave, "\\", "/")
  caminho_chave_wsl = format(
    "/mnt/%s%s",
    lower(substr(local.caminho_chave_posix, 0, 1)),
    substr(local.caminho_chave_posix, 2, length(local.caminho_chave_posix) - 2)
  )

  nome_chave = "${var.projeto}-${local.ambiente}.pem"

  # Ordem de precedencia: diretorio explicito > conversao WSL > caminho local.
  caminho_chave_ansible = (
    var.dir_chaves_ansible != "" ? "${var.dir_chaves_ansible}/${local.nome_chave}" :
    var.ansible_no_wsl ? local.caminho_chave_wsl :
    local.caminho_chave_posix
  )

  tags_comuns = {
    Projeto  = var.projeto
    Ambiente = local.ambiente
  }
}

# Guarda de seguranca: a atividade exige os workspaces dev e prod.
# O workspace "default" nao tem CIDR definido e e bloqueado aqui.
resource "terraform_data" "valida_workspace" {
  lifecycle {
    precondition {
      condition     = local.cidrs != null
      error_message = "Workspace '${terraform.workspace}' invalido. Use: terraform workspace select dev (ou prod)."
    }
  }
}

module "rede" {
  source = "./modules/network"

  projeto     = var.projeto
  ambiente    = local.ambiente
  vpc_cidr    = local.cidrs.vpc
  subnet_cidr = local.cidrs.subnet
  cidr_ssh    = var.cidr_ssh
  tags_comuns = local.tags_comuns

  depends_on = [terraform_data.valida_workspace]
}

module "servidor" {
  source = "./modules/compute"

  projeto               = var.projeto
  ambiente              = local.ambiente
  subnet_id             = module.rede.subnet_id
  security_group_id     = module.rede.security_group_id
  instance_type         = var.instance_type
  caminho_chave_privada = local.caminho_chave
  tags_comuns           = local.tags_comuns
}

# ---------------------------------------------------------------------------
# INTEGRACAO TERRAFORM -> ANSIBLE (Opcao B: local-exec)
#
# 1. Gera o arquivo de variaveis que o inventario dinamico consome, para que
#    o Ansible filtre exatamente a instancia deste workspace.
# 2. Espera a porta 22 responder (o Ansible falharia se a VM ainda estivesse
#    no boot).
# 3. Chama ansible-playbook na maquina local.
#
# Os triggers garantem idempotencia: o local-exec so reexecuta se a instancia
# mudar, se o playbook mudar ou se as roles mudarem. Um segundo
# "terraform apply" sem alteracoes nao dispara o Ansible novamente.
# ---------------------------------------------------------------------------

resource "local_file" "inventario_vars" {
  filename        = "${local.dir_ansible}/inventory/${local.ambiente}.aws_ec2.yml"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventario.aws_ec2.yml.tftpl", {
    regiao        = var.aws_region
    projeto       = var.projeto
    ambiente      = local.ambiente
    caminho_chave = local.caminho_chave_ansible
  })
}

resource "null_resource" "ansible_apply" {
  count = var.executar_ansible ? 1 : 0

  triggers = {
    instance_id   = module.servidor.instance_id
    ip_publico    = module.servidor.public_ip
    hash_playbook = filesha256("${local.dir_ansible}/playbook.yml")
    hash_roles = sha256(join("", [
      for arquivo in sort(fileset("${local.dir_ansible}/roles", "**/*.yml")) :
      filesha256("${local.dir_ansible}/roles/${arquivo}")
    ]))
    hash_inventario = local_file.inventario_vars.content_sha256
  }

  # Espera ativa pela porta 22. Sem isso, o primeiro apply chamaria o Ansible
  # enquanto a instancia ainda esta no boot e o playbook falharia por timeout
  # de SSH. E um local-exec: o loop roda na maquina do operador, nao no servidor.
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      echo "Aguardando SSH em ${module.servidor.public_ip}:22 ..."
      for tentativa in $(seq 1 60); do
        if ssh -o BatchMode=yes -o ConnectTimeout=5                -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null                -i "${replace(local.caminho_chave, "\\", "/")}"                ubuntu@${module.servidor.public_ip} 'echo pronto' 2>/dev/null; then
          echo "SSH disponivel apos $tentativa tentativa(s)."
          exit 0
        fi
        sleep 5
      done
      echo "Timeout aguardando SSH." >&2
      exit 1
    EOT
  }

  # local-exec: roda na maquina do operador, apenas para chamar o Ansible.
  provisioner "local-exec" {
    working_dir = local.dir_ansible
    interpreter = var.comando_ansible == "ansible-playbook" ? null : ["bash", "-c"]

    command = join(" ", [
      var.comando_ansible,
      "-i", "inventory/${local.ambiente}.aws_ec2.yml",
      "playbook.yml",
      "--extra-vars", "ambiente=${local.ambiente}",
    ])

    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_CONFIG            = "${local.dir_ansible}/ansible.cfg"
    }
  }

  depends_on = [
    module.servidor,
    local_file.inventario_vars,
  ]
}
