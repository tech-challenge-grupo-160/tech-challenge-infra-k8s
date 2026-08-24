data "aws_caller_identity" "atual" {}

data "aws_availability_zones" "disponiveis" {
  state = "available"
}

# O Learner Lab nao permite criar roles nem policies: LabRole e a unica
# utilizavel, compartilhada por Lambda, cluster e pipelines. Referenciada,
# nunca criada. Ver RFC-0001 e issue #59.
data "aws_iam_role" "lab" {
  name = "LabRole"
}
