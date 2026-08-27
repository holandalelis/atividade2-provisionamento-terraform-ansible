# Projeto Final IaC — Terraform + Ansible

Provisionamento e configuração integrados na AWS: o **Terraform** cria a
infraestrutura, o **Ansible** configura o que roda dentro dela, e a aplicação
[`getting-started-app`](https://github.com/docker/getting-started-app) da Docker
sobe como container na porta **3000**.

> **Disciplina:** Infraestrutura como Código — Pós-graduação em DevOps
> **Atividade 2 — Projeto Final**

---

## Sumário

- [Arquitetura](#arquitetura)
- [Separação de responsabilidades](#separação-de-responsabilidades)
- [Integração Terraform → Ansible](#integração-terraform--ansible)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Pré-requisitos](#pré-requisitos)
- [Como executar](#como-executar)
- [Workspaces (dev e prod)](#workspaces-dev-e-prod)
- [Idempotência](#idempotência)
- [Proteção de segredos (ansible-vault)](#proteção-de-segredos-ansible-vault)
- [Destruição dos recursos](#destruição-dos-recursos)
- [Evidências](#evidências)

---

## Arquitetura

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
  |   |  Subnet publica  10.10.1.0/24  (map_public_ip)   |     |
  |   |                                                  |     |
  |   |   Security Group                                 |     |
  |   |     ingress  22/tcp    <- SSH (Ansible)          |     |
  |   |     ingress  3000/tcp  <- HTTP (aplicacao)       |     |
  |   |     egress   all       -> apt, Docker Hub, GitHub|     |
  |   |                                                  |     |
  |   |   +------------------------------------------+   |     |
  |   |   |  EC2 t3.micro - Ubuntu 24.04 LTS         |   |     |
  |   |   |                                          |   |     |
  |   |   |   [Terraform] cria a instancia "crua"    |   |     |
  |   |   |   [Ansible]   instala o Docker Engine    |   |     |
  |   |   |   [Ansible]   builda a imagem da app     |   |     |
  |   |   |   [Ansible]   roda o container :3000     |   |     |
  |   |   |                                          |   |     |
  |   |   |   getting-started-app  (porta 3000)      |   |     |
  |   |   +------------------------------------------+   |     |
  |   +--------------------------------------------------+     |
  ==============================================================
```

### Fluxo de execução

```
  terraform apply
        |
        | 1. cria VPC, subnet, IGW, rotas, SG, key pair e EC2
        |
        | 2. local_file.inventario_vars
        |    grava ansible/inventory/<workspace>.aws_ec2.yml
        |
        | 3. null_resource.ansible_apply  (provisioner local-exec)
        |    3a. aguarda a porta 22 responder
        |    3b. executa: ansible-playbook -i inventory/<ws>.aws_ec2.yml playbook.yml
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

---

## Separação de responsabilidades

A regra que orienta todo o projeto: **cada ferramenta faz apenas o que sabe
fazer melhor.**

| Camada | Ferramenta | O que faz |
|---|---|---|
| Infraestrutura | Terraform | VPC, subnet, Internet Gateway, route table, security group, key pair, instância EC2 |
| Configuração | Ansible | Docker Engine, build da imagem, execução do container, healthcheck |

**Não existe `provisioner "remote-exec"` neste repositório.** Configurar o
servidor pelo Terraform quebraria a idempotência e jogaria fora a razão de usar
Ansible. Você pode verificar:

```bash
grep -rn "remote-exec" terraform/
```

O único provisioner presente é um `local-exec`, que **roda na máquina do
operador** e apenas *chama* o `ansible-playbook` — ele não executa nada dentro
da instância.

---

## Integração Terraform → Ansible

### Opção escolhida: **B — `local-exec` disparando o Ansible automaticamente**

Com um detalhe que também incorpora o melhor da Opção A: o inventário **não é
uma lista fixa de IPs**, e sim o **inventário dinâmico** `amazon.aws.aws_ec2`,
que consulta a API da AWS em tempo de execução.

### O que dispara o quê, em que ordem

Os três recursos abaixo estão em `terraform/main.tf`:

| # | Recurso | Arquivo | O que faz |
|---|---|---|---|
| 1 | `module.servidor` | `terraform/modules/compute/main.tf` | Cria a EC2 com as tags `Projeto`, `Ambiente` e `Funcao=webserver`, e grava a chave privada em `terraform/.chaves/` |
| 2 | `local_file.inventario_vars` | `terraform/main.tf` | Renderiza `templates/inventario.aws_ec2.yml.tftpl` e grava `ansible/inventory/<workspace>.aws_ec2.yml` |
| 3 | `null_resource.ansible_apply` | `terraform/main.tf` | Dois `local-exec`: espera o SSH subir e depois executa o `ansible-playbook` |

**Ordem garantida por `depends_on`:** o `null_resource.ansible_apply` declara
`depends_on = [module.servidor, local_file.inventario_vars]`, então o Ansible só
é chamado depois que a instância existe *e* o inventário foi escrito.

### Por que dessa forma

1. **O inventário é gerado, não escrito à mão.** O IP público só existe depois
   do `apply`. O Terraform grava o arquivo de inventário com o filtro de tags e
   o caminho da chave já corretos para o workspace ativo.

2. **A descoberta do host é dinâmica.** O arquivo gerado não contém IP nenhum —
   ele diz ao Ansible *como procurar* a instância:

   ```yaml
   plugin: amazon.aws.aws_ec2
   filters:
     tag:Projeto: iac-final
     tag:Ambiente: dev
     tag:Funcao: webserver
     instance-state-name: running
   ```

   Se a instância for recriada com outro IP, o Ansible continua encontrando-a.

3. **Espera pelo SSH antes de chamar o Ansible.** Sem isso, o primeiro `apply`
   chamaria o playbook enquanto a VM ainda está no boot e falharia por timeout.
   O laço de espera roda **na máquina local** (`local-exec`), não no servidor.

4. **`triggers` controlam a reexecução.** O `local-exec` só dispara de novo se
   algo relevante mudar:

   ```hcl
   triggers = {
     instance_id     = module.servidor.instance_id
     ip_publico      = module.servidor.public_ip
     hash_playbook   = filesha256(".../playbook.yml")
     hash_roles      = sha256(join("", [...]))   # hash de todas as roles
     hash_inventario = local_file.inventario_vars.content_sha256
   }
   ```

   Um segundo `terraform apply` sem alterações resulta em
   **"No changes. Your infrastructure matches the configuration."** — o Ansible
   nem chega a ser chamado.

---

## Estrutura do repositório

```
.
├── README.md
├── .gitignore
├── docs/
│   └── arquitetura.md
├── evidencias/                      # prints e saídas de curl
├── terraform/
│   ├── providers.tf                 # providers e default_tags
│   ├── variables.tf                 # variáveis raiz + CIDRs por workspace
│   ├── main.tf                      # composição dos módulos + INTEGRAÇÃO
│   ├── outputs.tf                   # IP, URL, comandos prontos
│   ├── templates/
│   │   └── inventario.aws_ec2.yml.tftpl
│   └── modules/
│       ├── network/                 # VPC, subnet, IGW, rotas, SG
│       └── compute/                 # key pair, AMI, EC2
└── ansible/
    ├── ansible.cfg
    ├── requirements.yml             # coleções amazon.aws e community.docker
    ├── playbook.yml                 # playbook principal
    ├── inventory/
    │   └── exemplo.aws_ec2.yml      # exemplo versionado (o real é gerado)
    ├── group_vars/all/
    │   ├── main.yml                 # variáveis não sensíveis
    │   └── vault.yml                # variável sensível (cifrada)
    └── roles/
        ├── docker/                  # instala o Docker Engine
        └── app/                     # builda a imagem e sobe o container
```

---

## Pré-requisitos

| Ferramenta | Versão | Observação |
|---|---|---|
| Terraform | >= 1.5 | |
| Ansible | >= 2.16 (ansible-core) | Não roda nativamente em Windows — use WSL |
| AWS CLI | v2 | Credenciais configuradas |
| Python | >= 3.10 | Com `boto3` e `botocore` |

### Observação para quem executa no Windows

O Ansible não roda nativamente no Windows. Este projeto foi executado com o
Terraform no Windows e o Ansible dentro do WSL (Ubuntu 24.04), ligados pelo
wrapper [`scripts/ansible-wsl.sh`](scripts/ansible-wsl.sh).

O wrapper resolve três diferenças entre os dois lados:

1. **Conversão de caminhos** — `C:/projeto` (ou `/c/projeto`, no Git Bash) vira
   `/mnt/c/projeto`, formato que o Ansible enxerga.
2. **Permissão da chave SSH** — o drive `C:` é montado no WSL com permissão fixa
   `0644`, e o SSH recusa chaves privadas que não estejam em `0600`. O wrapper
   copia a chave para o filesystem nativo do WSL antes de cada execução.
3. **Credenciais da AWS** — repassa `~/.aws` para dentro do WSL, já que o
   inventário dinâmico precisa consultar a API da AWS.

A ativação fica em [`terraform/terraform.tfvars`](terraform/exemplo.tfvars):

```hcl
comando_ansible    = "bash ../scripts/ansible-wsl.sh"
dir_chaves_ansible = "/root/.ssh/iac-final"
ansible_no_wsl     = true
```

**Em Linux ou macOS nada disso é necessário:** basta remover essas três linhas
e os valores padrão (`ansible-playbook` direto) já funcionam.

Preparação do WSL, uma vez só:

```bash
wsl --install Ubuntu-24.04
```

```bash
python3 -m venv /opt/ansible-venv && /opt/ansible-venv/bin/pip install ansible-core boto3 botocore docker
```

Instalação das dependências do Ansible:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

```bash
pip install boto3 botocore docker
```

### Credenciais AWS

```bash
aws sts get-caller-identity
```

### Senha do vault

O arquivo `ansible/.vault_pass` guarda a senha do `ansible-vault` e **está no
`.gitignore`** — ele não é versionado. Para recriá-lo:

```bash
echo "SUA_SENHA_DO_VAULT" > ansible/.vault_pass && chmod 600 ansible/.vault_pass
```

---

## Como executar

### Passo 1 — inicializar o Terraform

```bash
cd terraform && terraform init
```

### Passo 2 — selecionar o workspace

```bash
terraform workspace new dev || terraform workspace select dev
```

### Passo 3 — revisar o plano

```bash
terraform plan
```

### Passo 4 — aplicar (provisiona E configura)

```bash
terraform apply -auto-approve
```

Este único comando executa todo o fluxo: cria a infraestrutura, gera o
inventário, espera o SSH e roda o `ansible-playbook`.

### Passo 5 — obter a URL da aplicação

```bash
terraform output url_aplicacao
```

### Passo 6 — validar que a aplicação está no ar

```bash
curl -i "$(terraform output -raw url_aplicacao)"
```

### Executando o Ansible separadamente (opcional)

O playbook também roda sozinho, sem o Terraform:

```bash
cd ansible && ansible-playbook -i inventory/dev.aws_ec2.yml playbook.yml
```

Para conferir o inventário dinâmico resolvido:

```bash
cd ansible && ansible-inventory -i inventory/dev.aws_ec2.yml --graph
```

---

## Workspaces (dev e prod)

Cada workspace tem **state próprio** e **faixa de rede própria**, evitando
sobreposição de CIDR:

| Workspace | VPC | Subnet |
|---|---|---|
| `dev` | `10.10.0.0/16` | `10.10.1.0/24` |
| `prod` | `10.20.0.0/16` | `10.20.1.0/24` |

```bash
terraform workspace list
```

```bash
terraform workspace new prod || terraform workspace select prod
```

O workspace `default` é **bloqueado de propósito** por uma `precondition` em
`terraform_data.valida_workspace`: rodar sem escolher o ambiente retorna
`Workspace 'default' invalido. Use: terraform workspace select dev (ou prod).`

---

## Idempotência

A segunda execução completa do fluxo não altera nada.

**Terraform** — o segundo `apply` reporta:

```
No changes. Your infrastructure matches the configuration.
```

**Ansible** — o playbook rodado duas vezes reporta `changed=0` na segunda:

```bash
cd ansible && ansible-playbook -i inventory/dev.aws_ec2.yml playbook.yml
```

O que garante isso:

| Ponto de risco | Como foi resolvido |
|---|---|
| `git` refazendo fetch a cada execução | `update: false` no módulo `ansible.builtin.git` |
| `docker_image` reconstruindo a imagem sempre | `force_source` só é `true` quando o Dockerfile realmente mudou |
| `docker_container` recriando o container | `comparisons: {"*": strict}` — só recria se a definição mudar |
| `apt` atualizando cache toda vez | `cache_valid_time: 3600` |
| `local-exec` disparando a cada `apply` | `triggers` com hash do playbook, das roles e do inventário |
| Healthcheck marcando "changed" | `changed_when: false` na task `uri` |

---

## Proteção de segredos (ansible-vault)

A variável sensível simulada `app_admin_password` fica cifrada em
`ansible/group_vars/all/vault.yml` e é injetada como variável de ambiente no
container.

Visualizar (exige a senha do vault):

```bash
ansible-vault view ansible/group_vars/all/vault.yml
```

Editar:

```bash
ansible-vault edit ansible/group_vars/all/vault.yml
```

Nenhuma credencial real está versionada: `.vault_pass`, `*.pem`, `*.tfvars` e o
state do Terraform estão todos no `.gitignore`.

---

## Destruição dos recursos

```bash
cd terraform && terraform workspace select dev
```

```bash
terraform destroy -auto-approve
```

Se o workspace `prod` também tiver sido usado:

```bash
terraform workspace select prod && terraform destroy -auto-approve
```

Confirmar que nada sobrou na região:

```bash
aws ec2 describe-instances --region us-east-1 --filters "Name=instance-state-name,Values=running,pending,stopped" --query "Reservations[].Instances[].[InstanceId,State.Name]" --output table
```

---

## Evidências

Todas as evidências foram capturadas durante a execução real do projeto na
AWS e estão em [`evidencias/`](evidencias/).

| # | Evidência | Arquivo | O que comprova |
|---|---|---|---|
| 1 | Aplicação no navegador (dev) | [`app_navegador.png`](evidencias/app_navegador.png) | A getting-started-app no ar, com itens gravados pelo backend |
| 2 | Aplicação no navegador (prod) | [`app_navegador_prod.png`](evidencias/app_navegador_prod.png) | O segundo workspace no ar, com banco independente do dev |
| 3 | `curl` contra o IP público | [`app_curl.png`](evidencias/app_curl.png) | HTTP 200 na porta 3000 a partir da internet |
| 4 | EC2 e Security Group na AWS | [`instancia_aws.png`](evidencias/instancia_aws.png) | t3.micro `running`, portas 22 e 3000 liberadas, tags aplicadas |
| 5 | Workspaces dev e prod | [`workspaces.png`](evidencias/workspaces.png) | States isolados, CIDRs distintos (10.10 e 10.20), ambos HTTP 200 |
| 6 | Idempotência do Ansible | [`idempotencia_ansible.png`](evidencias/idempotencia_ansible.png) | 2ª execução do playbook com **`changed=0`** |
| 7 | Idempotência do Terraform | [`idempotencia_terraform.png`](evidencias/idempotencia_terraform.png) | `local-exec` chamando o Ansible e, na sequência, **"No changes"** |
| 8 | Ausência de `remote-exec` | [`sem_remote_exec.png`](evidencias/sem_remote_exec.png) | Os únicos provisioners são `local-exec` |
| 9 | Variável protegida com vault | [`ansible_vault.png`](evidencias/ansible_vault.png) | `vault.yml` cifrado no repositório e legível só com a senha |
| 10 | Destruição dos recursos | [`destroy.png`](evidencias/destroy.png) | 32 recursos destruídos e região `us-east-1` sem nada remanescente |

### Resultado da execução real

```
Terraform:  Apply complete!  Resources: 16 added   (por workspace)
Ansible:    PLAY RECAP  ok=22  changed=11  failed=0     (1a execucao)
Ansible:    PLAY RECAP  ok=21  changed=0   failed=0     (2a execucao - idempotente)
Terraform:  No changes. Your infrastructure matches the configuration.
Terraform:  Destroy complete!  Resources: 16 destroyed  (por workspace)
```
