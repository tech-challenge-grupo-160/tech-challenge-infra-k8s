variable "cluster_name" {
  description = "Nome do cluster kind que sera criado"
  type        = string
  default     = "oficina-mecanica"
}

variable "namespace" {
  description = "Namespace Kubernetes que recebera os recursos da aplicacao"
  type        = string
  default     = "oficina-mecanica"
}

variable "kubernetes_version" {
  description = "Versao da imagem do node kind"
  type        = string
  default     = "v1.31.0"
}

variable "control_plane_count" {
  description = "Numero de nos control-plane (use 1 para desenvolvimento local)"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Numero de nos worker onde os pods da aplicacao serao agendados"
  type        = number
  default     = 2
}

variable "api_host_port" {
  description = "Porta do host Windows mapeada para a porta 30080 do NodePort da API"
  type        = number
  default     = 8080
}

variable "ingress_http_port" {
  description = "Porta HTTP do host mapeada para o ingress controller"
  type        = number
  default     = 80
}

variable "ingress_https_port" {
  description = "Porta HTTPS do host mapeada para o ingress controller"
  type        = number
  default     = 443
}

variable "postgres_user" {
  description = "Usuario do PostgreSQL"
  type        = string
  default     = "postgres"
}

variable "postgres_pas" {
  description = "Senha do PostgreSQL"
  type        = string
  sensitive   = true
}

variable "postgres_db" {
  description = "Nome do banco de dados"
  type        = string
  default     = "oficina_mecanica"
}

variable "jwt_secret_key" {
  description = "Chave de assinatura JWT com minimo de 32 caracteres"
  type        = string
  sensitive   = true
  default     = "dev-secret-key-minimo-32-caracteres-ok"
}
