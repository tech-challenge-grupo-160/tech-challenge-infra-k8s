# Terraform — Cluster Kubernetes local com kind

Scripts Terraform para provisionar um cluster Kubernetes local usando
**kind** (Kubernetes in Docker), sem necessidade de conta em nenhum cloud.

## Estrutura dos arquivos

```text
terraform/
├── versions.tf              # Providers e versões mínimas exigidas
├── variables.tf             # Variáveis configuráveis (nome, portas, réplicas)
├── main.tf                  # Cluster kind + namespace + metrics-server
├── outputs.tf               # Valores exportados após o apply
├── terraform.tfvars.example # Template para suas configurações locais
└── .gitignore               # Exclui state e credenciais do Git
```

## Pré-requisitos

Você precisa de **três ferramentas** instaladas no Windows (todas gratuitas):

### 1. Docker Desktop
Já deve estar instalado (você já usa `docker-compose`). Confirme com:
```bash
docker --version
```

### 2. Terraform

Baixe o instalador para Windows em: https://developer.hashicorp.com/terraform/install

Ou instale via **winget** (recomendado, já vem no Windows 11):
```powershell
winget install HashiCorp.Terraform
```

Confirme:
```bash
terraform --version
# Deve mostrar >= 1.6.0
```

### 3. kind

Baixe o binário para Windows em: https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries

Ou instale via **winget**:
```powershell
winget install Kubernetes.kind
```

Confirme:
```bash
kind --version
```

> **Nota**: o `kubectl` você já tem instalado (ficou evidente nos erros anteriores).

---

## Como executar
 **instale**

winget install HashiCorp.Terraform

winget install Kubernetes.kind

**Acesse a pasta infra/ do projeto**
cd infra

terraform init

terraform apply -var-file="inventories/dev/terraform.tfvars"

**volte para a raiz do projeto**
cd ..

docker build -f docker/backend/Dockerfile -t oficina-mecanica-api:local .

**Em seguida:**

kind load docker-image oficina-mecanica-api:local --name oficina-mecanica

**Aplicar o kubernets**

kubectl apply -k k8s/

kubectl rollout restart deployment/oficina-mecanica-api -n oficina-mecanica

**Espere até ficar running**

kubectl get pods -n oficina-mecanica -w

**Expor endpoint se maquina windows** 

kubectl port-forward -n oficina-mecanica svc/oficina-mecanica-api 8080:80

Esses são os endpoints disponiveis
http://localhost:8080/health    # health check

http://localhost:8080/swagger   # documentacao

POST http://localhost:8080/api/v1/auth/login
  body: { "username": "admin", "password": "admin123" }

**Para destruir**

cd infra

terraform destroy -var-file="inventories/dev/terraform.tfvars"
