# tech-challenge-infra-k8s

Infraestrutura como código do projeto — Tech Challenge SOAT, Fase 3.

> Este README substitui a versão anterior, que ainda descrevia o fluxo local
> com Kind (Fase 2). O Terraform já evoluiu para provisionar recursos reais
> no AWS Academy Learner Lab; este documento descreve o que existe hoje.

## Papel desta camada

O Terraform provisiona a infraestrutura AWS do projeto:

- Rede (VPC, subnets públicas e privadas, Internet Gateway, NAT Gateway);
- API Gateway (HTTP API), com Lambda Authorizer nas rotas protegidas;
- Cluster Kubernetes gerenciado (EKS), opcional e sob feature flag, por custo;
- Registro de imagens (ECR);
- Segredos (Secrets Manager) — chave de assinatura do JWT;
- Notificações e alertas (SNS + CloudWatch Alarms).

O banco de dados fica no repositório
[tech-challenge-infra-database](https://github.com/tech-challenge-grupo-160/tech-challenge-infra-database).
A Lambda de autenticação e o authorizer JWT são publicados pelo repositório
[tech-challenge-lambda-auth](https://github.com/tech-challenge-grupo-160/tech-challenge-lambda-auth).
Os manifests Kubernetes da aplicação ficam em `../k8s` (overlay de nuvem) e
`../k8s-local` (fluxo Kind, mantido só para desenvolvimento sem custo — ver
issue #65 sobre sua eventual aposentadoria).

## Por que o desenho é assim: AWS Academy Learner Lab

Este projeto roda no Learner Lab, não em uma conta AWS própria. Isso impõe
restrições reais que moldam várias decisões abaixo — documentadas na RFC-0001
e repetidas nos comentários do código onde se aplicam:

- **Sem IAM customizado.** O Lab bloqueia `iam:CreateRole` e
  `iam:CreatePolicy`. A única role disponível é a `LabRole`, compartilhada por
  Lambda, cluster e pipelines — referenciada via `data "aws_iam_role" "lab"`,
  nunca criada. Isso significa que **least-privilege por componente e IRSA
  (IAM Roles for Service Accounts) não são viáveis aqui**: o desenho correto
  fica documentado em comentário (ver `secrets.tf`) para constar, mas não é
  aplicável neste ambiente.
- **Sessão com tempo limitado e sem suspensão automática do control plane.**
  O EKS cobra US$ 0,10/hora enquanto existir, diferente das instâncias EC2 que
  o Lab suspende com a sessão. Por isso o cluster nasce **desligado por
  padrão** (`criar_cluster = false`), ligado manualmente quando necessário, e
  a disciplina esperada é destruir ao fim de cada sessão de trabalho.
- **Região fixa** (`us-east-1`) e nomes com o id da conta no bucket de state
  (este repositório é público).

## Estrutura

```text
infra/
├── versions.tf            # providers e backend S3 (configurado via -backend-config)
├── variables.tf            # variáveis gerais do módulo
├── data.tf                 # data sources: caller identity, AZs, LabRole
├── rede.tf                 # VPC, subnets públicas/privadas, route tables
├── nat.tf                  # NAT Gateway (só com criar_cluster = true)
├── security-groups.tf      # security groups (ALB, nodes, banco, Lambda)
├── vpc-endpoints.tf         # endpoint de interface do Secrets Manager
├── api-gateway.tf           # HTTP API, rota /auth, VPC Link para o cluster
├── authorizer.tf             # Lambda Authorizer que valida o JWT nas rotas protegidas
├── cluster.tf                # EKS, node group, addon de metrics-server
├── ecr.tf                    # registro de imagens da API
├── secrets.tf                 # chave de assinatura do JWT no Secrets Manager
├── sns.tf                     # tópicos de notificação e alertas
├── alarms.tf                  # CloudWatch Alarms sobre o API Gateway
├── outputs.tf
└── inventories/
    ├── dev/terraform.tfvars
    ├── hom/terraform.tfvars
    └── prod/terraform.tfvars
```

## O que cada peça resolve, dos requisitos do desafio

| Requisito do desafio | Onde |
|---|---|
| API Gateway para controle e roteamento | `api-gateway.tf` |
| Proteger rotas sensíveis com autenticação | `authorizer.tf` (Lambda Authorizer validando o JWT em `ANY /api/v1/{proxy+}`) |
| Function serverless de autenticação por CPF | Integrada em `api-gateway.tf`, código no repositório `tech-challenge-lambda-auth` |
| Cluster Kubernetes com escalabilidade | `cluster.tf` (EKS + node group com `min_size`/`max_size`) |
| Terraform para provisionamento | Todo este repositório |
| Solução serverless para notificações | `sns.tf` (SNS, totalmente gerenciado) |
| Alertas para falhas no processamento | `alarms.tf` (CloudWatch Alarms → SNS) |

## Pré-requisitos

- Credenciais do AWS Academy Learner Lab ativas (`aws configure` ou variáveis
  `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` — o Lab usa
  credenciais temporárias, que expiram com a sessão).
- Terraform >= 1.9.
- `kubectl`, se for aplicar os manifests com o cluster ligado.

## Execução

```bash
cd infra
terraform init -backend-config="bucket=<bucket-do-bootstrap>" -backend-config="key=infra-k8s/dev/terraform.tfstate"
terraform plan -var-file="inventories/dev/terraform.tfvars"
terraform apply -var-file="inventories/dev/terraform.tfvars"
```

Para ligar o cluster (fora do padrão, por custo — ver seção acima), edite
`criar_cluster = true` em `inventories/dev/terraform.tfvars` antes do apply.

Depois do apply com cluster ligado:

```bash
$(terraform output -raw cluster_kubeconfig_comando)
kubectl apply -k ../k8s
```

Para receber e-mails de teste dos tópicos SNS (opcional, útil para a gravação
do vídeo de demonstração), defina `notification_email` no `.tfvars` do
ambiente e confirme a assinatura no e-mail que a AWS envia.

### Destruir ao final da sessão

```bash
terraform destroy -var-file="inventories/dev/terraform.tfvars"
```

A RFC-0001 pede isso ao fim de cada sessão de trabalho — o Learner Lab não
suspende o EKS junto com a sessão.

## Limitações conhecidas (documentadas para constar na entrega)

- **Least-privilege por componente não é aplicável neste ambiente.** A
  política ideal (uma role por consumidor do segredo JWT, restrita ao ARN
  específico) está comentada em `secrets.tf` para registro; a `LabRole`
  compartilhada é a única opção viável no Learner Lab.
- **Security group dos nodes não se aplica às instâncias reais.** Um node
  group gerenciado sem launch template recebe apenas o security group que o
  próprio EKS cria (`eks-cluster-sg-<cluster>`), não o `aws_security_group.nodes`
  deste repositório. As regras que dependem de acesso real dos nodes
  referenciam `cluster_security_group_id` diretamente (ver `banco_dos_nodes_eks`
  em `cluster.tf` e `endpoints_dos_nodes_eks` em `vpc-endpoints.tf`). O caminho
  estruturalmente correto — um launch template só para anexar o security group
  às instâncias — fica registrado como próximo passo; não foi adotado agora
  pelas arestas próprias de AMI e user data.
