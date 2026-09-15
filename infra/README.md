# infra/

Terraform da AWS: rede, EKS com Cluster Autoscaler, ECR, ALB interno, API
Gateway com authorizer, segredos e Datadog Agent. O mesmo código serve os três
ambientes, cada um com seu inventory e seu state:

| Ambiente | Inventory | State |
|---|---|---|
| `dev` | `inventories/dev/terraform.tfvars` | `s3://tc-grupo160-tfstate-<id-da-conta>/dev/rede.tfstate` |
| `hom` | `inventories/hom/terraform.tfvars` | `s3://tc-grupo160-tfstate-<id-da-conta>/hom/rede.tfstate` |
| `prod` | `inventories/prod/terraform.tfvars` | `s3://tc-grupo160-tfstate-<id-da-conta>/prod/rede.tfstate` |

> Até 15/09 este arquivo descrevia o cluster **kind** com runner self-hosted da
> Fase 2. Nada disso roda mais aqui: o kind mora em [`../local/`](../local/README.md),
> só para desenvolvimento, e nenhum pipeline o usa desde 04/09.

## Subir e derrubar um ambiente

Use os scripts do repositório principal. Eles aplicam este Terraform na ordem
certa junto com o banco, as Lambdas e a API, e no fim conferem o que ficou
cobrando. A partir da raiz deste repositório:

```bash
bash ../tech-challenge-oficina-mecanica/scripts/sobe-tudo.sh --ambiente dev
```

```bash
bash ../tech-challenge-oficina-mecanica/scripts/derruba-tudo.sh --ambiente dev
```

Pré-requisitos, tempos e o que fazer quando dá errado estão em
[CICLO-DE-VIDA.md](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/develop/docs/CICLO-DE-VIDA.md).

## Pelas pipelines

| Evento | O que acontece |
|---|---|
| PR | `fmt`, `validate` e plan real nos três ambientes, comentado no PR |
| push em `develop` | apply do `dev` |
| push em `homolog` | apply do `hom` |
| push em `main` | apply do `prod` |
| `workflow_dispatch` | apply do ambiente escolhido no input |

## Terraform direto

Para mexer neste repositório com o ambiente já de pé na sua conta. A partir
desta pasta:

```bash
CONTA="$(aws sts get-caller-identity --query Account --output text)"
terraform init -reconfigure \
  -backend-config="bucket=tc-grupo160-tfstate-${CONTA}" \
  -backend-config="key=dev/rede.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=tc-grupo160-tflock"
export TF_VAR_datadog_api_key="<chave da organizacao>"
terraform plan -var-file=inventories/dev/terraform.tfvars
```

Três cuidados:

- **Chave do Datadog.** Os três inventories ligam o Datadog. Sem
  `TF_VAR_datadog_api_key`, vale o padrão, que é uma chave falsa: o Agent recebe
  403 e o Helm estoura o timeout de 15 minutos. Onde conseguir a chave está no
  [README](../README.md#onde-conseguir-a-chave).
- **Lambdas antes do gateway.** `lambdas_publicadas` é `true` por padrão. Numa
  conta sem as funções publicadas, o apply falha com 404 no `AddPermission`:
  aplique com `-var='lambdas_publicadas=false'`, publique as funções e aplique
  de novo **sem** a variável. Se ficar em `false`, o gateway perde a permissão de
  invocar as Lambdas e o `POST /auth` passa a responder 500.
- **Nada de apply junto com a pipeline.** Plan e apply pegam o lock do state, e
  o Terraform não espera: quem chega depois falha na hora. Não aplique um
  ambiente enquanto um push ou um PR estiver rodando a pipeline dele.

## Validações sem AWS

```bash
terraform fmt -check -recursive
```

```bash
terraform init -backend=false && terraform validate
```
