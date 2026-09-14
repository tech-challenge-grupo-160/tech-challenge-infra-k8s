# Infraestrutura AWS com Terraform e EKS

Esta pasta concentra a definição de infraestrutura como código do projeto. O
ambiente roda inteiramente na AWS (conta do **AWS Academy Learner Lab**), com
cluster Kubernetes gerenciado (**EKS**), rede própria (VPC, subnets públicas e
privadas, NAT Gateway), banco de dados gerenciado (**RDS**), autenticação via
**Lambda + API Gateway (HTTP API) com VPC Link**, e exposição da API através
de um Application Load Balancer via Ingress no cluster.

> Este repositório substitui a infraestrutura local baseada em Kind usada na
> Fase 2. A partir da Fase 3, não há mais cluster local: tudo é provisionado
> na AWS.

## Papel desta camada

O Terraform aqui é responsável por criar:

- backend remoto de state (bucket S3 + tabela DynamoDB de lock), em
  `bootstrap/`;
- VPC, subnets públicas/privadas, NAT Gateway, Internet Gateway;
- cluster EKS (opcional via feature flag `criar_cluster`), node groups e
  Cluster Autoscaler;
- ECR para a imagem da API;
- API Gateway (HTTP API) com VPC Link, rotas e o Lambda Authorizer (JWT);
- security groups e VPC endpoints necessários;
- SNS e alarms para notificações;

tudo em `infra/`. O banco de dados gerenciado (RDS) vive em repositório
separado (`tech-challenge-infra-database`), pois depende do state de rede
deste repositório (vpc_id, subnets, security group).

Os manifests da aplicação ficam em `../k8s`, aplicados via Kustomize:

```bash
kubectl apply -k k8s/nuvem
```

Essa separação evita duplicidade de responsabilidade:

