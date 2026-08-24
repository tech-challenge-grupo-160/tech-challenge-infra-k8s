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
