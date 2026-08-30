variable "region" {
  description = "Regiao AWS. O AWS Academy Learner Lab so permite us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo dos recursos."
  type        = string
  default     = "tc-grupo160"
}

variable "ambiente" {
  description = "Ambiente logico (dev, hom, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "hom", "prod"], var.ambiente)
    error_message = "ambiente deve ser dev, hom ou prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "quantidade_azs" {
  description = "Quantidade de zonas de disponibilidade. Minimo 2 para o RDS."
  type        = number
  default     = 2

  validation {
    condition     = var.quantidade_azs >= 2
    error_message = "O subnet group do RDS exige ao menos 2 AZs."
  }
}

variable "criar_cluster" {
  description = <<-EOT
    Cria o cluster EKS, o node group e o NAT Gateway das subnets privadas.

    Desligado por padrao, e de proposito: o control plane cobra US$ 0,10/hora
    enquanto existir e NAO e suspenso com a sessao do Learner Lab, diferente das
    instancias EC2. Com o NAT, dao ~US$ 3,50/dia contra um orcamento de US$ 100.

    Nao esta ligado em nenhum inventory. Para subir o cluster em dev, ligue em
    inventories/dev/terraform.tfvars e desligue quando terminar - a RFC-0001
    pede `terraform destroy` ao fim de cada sessao de trabalho.
  EOT
  type        = bool
  default     = false
}

variable "cluster_version" {
  description = <<-EOT
    Versao do Kubernetes no EKS.

    Nem a mais nova nem a mais velha: `aws eks describe-cluster-versions`
    listava 1.31 a 1.36 em 29/08/2026. A 1.31 sai de suporte primeiro e a 1.36
    e recente demais para addons; 1.33 fica no meio.
  EOT
  type        = string
  default     = "1.33"
}

variable "node_instance_types" {
  description = <<-EOT
    Tipos de instancia dos nodes.

    t3.medium e o menor que serve: o VPC CNI reserva IPs por ENI e limita quantos
    pods cabem no node, e em t3.micro os pods de sistema - CoreDNS, kube-proxy,
    metrics-server - ja ocupam quase tudo, sem sobrar espaco para a aplicacao.
  EOT
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_disk_size" {
  description = "Disco de cada node, em GB."
  type        = number
  default     = 20
}

variable "node_desired_size" {
  description = "Quantidade inicial de nodes. Depois do primeiro apply, quem manda e o autoscaling."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimo de nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximo de nodes que o autoscaling pode criar."
  type        = number
  default     = 4
}

variable "lambda_auth_nome" {
  description = "Nome da funcao Lambda de autenticacao. Vazio usa <project>-auth-<ambiente>."
  type        = string
  default     = ""
}

variable "alb_listener_arn" {
  description = <<-EOT
    ARN do listener do load balancer que expoe a API no cluster.
    Enquanto vazio, o gateway sobe apenas com a rota de autenticacao: o
    VPC Link e as rotas /api/v1 ficam de fora. Preencher quando o cluster
    (issue #60) e o ingress (issue #64) existirem.
  EOT
  type        = string
  default     = ""
}

variable "gateway_rate_limit" {
  description = "Requisicoes por segundo por rota no gateway."
  type        = number
  default     = 50
}

variable "gateway_burst_limit" {
  description = "Rajada permitida acima do rate limit."
  type        = number
  default     = 100
}

variable "gateway_log_retention_days" {
  description = "Retencao dos logs de acesso do gateway. Baixa de proposito: o orcamento do lab e de US$ 100."
  type        = number
  default     = 7
}
