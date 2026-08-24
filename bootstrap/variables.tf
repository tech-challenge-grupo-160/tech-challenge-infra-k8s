variable "region" {
  description = "Regiao AWS. O AWS Academy Learner Lab so permite us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo dos recursos criados."
  type        = string
  default     = "tc-grupo160"
}
