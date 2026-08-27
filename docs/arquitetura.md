# Diagrama de arquitetura

```
                            INTERNET
                                |
                                v
                    +-----------------------+
                    |   Internet Gateway    |   (aws_internet_gateway)
                    +-----------------------+
                                |
  ==============================================================
  |  VPC  10.10.0.0/16 (dev)  |  10.20.0.0/16 (prod)           |
  |                                                            |
  |   Route Table  0.0.0.0/0 -> IGW                            |
  |                            |                               |
  |   +--------------------------------------------------+     |
  |   |  Subnet publica  10.10.1.0/24  (map_public_ip)    |     |
  |   |                                                    |    |
  |   |   Security Group                                   |    |
  |   |     ingress  22/tcp    <- SSH (Ansible)            |    |
  |   |     ingress  3000/tcp  <- HTTP (aplicacao)         |    |
  |   |     egress   all       -> apt, Docker Hub, GitHub  |    |
  |   |                                                    |    |
  |   |   +--------------------------------------------+   |    |
  |   |   |  EC2 t3.micro - Ubuntu 24.04 LTS           |   |    |
  |   |   |                                            |   |    |
  |   |   |   [Terraform] cria a instancia "crua"      |   |    |
  |   |   |   [Ansible]   instala o Docker Engine      |   |    |
  |   |   |   [Ansible]   builda a imagem da app       |   |    |
  |   |   |   [Ansible]   roda o container :3000       |   |    |
  |   |   |                                            |   |    |
  |   |   |   getting-started-app  (porta 3000)        |   |    |
  |   |   +--------------------------------------------+   |    |
  |   +--------------------------------------------------+     |
  ==============================================================


FLUXO DE EXECUCAO
-----------------

  terraform apply
        |
        | 1. cria VPC, subnet, IGW, rotas, SG, key pair e EC2
        |
        | 2. local_file.inventario_vars
        |    grava ansible/inventory/<workspace>.aws_ec2.yml
        |
        | 3. null_resource.ansible_apply  (provisioner local-exec)
        |    3a. aguarda a porta 22 responder
        |    3b. executa:  ansible-playbook -i inventory/<ws>.aws_ec2.yml playbook.yml
        v
  ansible-playbook   (roda na MAQUINA LOCAL, nunca no servidor)
        |
        | consulta a API da AWS pelo plugin amazon.aws.aws_ec2
        | e descobre a instancia pelas tags Projeto/Ambiente/Funcao
        v
  +-----------------------+       +--------------------------+
  |  role: docker         |  -->  |  role: app               |
  |  - repo oficial       |       |  - clona o codigo        |
  |  - docker-ce          |       |  - gera o Dockerfile     |
  |  - servico ativo      |       |  - docker_image (build)  |
  |  - usuario no grupo   |       |  - docker_container (run)|
  +-----------------------+       +--------------------------+
                                              |
                                              v
                                  http://<IP_PUBLICO>:3000
```
