# tech-challenge-infra-k8s

Infraestrutura como código do cluster Kubernetes — Tech Challenge SOAT, Fase 3.

## Propósito

Provisiona, via Terraform, a rede e o cluster Kubernetes onde a API roda, além dos manifests da aplicação.

Responsabilidades deste repositório:

- Rede base (VPC, subnets públicas e privadas, NAT Gateway, security groups)
- Cluster EKS com node group em subnet privada
- API Gateway, com a rota de autenticação e o authorizer JWT
- Balanceador interno que expõe a API do cluster ao gateway
- Registry das imagens da API (ECR)
- Segredo de assinatura do JWT no Secrets Manager
- Manifests da API e do HPA

O banco de dados fica em [tech-challenge-infra-database](https://github.com/tech-challenge-grupo-160/tech-challenge-infra-database). A imagem da API é construída na [aplicação principal](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica).

## Status

O ambiente `dev` está no ar e a aplicação responde pela internet, no endpoint do
API Gateway. `hom` e `prod` têm a configuração pronta nos inventories, mas ainda
não foram aplicados.

| Componente | Estado |
|---|---|
| Rede, NAT, security groups | ✅ |
| Cluster EKS 1.33, 2 nodes privados | ✅ |
| API Gateway com authorizer JWT | ✅ |
| Balanceador interno + VPC Link | ✅ |
| ECR e deploy da API | ✅ |
| Cluster Autoscaler | ✅ manifest em `k8s/cluster-autoscaler`, descoberta por tag no ASG |

> **O cluster cobra sozinho.** O control plane do EKS custa US$ 0,10/hora
> **enquanto existir** e não é suspenso junto com a sessão do Learner Lab —
> diferente das instâncias EC2. Com NAT, balanceador e banco, um ambiente de pé
> custa cerca de **US$ 5/dia**.
>
> A variável `criar_cluster`, no inventory de cada ambiente, liga e desliga
> cluster e NAT juntos.

## Estrutura

```text
bootstrap/                    # bucket de state e tabela de lock; state local
infra/
├── rede.tf                   # VPC, subnets, internet gateway e rotas
├── nat.tf                    # NAT Gateway: a saida das subnets privadas
├── security-groups.tf        # SGs de ALB, nodes, banco, Lambda e endpoints
├── vpc-endpoints.tf          # endpoint do Secrets Manager, para a Lambda na VPC
├── cluster.tf                # EKS, node group, metrics-server e tags do autoscaler
├── ecr.tf                    # registry das imagens da API
├── alb.tf                    # balanceador interno e target group dos nodes
├── api-gateway.tf            # HTTP API, rotas e integracoes
├── authorizer.tf             # Lambda authorizer que protege /api/v1
├── secrets.tf                # chave de assinatura do JWT
├── data.tf                   # LabRole e zonas de disponibilidade
├── variables.tf
├── versions.tf
├── outputs.tf
└── inventories/
    ├── dev/terraform.tfvars
    ├── hom/terraform.tfvars
    └── prod/terraform.tfvars

local/                        # cluster kind na maquina: SO desenvolvimento, nenhum pipeline usa

k8s/
├── kustomization.yaml        # fluxo local com kind: API + PostgreSQL no cluster
├── api/                      # base compartilhada: configmap, deployment, service, hpa
├── postgres/                 # so o fluxo local com kind usa; na nuvem o banco e o RDS
├── nuvem/                    # overlay do EKS: banco no RDS, imagem do ECR
└── cluster-autoscaler/       # componente do cluster, aplicado em kube-system
```

**Dois overlays, de propósito.** A raiz serve o desenvolvimento local com `kind`
e um PostgreSQL dentro do cluster. O `nuvem/` monta a API contra o RDS
gerenciado, com a imagem do ECR e Service `NodePort` — e **não** inclui
`postgres/`, senão haveria um segundo banco, vazio, e a API conversaria com o
errado.

## Tecnologias

| Item | Definição |
|---|---|
| IaC | Terraform |
| Orquestração | Kubernetes |
| Manifests | Kustomize |
| Nuvem | AWS, região `us-east-1` — [RFC-0001](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/develop/docs/rfcs/0001-escolha-da-nuvem.md) |

## Escalabilidade

O HPA em `k8s/api/hpa.yaml` escala a API entre **2 e 10 réplicas**, com alvo de 70% de CPU e 75% de memória. Ele funciona: o `metrics-server` entra como addon gerenciado do EKS, e sem ele o HPA ficaria em `<unknown>`.

O node group tem `min_size = 2` e `max_size = 4`. Quem se move dentro desses limites é o **Cluster Autoscaler**, em `k8s/cluster-autoscaler` — um managed node group não escala sozinho, os limites apenas dizem até onde alguém *pode* ir.

Os dois trabalham em camadas diferentes, e a distinção importa: o HPA cria **pod**; quando não há node com espaço, o pod novo fica `Pending` para sempre. O autoscaler vê esse `Pending` e cria **node**. Na volta, remove o node que passou 5 minutos ocioso e cujos pods cabem em outro lugar.

Medido em `dev` em 04/09, forçando 6 pods de 900m contra dois `t3.medium`:

```
18:55:54  Estimated 2 nodes needed
18:55:54  Final scale-up plan: [2->4 (max: 4)]
18:56:35  node registrado e Ready
18:56:04  pod didn't trigger scale-up: 1 max node group size reached
```

**45 segundos** da decisão ao node pronto. Os dois pods que sobraram continuaram `Pending` de propósito: o `max_size` é 4, e o autoscaler para no teto em vez de estourar o limite — é o comportamento correto, e é o que impede uma carga anômala de consumir o crédito da conta.

A descoberta é por tag no Auto Scaling group, não por parâmetro: `infra/cluster.tf` marca o ASG com `k8s.io/cluster-autoscaler/enabled` e `k8s.io/cluster-autoscaler/<cluster>`. A segunda tag traz o nome do cluster porque os três ambientes dividem a mesma conta do Learner Lab — sem ela, o autoscaler de `dev` escalaria os nodes de `hom` e `prod` também.

Na AWS ele se autentica pela role da instância do node, a `LabRole`. O correto seria IRSA, com uma role só para o ServiceAccount, mas o Learner Lab não permite criar roles.

A revisão dos limiares é a ADR [#63](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/63).

## Execução

Para subir ou derrubar o ambiente **inteiro**, os scripts ficam no repositório
principal — eles orquestram os quatro repositórios, e nenhum dos quatro é dono
dos demais:

```bash
bash ../tech-challenge-oficina-mecanica/scripts/sobe-tudo.sh
```

```bash
bash ../tech-challenge-oficina-mecanica/scripts/derruba-tudo.sh
```

O passo a passo e a ordem de dependência estão em
[docs/CICLO-DE-VIDA.md](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/develop/docs/CICLO-DE-VIDA.md).

> **O cluster cobra sozinho.** O control plane do EKS custa US$ 0,10/hora
> enquanto existir e **não** é suspenso junto com a sessão do Learner Lab.

Para trabalhar só neste repositório, o Terraform direto:

```bash
cd infra
terraform init
terraform plan -var-file=inventories/dev/terraform.tfvars
```

Ambiente local com kind — **so desenvolvimento**, nenhum pipeline usa. O cluster sai do
`local/`, e os manifests do kustomization da raiz de `k8s/`, que inclui o PostgreSQL
dentro do cluster:

```bash
cd local && terraform init && terraform apply
```

```bash
kubectl apply -k k8s/
```

Detalhes e limitacoes em [local/README.md](local/README.md). Para so rodar a API, o
`docker-compose.yml` do repositorio principal e mais rapido.

Na nuvem o overlay é outro — usa o RDS e a imagem do ECR:

```bash
kubectl apply -k k8s/nuvem
```

## Credenciais da AWS nos pipelines

O AWS Academy Learner Lab **não permite criar provedor OIDC nem roles IAM**, então os pipelines usam as **credenciais temporárias da sessão**, cadastradas como secrets. Elas expiram junto com a sessão do lab, a cada ~4 horas.

Para renovar em todos os repositórios de uma vez — o script vive no repositório
principal desde 30/08, junto com os demais que atravessam os quatro:

```bash
bash ../tech-challenge-oficina-mecanica/scripts/renova-secrets.sh
```

Ele lê o perfil local do `~/.aws/credentials` e publica nos quatro repositórios **sem imprimir os valores em nenhum momento**.

| Comando | O que faz |
|---|---|
| `renova-secrets.sh` | Renova nos 4 repositórios |
| `renova-secrets.sh --check` | Mostra só nomes e datas dos secrets |
| `renova-secrets.sh --dry-run` | Mostra o que faria, sem alterar |

### Rodando os scripts no Windows

**Use o Git Bash.** Em máquina com WSL instalado, `bash` no PowerShell resolve para `C:\Windows\System32\bash.exe`, que é o launcher do WSL — e lá o script quebra de três formas diferentes, nenhuma delas apontando para a causa real:

| Sintoma | Causa |
|---|---|
| `$'\r': command not found` e erro de sintaxe no `do` | Checkout com CRLF. Resolvido pelo [`.gitattributes`](.gitattributes) — mas só depois de um checkout novo |
| `ERRO: 'gh' nao encontrado no PATH` | No WSL os binários do Windows aparecem como `gh.exe`; o `command -v gh` não os encontra |
| Perfil sem credenciais, mesmo com o bloco colado | **O mais traiçoeiro:** o `$HOME` do WSL é `/home/<user>`, então o script lê um `~/.aws/credentials` diferente do `C:\Users\<voce>\.aws\credentials` onde você colou o bloco |

Chamando o Git Bash explicitamente do PowerShell:

```powershell
& "C:\Program Files\Git\bin\bash.exe" ../tech-challenge-oficina-mecanica/scripts/renova-secrets.sh --dry-run
```

Mais prático: abrir o **Git Bash** direto pelo menu Iniciar. Ali `$HOME` é `C:\Users\<voce>`, e `gh`, `aws`, `terraform` e `kubectl` estão todos no PATH — `renova-secrets.sh` funciona sem prefixo.

> Se você já tinha o repositório clonado antes do `.gitattributes`, force a renormalização uma vez:
>
> ```bash
> git rm --cached -r . && git reset --hard
> ```

### Como obter as credenciais

No painel do Learner Lab: **AWS Details → AWS CLI**. Copie o bloco para o `~/.aws/credentials`, no perfil `default`.

Se as credenciais estiverem expiradas, o script avisa e orienta: **End Lab**, depois **Start Lab**, e copiar o bloco novo.

### Regra do time

**Credencial não passa por chat, e-mail ou grupo de mensagem** — nem as temporárias. Mensagem fica salva e ninguém lembra de apagar. Se uma vazar, encerre e reinicie o lab imediatamente: isso invalida a sessão na hora.

Essa limitação está registrada na [RFC-0001](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/develop/docs/rfcs/0001-escolha-da-nuvem.md) junto com o desenho correto (OIDC) que o ambiente inviabiliza.

## Deploy

Pipeline em GitHub Actions ([issue #51](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/51)):

| Evento | Ação |
|---|---|
| Pull Request | `fmt`, `validate` e `plan` nos três ambientes, publicado como comentário |
| Merge em `develop` | `apply` no ambiente de desenvolvimento |
| Merge em `homolog` | `apply` no ambiente de homologação |
| Merge em `main` | `apply` no ambiente de produção |
| `workflow_dispatch` | `apply` no ambiente escolhido, de qualquer branch |

> A `develop` aplicar o `dev` é deliberado — é o ambiente onde o time trabalha.
> A consequência é que **aplicar código de branch não mergeada não sobrevive**:
> o próximo push na `develop` reconcilia o ambiente com o que está lá e desfaz
> o que não estiver no código. Já derrubou um authorizer no meio do caminho.

Autenticação com as **credenciais temporárias da sessão** do Learner Lab, cadastradas como secrets do repositório — ver [Credenciais da AWS nos pipelines](#credenciais-da-aws-nos-pipelines).

O desenho previsto era OIDC, sem credencial estática ([issue #54](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/54)). O ambiente bloqueia `iam:CreateOpenIDConnectProvider`, o que o inviabiliza. A alternativa foi aprovada pelo professor em 24/08 e está registrada como **limitação do ambiente, não escolha de arquitetura**, na [RFC-0001](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/develop/docs/rfcs/0001-escolha-da-nuvem.md).

## Arquitetura

Diagrama da arquitetura na nuvem em [docs/diagrams](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/tree/develop/docs/diagrams) no repositório principal — em especial o `C4_04_AWS_Deployment_Diagram.puml`.

## Repositórios do projeto

| Repositório | Conteúdo |
|---|---|
| [tech-challenge-oficina-mecanica](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica) | API .NET e documentação |
| [tech-challenge-lambda-auth](https://github.com/tech-challenge-grupo-160/tech-challenge-lambda-auth) | Function serverless de autenticação |
| [tech-challenge-infra-k8s](https://github.com/tech-challenge-grupo-160/tech-challenge-infra-k8s) | Este repositório |
| [tech-challenge-infra-database](https://github.com/tech-challenge-grupo-160/tech-challenge-infra-database) | Terraform do banco gerenciado |

## Contribuição

Branch `main` protegida — sem commits diretos. Toda mudança entra por Pull Request com pelo menos uma aprovação.

## API Gateway

Porta de entrada da aplicacao, em [`infra/api-gateway.tf`](infra/api-gateway.tf). HTTP API (v2), escolhido na [RFC-0002](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/develop/docs/rfcs/0002-autenticacao-por-cpf-e-api-gateway.md).

| Rota | Destino | Publica |
|---|---|---|
| `POST /auth` | Lambda de autenticacao | Sim |
| `POST /api/v1/auth/login` | API no cluster | Sim |
| `ANY /api/v1/{proxy+}` | API no cluster | **Nao** — protegida pelo authorizer |
| `GET /health/live` | API no cluster | Sim |

A classificacao vem da [matriz de autorizacao](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/develop/docs/MATRIZ_AUTORIZACAO.md). O `/health` e o `/health/ready` **nao** sao roteados: o corpo do `/health` expoe `description` dos checks.

### O caminho ate o cluster

```text
cliente --HTTPS--> API Gateway --VPC Link--> ALB interno --> nodes:30080 --> pods
        (cert AWS)                (privado)
```

As rotas `/api/v1` existem quando existe cluster: `local.integrar_cluster`
acompanha `criar_cluster`, e o balanceador nasce junto, em `alb.tf`. Nao ha mais
variavel para preencher a mao — o output `gateway_rotas_do_cluster_ativas` diz
se elas estao no ar.

**O TLS vem do gateway, nao do balanceador.** O `execute-api` ja atende com
certificado valido da AWS. Um ALB publico exigiria certificado do ACM, que so e
emitido para dominio cuja posse se prova — ninguem valida `amazonaws.com`. Por
isso o balanceador e interno: quem fala com ele e so o gateway.

**O gateway repassa o nome do estagio no caminho.** Uma chamada a
`/dev/health/live` chegaria na API como `/dev/health/live`, que ela nao conhece,
e devolveria 404. O mapeamento `overwrite:path` com `$request.path` entrega o
caminho ja sem o estagio, e um unico mapeamento resolve as tres rotas.

### Authorizer

O `ANY /api/v1/{proxy+}` e protegido pelo Lambda authorizer de
[`infra/authorizer.tf`](infra/authorizer.tf) — formato 2.0, resposta simples,
cache de 300s.

| Requisicao | Resposta |
|---|---|
| Sem header `Authorization` | 401 |
| Token invalido ou expirado | 403 |
| Token valido | segue para o cluster |

O 403 e comportamento do HTTP API: header de identidade ausente da 401,
authorizer que recusa da 403. Forcar 401 exigiria REST API, descartado na
RFC-0002. Decisao registrada na [#43](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/43).

O motivo de cada recusa vai para o log da funcao, **nunca para a resposta**. E o
log de acesso do gateway mostra `integrationTime: "-"` nas recusas: o trafego
nao chega ao backend.

> O cache de 300s significa que um token continua sendo aceito por ate cinco
> minutos depois de expirar, servido do cache, sem a funcao ser consultada.
> `authorizer_cache_ttl` permite zerar para depuracao.

### Throttling e logs

50 req/s por rota, com rajada de 100 (`gateway_rate_limit` e `gateway_burst_limit`). Logs de acesso em CloudWatch, `/aws/apigateway/tc-grupo160-<ambiente>`, retencao de 7 dias — curta de proposito, pelo orcamento do lab.

## Segredo de assinatura do JWT

A chave HMAC que assina os tokens vive no **AWS Secrets Manager**, em
`tc-grupo160/<ambiente>/jwt-signing-key`, criada pelo Terraform em
[`infra/secrets.tf`](infra/secrets.tf). Nunca é versionada.

Três consumidores leem a mesma chave em runtime:

| Consumidor | Como recebe | Quando lê |
|---|---|---|
| Lambda de autenticação | env `JWT_SECRET_ID` com o **nome** do segredo | cold start |
| Lambda authorizer | idem | cold start |
| API .NET | config `Jwt:SecretId` com o **nome** do segredo | startup do pod |

Nenhum deles recebe o valor por variável de ambiente. Se a variável do nome não
estiver definida e não houver chave local, a inicialização **falha** — não há
valor padrão. Essa decisão é deliberada: um default em repositório público é uma
chave que qualquer pessoa lê.

### Procedimento de rotação

Rotação é **manual e com janela**. Não há duas chaves ativas ao mesmo tempo, então
todos os tokens em circulação são invalidados no momento da troca. Com expiração
de 60 minutos e sem tráfego real, o custo é aceitável nesta fase — a alternativa
sem downtime (duas chaves identificadas por `kid`) está registrada na
[RFC-0002](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/blob/develop/docs/rfcs/0002-autenticacao-por-cpf-e-api-gateway.md)
como o caminho correto, não implementado.

**1. Gerar e gravar a chave nova**

```bash
terraform -chdir=infra taint random_password.jwt_signing_key
```

```bash
terraform -chdir=infra apply -var-file=inventories/hom/terraform.tfvars
```

**2. Forçar as Lambdas a reler**

Elas leem no cold start, então basta publicar uma nova versão da configuração:

```bash
aws lambda update-function-configuration --function-name tc-grupo160-auth-hom --description "rotacao $(date +%F)"
```

**3. Reiniciar os pods da API**

Este passo é obrigatório: a API lê no startup.

```bash
kubectl rollout restart deployment/oficina-api
```

**4. Conferir**

```bash
kubectl rollout status deployment/oficina-api
```

Autentique um cliente e chame uma rota protegida. Se voltar `401`, algum
consumidor ficou para trás — quase sempre o passo 3.

> ⚠️ Executar os passos fora de ordem deixa a Lambda assinando com a chave nova
> enquanto a API ainda valida com a antiga. O sintoma é `401` em todas as rotas
> protegidas, com o login funcionando normalmente.
