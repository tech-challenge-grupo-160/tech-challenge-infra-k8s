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
