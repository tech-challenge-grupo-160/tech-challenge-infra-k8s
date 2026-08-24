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
# Publicas: ALB e nodes do cluster. Os nodes ficam aqui, e nao em subnet
# privada, porque sem NAT Gateway (~US$ 32/mes) nao teriam saida para
# internet - decisao de custo registrada na issue #58 e na RFC-0001.
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

# Privadas: apenas o banco. Sem rota para a internet, por design.
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

# Sem rota default: a subnet privada nao tem saida para a internet.
resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "${local.nome}-privada" }
}

resource "aws_route_table_association" "privada" {
  count = var.quantidade_azs

  subnet_id      = aws_subnet.privada[count.index].id
  route_table_id = aws_route_table.privada.id
}
