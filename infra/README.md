# Infraestrutura local com Terraform e Kind

Esta pasta concentra a definicao de infraestrutura como codigo do projeto. O objetivo e provisionar localmente um cluster Kubernetes usando Kind, sem depender de cloud, para demonstrar o fluxo de CI/CD da Fase 2 do Tech Challenge.

## Papel desta camada

O Terraform e responsavel por criar os recursos base do ambiente:

- cluster Kubernetes local via Kind;
- namespace da aplicacao;
- secrets da API e do PostgreSQL;
- metrics-server, usado pelo HPA para obter metricas de CPU/memoria.

Os manifests da aplicacao ficam fora desta pasta, em `../k8s`. A partir da raiz do projeto, eles sao aplicados com:

```powershell
kubectl apply -k k8s
```

Essa separacao evita duplicidade de responsabilidade:

- `infra`: cria infraestrutura base e configuracoes sensiveis;
- `k8s`: define Deployments, Services, ConfigMaps, PVC e HPA da aplicacao.

## Estrutura

```text
infra/
  main.tf
  variables.tf
  outputs.tf
  versions.tf
  inventories/
    dev/
      terraform.tfvars
    hom/
      terraform.tfvars
    prod/
      terraform.tfvars
```

## Ambientes

O projeto usa o mesmo cluster Kind local e separa os ambientes por namespace.

| Ambiente | Arquivo tfvars | Namespace |
| --- | --- | --- |
| Desenvolvimento local | `inventories/dev/terraform.tfvars` | `oficina-mecanica` |
| Homologacao | `inventories/hom/terraform.tfvars` | `oficina-mecanica-homolog` |
| Producao simulada | `inventories/prod/terraform.tfvars` | `oficina-mecanica-prod` |

No fluxo de CI/CD, a branch `homolog` publica no namespace `oficina-mecanica-homolog` usando o self-hosted runner local.

## Pre-requisitos

Instale e valide as ferramentas abaixo:

```powershell
docker version
docker info
terraform version
kind version
kubectl version --client
```

No Windows, uma forma simples de instalar Terraform e Kind e:

```powershell
winget install HashiCorp.Terraform
winget install Kubernetes.kind
```

O Docker Desktop precisa estar em execucao.

## Subir ambiente local de desenvolvimento

A partir da raiz do projeto:

```powershell
cd D:\Dev\FIAP\tech-challenge-grupo-160\tech-challenge-oficina-mecanica
```

Inicialize e aplique o Terraform:

```powershell
cd infra
terraform init -reconfigure
terraform apply -var-file="inventories/dev/terraform.tfvars"
```

Quando solicitado, digite:

```text
yes
```

Depois volte para a raiz, gere a imagem da API e carregue-a no Kind:

```powershell
cd ..
docker build -f docker/backend/Dockerfile -t oficina-mecanica-api:local .
kind load docker-image oficina-mecanica-api:local --name oficina-mecanica
```

Aplique os manifests Kubernetes:

```powershell
kubectl apply -k k8s
```

Valide os recursos:

```powershell
kubectl get nodes
kubectl get namespaces
kubectl get all -n oficina-mecanica
```

Exponha a API localmente:

```powershell
kubectl port-forward -n oficina-mecanica svc/oficina-mecanica-api 8080:80
```

Acesse:

```text
http://localhost:8080/swagger
http://localhost:8080/health
```

## Deploy local de homologacao via GitHub Actions

O workflow de homologacao usa self-hosted runner local. Apos merge/push na branch `homolog`, o job de CD executa na maquina registrada como runner e aplica o ambiente usando:

```powershell
terraform apply -auto-approve -var-file="inventories/hom/terraform.tfvars"
```

Em seguida, o workflow:

1. gera a imagem Docker da API;
2. carrega a imagem no cluster Kind;
3. ajusta o namespace do `k8s/kustomization.yaml` para `oficina-mecanica-homolog`;
4. aplica os manifests Kubernetes;
5. aguarda o rollout da API;
6. executa health check por `port-forward`.

Para validar apos o CD:

```powershell
kind get clusters
kubectl get all -n oficina-mecanica-homolog
kubectl get pods -n oficina-mecanica-homolog
kubectl get hpa -n oficina-mecanica-homolog
```

Para acessar a API de homologacao:

```powershell
kubectl port-forward -n oficina-mecanica-homolog svc/oficina-mecanica-api 8080:80
```

## State local do Terraform

Por padrao, o Terraform usa backend local.

Para execucao manual em `dev`, o state fica em:

```text
infra/terraform.tfstate
```

Nos workflows de CD, os states sao separados fora do checkout:

```text
D:\terraform-state\oficina-mecanica\homolog.tfstate
D:\terraform-state\oficina-mecanica\prod.tfstate
```

Isso evita misturar o state local de desenvolvimento com os ambientes simulados pelo self-hosted runner.

## Destruir ambiente local

Preferencialmente destrua com Terraform:

```powershell
cd infra
terraform destroy -var-file="inventories/dev/terraform.tfvars"
```

Se o cluster tiver sido removido manualmente ou o state tiver ficado inconsistente, use a limpeza forcada:

```powershell
cd D:\Dev\FIAP\tech-challenge-grupo-160\tech-challenge-oficina-mecanica
kind delete cluster --name oficina-mecanica
Remove-Item .\infra\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item .\infra\terraform.tfstate.backup -ErrorAction SilentlyContinue
```

## Problemas comuns

### Cluster existe, mas Terraform nao tem state

Erro comum:

```text
node(s) already exist for a cluster with the name "oficina-mecanica"
```

Solucao local:

```powershell
kind delete cluster --name oficina-mecanica
Remove-Item .\infra\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item .\infra\terraform.tfstate.backup -ErrorAction SilentlyContinue
cd infra
terraform init -reconfigure
terraform apply -var-file="inventories/dev/terraform.tfvars"
```

### Terraform tem state, mas cluster foi apagado por fora

Erro comum:

```text
could not locate any control plane nodes for cluster named 'oficina-mecanica'
```

Solucao local:

```powershell
Remove-Item .\infra\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item .\infra\terraform.tfstate.backup -ErrorAction SilentlyContinue
cd infra
terraform init -reconfigure
terraform apply -var-file="inventories/dev/terraform.tfvars"
```

### HPA mostra CPU ou memoria como unknown

O metrics-server pode levar alguns minutos para expor metricas. Valide com:

```powershell
kubectl top nodes
kubectl top pods -n oficina-mecanica
kubectl get hpa -n oficina-mecanica
```

## Validacoes uteis

Formatacao:

```powershell
terraform fmt -check -recursive
```

Validacao Terraform:

```powershell
terraform init -backend=false
terraform validate
```

Render dos manifests Kubernetes:

```powershell
cd ..
kubectl kustomize k8s
```

Listar secrets criados pelo Terraform:

```powershell
kubectl get secrets -n oficina-mecanica
kubectl get secrets -n oficina-mecanica-homolog
```
