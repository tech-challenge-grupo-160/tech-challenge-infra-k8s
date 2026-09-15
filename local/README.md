# Ambiente de desenvolvimento local com kind

Cluster Kubernetes em contêiner, na sua máquina. **Só para desenvolvimento.**

Nenhum pipeline usa isto. O deploy de verdade — `dev`, `hom` e `prod` — vai para o EKS, pelo `infra/` deste repositório. Até 04/09 existiam dois workflows publicando aqui por runner self-hosted; foram aposentados na [#65](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/65).

## Para que serve

Para testar os manifests antes de mandá-los para a nuvem. Um `kubectl apply -k ../k8s` aqui pega erro de YAML, de probe e de configuração em segundos, sem cluster EKS de US$ 0,10/hora e sem esperar 15 minutos de apply.

**Se você só quer rodar a API**, não precisa disto: o `docker-compose.yml` do repositório principal sobe API e Postgres direto, e é bem mais rápido. O kind serve quando o que você está mexendo é o Kubernetes em si.

## Pré-requisitos

Docker Desktop, Terraform >= 1.6, kubectl e o binário do `kind`.

## Subir

```bash
terraform init
```

```bash
terraform apply
```

Cria o cluster (1 control plane, 2 workers), o namespace, e instala o metrics-server — sem ele o HPA fica em `<unknown>` e não escala.

Depois, os manifests do fluxo local:

```bash
kubectl apply -k ../k8s
```

Esse kustomization inclui `postgres/`, ao contrário do overlay `../k8s/nuvem`. É a diferença que importa entre os dois: aqui o banco roda **dentro** do cluster; na nuvem ele é o RDS gerenciado.

## Derrubar

```bash
terraform destroy
```

Não há custo em deixar de pé além da memória da sua máquina — mas o cluster continua consumindo RAM do Docker Desktop depois que você esquece dele.

## Problemas comuns

O state é local — fica em `local/terraform.tfstate`, fora do Git. Os dois erros
abaixo são as duas metades do mesmo problema: state e cluster saírem de sincronia
porque um dos dois foi mexido por fora.

### `node(s) already exist for a cluster with the name "oficina-mecanica"`

O cluster existe, o Terraform não sabe. Apague os dois e comece de novo:

```bash
kind delete cluster --name oficina-mecanica && rm -f terraform.tfstate terraform.tfstate.backup && terraform init -reconfigure && terraform apply
```

### `could not locate any control plane nodes for cluster named 'oficina-mecanica'`

O inverso: o state existe, o cluster não. Só o state precisa sair:

```bash
rm -f terraform.tfstate terraform.tfstate.backup && terraform init -reconfigure && terraform apply
```

### HPA em `<unknown>`

O metrics-server leva alguns minutos para expor métricas depois que o cluster
sobe. Antes de investigar, confirme que ele já responde:

```bash
kubectl top nodes && kubectl get hpa -n oficina-mecanica
```

Se `kubectl top` também não responder depois de alguns minutos, o problema é o
metrics-server, não o HPA — aqui ele é instalado por um `local-exec` com
`--kubelet-insecure-tls`, necessário porque os certificados do kubelet no kind
não são assinados por uma CA que ele reconheça.

## Validações antes de abrir PR

```bash
terraform fmt -check -recursive && terraform init -backend=false && terraform validate
```

Render dos manifests, sem aplicar nada:

```bash
kubectl kustomize ../k8s
```

## Uma inconsistência proposital com o `infra/`

Aqui o namespace é criado **por Terraform**, com `kubernetes_namespace`. Na nuvem ele nasce de um manifest, e a [#60](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/60) registra por quê: configurar um provider a partir de um recurso da mesma configuração é antipattern do Terraform — o endpoint do cluster é *unknown* no primeiro apply, e quebra na criação e no destroy.

O mesmo antipattern está neste arquivo, e é tolerável aqui pelo que este ambiente é: descartável, de uma máquina só, recriado do zero quando dá errado. Quando o `terraform destroy` tropeça no namespace, a saída é `kind delete cluster` e começar de novo — coisa que não existe como opção em `prod`.

Fica registrado para ninguém copiar o padrão daqui para o `infra/` achando que está seguindo o exemplo da casa.

## Versão do Kubernetes

`var.kubernetes_version` está em `v1.31.0`, enquanto o EKS roda **1.33**. Divergência conhecida: o node image do kind é publicado por release do projeto e nem sempre acompanha a versão do EKS. Para o que este ambiente faz — validar YAML e comportamento de manifest — a diferença não aparece. Se for testar API do Kubernetes que mudou entre as duas, ajuste a variável antes de tirar conclusão.
