locals {
  nome = "${var.project}-${var.ambiente}"
  azs  = slice(data.aws_availability_zones.disponiveis.names, 0, var.quantidade_azs)
}

resource "aws_vpc" "principal" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # exigido pelo EKS e pelo endpoint do RDS

  tags = { Name = local.nome }
}

resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = local.nome }
}

# ---------------------------------------------------------------- subnets
# Publicas: ALB e NAT Gateway.
#
# Ate 29/08 os nodes do cluster tambem ficavam aqui, porque sem NAT Gateway eles
# nao teriam saida para a internet - decisao de custo da RFC-0001. Revista: o
# credito e renovavel, a #60 exige nodes em subnet privada, e o NAT entrou em
# nat.tf. Os nodes agora ficam nas privadas.
resource "aws_subnet" "publica" {
  count = var.quantidade_azs

  vpc_id                  = aws_vpc.principal.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.nome}-publica-${local.azs[count.index]}"
    # Tags que o AWS Load Balancer Controller procura para escolher onde
    # criar o ALB. Ficam prontas para a issue #60.
    "kubernetes.io/role/elb" = "1"
  }
}

# Privadas: banco, Lambda de autenticacao e nodes do cluster. A rota default
# para o NAT so existe com criar_cluster ligado - ver nat.tf. Sem ela, quem
# esta aqui alcanca apenas a VPC e os VPC endpoints.
resource "aws_subnet" "privada" {
  count = var.quantidade_azs

  vpc_id            = aws_vpc.principal.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 8)
  availability_zone = local.azs[count.index]

  tags = {
    Name                              = "${local.nome}-privada-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ---------------------------------------------------------------- rotas
resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.principal.id
  }

  tags = { Name = "${local.nome}-publica" }
}

resource "aws_route_table_association" "publica" {
  count = var.quantidade_azs

  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# A rota default entra em nat.tf, condicionada a criar_cluster. Sem cluster, a
# subnet privada segue sem saida para a internet - e o endpoint de interface do
# Secrets Manager e o que mantem a Lambda funcionando nesse cenario.
resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "${local.nome}-privada" }
}

resource "aws_route_table_association" "privada" {
  count = var.quantidade_azs

  subnet_id      = aws_subnet.privada[count.index].id
  route_table_id = aws_route_table.privada.id
}
