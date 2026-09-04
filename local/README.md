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

## Uma inconsistência proposital com o `infra/`

Aqui o namespace é criado **por Terraform**, com `kubernetes_namespace`. Na nuvem ele nasce de um manifest, e a [#60](https://github.com/tech-challenge-grupo-160/tech-challenge-oficina-mecanica/issues/60) registra por quê: configurar um provider a partir de um recurso da mesma configuração é antipattern do Terraform — o endpoint do cluster é *unknown* no primeiro apply, e quebra na criação e no destroy.

O mesmo antipattern está neste arquivo, e é tolerável aqui pelo que este ambiente é: descartável, de uma máquina só, recriado do zero quando dá errado. Quando o `terraform destroy` tropeça no namespace, a saída é `kind delete cluster` e começar de novo — coisa que não existe como opção em `prod`.

Fica registrado para ninguém copiar o padrão daqui para o `infra/` achando que está seguindo o exemplo da casa.

## Versão do Kubernetes

`var.kubernetes_version` está em `v1.31.0`, enquanto o EKS roda **1.33**. Divergência conhecida: o node image do kind é publicado por release do projeto e nem sempre acompanha a versão do EKS. Para o que este ambiente faz — validar YAML e comportamento de manifest — a diferença não aparece. Se for testar API do Kubernetes que mudou entre as duas, ajuste a variável antes de tirar conclusão.
