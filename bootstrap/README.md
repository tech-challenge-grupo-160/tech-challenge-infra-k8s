# Bootstrap do backend de state

Cria o bucket S3 e a tabela DynamoDB que guardam e travam o state do Terraform
dos demais módulos.

## Por que não é Terraform

Era, até ser descoberto que o SCP do AWS Academy Learner Lab nega
`s3:GetBucketObjectLockConfiguration` — inclusive em conta nova, não só no
refresh de um bucket já existente. O provider `hashicorp/aws` lê essa
configuração de forma incondicional sempre que cria ou atualiza um
`aws_s3_bucket` (`resourceBucketRead`), e trata `AccessDenied` como erro fatal
em qualquer partição `aws`. Não há flag, `-refresh=false` ou downgrade de
provider que evite essa leitura.

Como o bucket e a tabela são criados uma vez e nunca mudam, a solução foi
tirá-los do Terraform. Quem cria e destrói os dois agora é o AWS CLI puro, nas
funções `garantir_backend_state` e `destruir_backend_state` de
[`scripts/comum.sh`](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/master/scripts/comum.sh)
(no repositório principal). `sobe-tudo.sh` e `derruba-tudo.sh` chamam essas
funções na etapa 1.

Esta pasta existe só para documentar essa decisão — não há mais `.tf` aqui.

## Ligando os outros módulos

Os demais módulos continuam declarando o backend vazio e recebendo a
configuração no `init`:

```hcl
terraform {
  backend "s3" {}
}
```

`tf_init`, em `scripts/comum.sh`, monta esse `init` com o nome do bucket
(que contém o id da conta, resolvido em tempo de execução por
`nome_do_bucket`) e o nome da tabela de lock (`nome_da_tabela_lock`).

Nos pipelines, o bucket vem da variável de repositório `TF_STATE_BUCKET`:

```bash
gh variable set TF_STATE_BUCKET --body "<bucket>" --repo tech-challenge-grupo-160/tech-challenge-infra-k8s
gh variable set TF_STATE_BUCKET --body "<bucket>" --repo tech-challenge-grupo-160/tech-challenge-infra-database
```

## Custo

Desprezível. O S3 cobra por armazenamento (state tem alguns KB) e o DynamoDB
está em `PAY_PER_REQUEST`, cobrando por operação de lock. Nenhum dos dois tem
cobrança por hora — diferente do EKS.
