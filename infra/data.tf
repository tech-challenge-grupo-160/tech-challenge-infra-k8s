data "aws_caller_identity" "atual" {}

data "aws_availability_zones" "disponiveis" {
  state = "available"
}

