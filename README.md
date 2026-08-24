# tech-challenge-infra-k8s

Infraestrutura como código do cluster Kubernetes — Tech Challenge SOAT, Fase 3.

## Propósito

Provisiona, via Terraform, a rede e o cluster Kubernetes onde a API roda, além dos manifests da aplicação.

Responsabilidades deste repositório:

- Rede base (VPC, subnets públicas e privadas, security groups)
- Cluster Kubernetes gerenciado com node group escalável
- Manifests da API e do HPA
- Ingress e TLS

O banco de dados fica em [tech-challenge-infra-database](https://github.com/tech-challenge-grupo-160/tech-challenge-infra-database). A imagem da API é construída na [aplicação principal](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica).

## Status

> ⚠️ **Em migração.** A rede AWS (VPC, subnets, security groups) já está aqui. O cluster ainda não: é a issue [#60](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/60). O provisionamento do cluster `kind` da Fase 2 foi removido — o deploy agora é na AWS.

## Estrutura

```text
infra/
├── rede.tf                   # VPC, subnets, internet gateway e rotas
├── security-groups.tf        # SGs de ALB, nodes, banco e Lambda
├── data.tf                   # LabRole e zonas de disponibilidade
├── variables.tf
├── versions.tf
├── outputs.tf
└── inventories/
    ├── dev/terraform.tfvars
    ├── hom/terraform.tfvars
    └── prod/terraform.tfvars

k8s/
├── kustomization.yaml
├── api/                      # configmap, deployment, service, hpa
└── postgres/                 # sai daqui quando o banco gerenciado entrar (issue #62)
```

## Tecnologias

| Item | Definição |
|---|---|
| IaC | Terraform |
| Orquestração | Kubernetes |
| Manifests | Kustomize |
| Nuvem | A definir — RFC [#56](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/56) |

## Escalabilidade

O HPA em `k8s/api/hpa.yaml` escala a API entre **2 e 10 réplicas**, com alvo de 70% de CPU e 75% de memória. A revisão desses limiares para o cluster gerenciado é a ADR [#63](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/63).

## Execução

```bash
cd infra
terraform init
terraform plan -var-file=inventories/dev/terraform.tfvars
```

Aplicar os manifests:

```bash
kubectl apply -k k8s/
```

## Deploy

Pipeline em GitHub Actions ([issue #51](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/51)):

| Evento | Ação |
|---|---|
| Pull Request | `fmt`, `validate` e `plan` publicado como comentário no PR |
| Merge em `homolog` | `apply` no ambiente de homologação |
| Merge em `main` | `apply` no ambiente de produção |

Autenticação por OIDC ([issue #54](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/54)) — sem credencial estática.

## Arquitetura

Diagrama da arquitetura na nuvem em [docs/diagrams](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/master/docs/diagrams) no repositório principal.

## Repositórios do projeto

| Repositório | Conteúdo |
|---|---|
| [tech-challenge-oficina-mecanica](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica) | API .NET e documentação |
| [tech-challenge-lambda-auth](https://github.com/tech-challenge-grupo-160/tech-challenge-lambda-auth) | Function serverless de autenticação |
| [tech-challenge-infra-k8s](https://github.com/tech-challenge-grupo-160/tech-challenge-infra-k8s) | Este repositório |
| [tech-challenge-infra-database](https://github.com/tech-challenge-grupo-160/tech-challenge-infra-database) | Terraform do banco gerenciado |

## Contribuição

Branch `main` protegida — sem commits diretos. Toda mudança entra por Pull Request com pelo menos uma aprovação.