- **infra/**: cria rede, cluster, gateway, ECR e configurações sensíveis;
- **k8s/**: define Deployments, Services, ConfigMaps, Secrets (montados do
  Secrets Manager) e HPA da aplicação, além do Cluster Autoscaler.

## Repositórios envolvidos

O ambiente completo é composto por quatro repositórios, que devem ficar como
pastas irmãs (mesmo diretório pai) para os scripts de automação funcionarem:

```
Projetos/
  tech-challenge-infra-k8s/        (este repositório: rede, EKS, gateway, scripts)
  tech-challenge-infra-database/   (RDS, depende do state de rede)
  tech-challenge-lambda-auth/      (funções Lambda de autenticação e authorizer)
  tech-challenge-oficina-mecanica/ (código da API, Dockerfile)
```

## Estrutura

```
tech-challenge-infra-k8s/
  bootstrap/
    main.tf              # bucket S3 (state) + tabela DynamoDB (lock)
  infra/
    main.tf
    variables.tf
    outputs.tf
    versions.tf
    authorizer.tf        # Lambda Authorizer (JWT)
    sns.tf
    alarms.tf
    vpc-endpoints.tf
    inventories/
      dev/terraform.tfvars
      hom/terraform.tfvars
      prod/terraform.tfvars
  k8s/
    nuvem/
      namespace.yaml
      kustomization.yaml
    cluster-autoscaler/
  scripts/
    sobe-tudo.sh
    derruba-tudo.sh
    comum.sh
```

## Ambientes

O projeto usa um cluster EKS por ambiente (ou nenhum, se `criar_cluster` for
`false` no `tfvars`), separados por conta/prefixo de recursos.

| Ambiente     | Arquivo tfvars                | Prefixo dos recursos      |
|--------------|--------------------------------|----------------------------|
| Desenvolvimento | `inventories/dev/terraform.tfvars`  | `tc-grupo160-*-dev`  |
| Homologação  | `inventories/hom/terraform.tfvars`  | `tc-grupo160-*-hom`  |
| Produção (simulada) | `inventories/prod/terraform.tfvars` | `tc-grupo160-*-prod` |

Cada membro do grupo usa sua própria conta do AWS Academy Learner Lab. O nome
do bucket de state carrega o ID da conta (`tc-grupo160-tfstate-<account-id>`),
então trocar de credencial e rodar os scripts de novo constrói o ambiente do
zero em outra conta, sem conflito.

## Pré-requisitos

Instale e valide as ferramentas abaixo:

```bash
aws --version
terraform version
kubectl version --client
docker version
docker info
dotnet --version
```

- **AWS CLI** configurado com a credencial do Learner Lab (`aws configure` ou
  variáveis de ambiente `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_SESSION_TOKEN`). A sessão do Academy Lab expira em algumas horas —
  renove pelo painel "AWS Details" quando comandos começarem a falhar por
  token expirado.
- **Docker Desktop precisa estar em execução** antes de rodar o script
  completo — ele é usado para build e push da imagem da API para o ECR (não
  há mais `kind load`, a imagem vai para um registro remoto).
- **.NET SDK + Amazon.Lambda.Tools** para publicar as funções Lambda:
  ```bash
  dotnet tool install -g Amazon.Lambda.Tools
  ```
  Se o projeto Lambda não tiver `aws-lambda-tools-defaults.json` com o
  runtime definido, o comando `dotnet lambda deploy-function` pode pedir o
  runtime interativamente (`Enter Runtime:`) — rode manualmente uma vez fora
  do script para responder o prompt antes de depender da automação.
- **GitHub CLI (`gh`)**, opcional — usado pelos scripts para manter a
  variável `TF_STATE_BUCKET` sincronizada nos quatro repositórios da
  organização.

## Subindo o ambiente completo

A partir da raiz do repositório `tech-challenge-infra-k8s`:

```bash
./scripts/sobe-tudo.sh                      # ambiente dev
./scripts/sobe-tudo.sh --ambiente hom       # outro ambiente
./scripts/sobe-tudo.sh --so-infra           # só infraestrutura, sem publicar a app
./scripts/sobe-tudo.sh --sim                # não pergunta nada (sem confirmação de custo)
./scripts/sobe-tudo.sh --assumir-pipelines  # aponta as pipelines dos 4 repos para a sua conta
```

O script roda, em ordem:

1. **Backend de state** — cria bucket S3 + tabela DynamoDB (via `bootstrap/`),
   ou reaproveita se já existir na conta atual;
2. **Funções Lambda (código)** — publica auth e authorizer antes da rede,
   porque o API Gateway exige que a função já exista para criar a permissão
   de invocação;
3. **Rede, cluster, ECR, gateway e balanceador** — aplica `infra/` com o
   `tfvars` do ambiente escolhido;
4. **Banco de dados gerenciado** — aplica `tech-challenge-infra-database`,
   que lê `vpc_id`/subnets/security group do state de rede;
5. **Conferência** — lê os outputs (`gateway_url`, `cluster_nome`). Se
   `criar_cluster=false` no `tfvars`, o script para aqui;
6. **Rede e variáveis das funções** — injeta `JWT_SECRET_ID`, `DB_SECRET_ID`
   e a config de VPC nas Lambdas (a função de auth entra na VPC para
   alcançar o RDS; o authorizer fica fora, sem custo de ENI/cold start);
7. **API no cluster** — build/push da imagem para o ECR, aplica os
   manifests via Kustomize (overlay `nuvem`), cria o Secret a partir do
   Secrets Manager e sobe o Cluster Autoscaler;
8. **Teste de fumaça** — `POST /auth` no gateway, esperando `200`.

### Custos enquanto o ambiente estiver de pé

| Recurso        | Custo aproximado                          |
|-----------------|-------------------------------------------|
| Cluster EKS     | ~US$ 0,10/h — **não é suspenso** junto com a sessão do lab |
| NAT Gateway     | ~US$ 1,08/dia |
| RDS multi-AZ    | ~US$ 0,90/dia |
| ALB             | ~US$ 0,54/dia |

Total aproximado: **~US$ 3,50/dia por ambiente**. Rode
`./scripts/derruba-tudo.sh` ao terminar de usar.

## Derrubando o ambiente

```bash
./scripts/derruba-tudo.sh --ambiente dev
```

O `destroy` do EKS não é automático fora deste script — o cluster continua
cobrando mesmo que sua sessão do Learner Lab termine, então **sempre derrube
explicitamente** ao final do uso.

## State remoto

Diferente do modelo local (Fase 2), o state agora é remoto, no bucket S3
criado por `bootstrap/`:

```
s3://tc-grupo160-tfstate-<account-id>/
  dev/rede.tfstate
  dev/banco.tfstate
  hom/rede.tfstate
  hom/banco.tfstate
  prod/rede.tfstate
  prod/banco.tfstate
```

O state do **bootstrap** em si continua local (`bootstrap/terraform.tfstate`),
fora do Git — ele não pode viver no bucket que ele mesmo cria. Se esse
arquivo local apontar para uma conta diferente da atual, o script move para
`.antigo-<timestamp>` automaticamente antes de recriar.

A variável `TF_STATE_BUCKET`, usada pelas pipelines dos quatro repositórios,
é sincronizada pelo `sobe-tudo.sh` via `gh variable set` — com proteção
contra dois membros do grupo sobrescreverem a conta um do outro sem querer
(veja `--assumir-pipelines` acima).

## Problemas comuns

### `AccessDenied: ... GetBucketObjectLockConfiguration ... explicit deny in a service control policy`

O SCP do Learner Lab bloqueia essa chamada, que o provider da AWS faz sempre
que cria ou atualiza um `aws_s3_bucket`. Por isso o bootstrap roda com
`-refresh=false` quando o bucket já existe — isso evita a chamada **desde
que o recurso já esteja no state sem nenhuma mudança pendente**. Se o
recurso ficar marcado como `tainted` (por exemplo, depois de uma falha
parcial anterior), o Terraform vai tentar recriar o bucket e cair no mesmo
erro. Solução:

```bash
terraform -chdir=bootstrap untaint aws_s3_bucket.tfstate
terraform -chdir=bootstrap plan -refresh=false   # deve mostrar "no changes" pro bucket
terraform -chdir=bootstrap apply -auto-approve -input=false -refresh=false
```

### `Resource already managed by Terraform` ao tentar `terraform import`

Se o `import` falhar com essa mensagem, o recurso **já está** no state —
não precisa importar. O problema provável é outro (veja o item de
`tainted` acima).

### Docker Desktop não conectado

```
ERROR: failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine
```

Abra o Docker Desktop e espere ele terminar de inicializar antes de rodar o
script (etapa 7 depende dele para build/push da imagem no ECR).

### `dotnet lambda deploy-function` trava sem nenhuma saída

Se o processo ficar parado sem imprimir nada, é provável que ele tenha
entrado em modo interativo (`Enter Runtime:`) e esteja esperando um input
que o script não fornece (a saída vai para `/dev/null`). Rode o comando
manualmente, fora do script, apontando para a pasta correta do projeto
(caminho relativo à raiz onde os 4 repositórios estão lado a lado) para ver
o prompt e resolver o `aws-lambda-tools-defaults.json` do projeto.

### `node(s) already exist` / cluster órfão

Não se aplica mais neste modelo (não há mais Kind local). Se o cluster EKS
ficar inconsistente com o state, use `terraform plan` em `infra/` para
identificar a divergência antes de qualquer `destroy` manual — destruir um
EKS fora do Terraform pode deixar ENIs e Load Balancers órfãos, ainda
cobrando.

### As pipelines apontam para outra conta

Mensagem do script:

```
As pipelines apontam para OUTRA conta.
```

Significa que outro integrante do grupo já configurou `TF_STATE_BUCKET` para
a conta dele. Sua execução local não é afetada, mas os merges do time
continuam aplicando na conta de quem configurou antes. Combine com o time
antes de usar `--assumir-pipelines`.

## Validações úteis

```bash
# Formatação e validação Terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate

# Cluster e aplicação
aws eks update-kubeconfig --region us-east-1 --name <cluster_nome>
kubectl get nodes
kubectl get all -n oficina-mecanica
kubectl get hpa -n oficina-mecanica
kubectl logs -n oficina-mecanica deployment/oficina-mecanica-api

# Secrets
kubectl get secrets -n oficina-mecanica
aws secretsmanager get-secret-value --secret-id tc-grupo160/dev/banco

# Gateway e Lambdas
curl -X POST "$GATEWAY/auth" -H 'Content-Type: application/json' \
  -d '{"documento":"000.000.000-00"}'
aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'tc-grupo160')].FunctionName"
```
