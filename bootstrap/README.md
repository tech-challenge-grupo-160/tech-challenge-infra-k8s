# Bootstrap do backend de state

Cria o bucket S3 e a tabela DynamoDB que guardam e travam o state do Terraform dos demais módulos.

## Por que este módulo é diferente

É o problema do ovo e da galinha: **não dá para guardar no bucket o state que cria o bucket**. Por isso este módulo é o único que usa **state local**, e roda **uma vez só**, manualmente.

O `.gitignore` já impede que `terraform.tfstate` seja versionado — o state contém ARNs e atributos que não devem ir para um repositório público.

## Como rodar (uma vez)

Com as credenciais da sessão do Learner Lab ativas:

```bash
cd bootstrap
terraform init
terraform apply
```

Anote as saídas:

```bash
terraform output state_bucket
terraform output lock_table
```

## Ligando os outros módulos

Os demais módulos declaram o backend vazio e recebem a configuração no `init`, para o nome do bucket — que contém o id da conta — não ficar escrito em repositório público:

```hcl
terraform {
  backend "s3" {}
}
```

O comando pronto sai em:

```bash
terraform output backend_config
```

Nos pipelines, o valor vem da variável de repositório `TF_STATE_BUCKET`:

```bash
gh variable set TF_STATE_BUCKET --body "<bucket>" --repo tech-challenge-grupo-160/tech-challenge-infra-k8s
gh variable set TF_STATE_BUCKET --body "<bucket>" --repo tech-challenge-grupo-160/tech-challenge-infra-database
```

## Custo

Desprezível. O S3 cobra por armazenamento (state tem alguns KB) e o DynamoDB está em `PAY_PER_REQUEST`, cobrando por operação de lock. Nenhum dos dois tem cobrança por hora — diferente do EKS.

## Limpeza

```bash
terraform destroy
```

O bucket tem `force_destroy = true`, então versões antigas do state não travam a remoção. **Só faça isso depois de destruir todos os outros módulos**, senão você perde o state deles.
