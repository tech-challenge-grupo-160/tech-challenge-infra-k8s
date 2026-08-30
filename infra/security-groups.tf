# Desde 29/08 os nodes ficam em subnet privada, atras do NAT (issue #60), entao
# o SG deixou de ser a unica barreira que protege o banco. Continua sendo a
# barreira principal: nenhuma regra de entrada usa cidr_ipv4 aberto - o acesso
# ao PostgreSQL e concedido por referencia a outro security group.

resource "aws_security_group" "alb" {
  name        = "${local.nome}-alb"
  description = "Entrada HTTP e HTTPS da internet para o balanceador"
  vpc_id      = aws_vpc.principal.id

  tags = { Name = "${local.nome}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS da internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP da internet, redirecionado para HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_saida" {
  security_group_id = aws_security_group.alb.id
  description       = "Saida para os nodes"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ATENCAO ao nome: apesar de "nodes", este security group NAO fica nas
# instancias dos nodes. Ele entra em vpc_config.security_group_ids do cluster,
# o que o coloca nas ENIs do control plane. Um node group gerenciado sem launch
# template recebe apenas o `eks-cluster-sg-<cluster>`, criado pelo EKS.
#
# Consequencia pratica: regras que liberam acesso "a partir dos nodes"
# referenciando este SG nao valem para pod algum. Ver a regra
# banco_dos_nodes_eks em cluster.tf, que e a que de fato libera o banco.
resource "aws_security_group" "nodes" {
  name        = "${local.nome}-nodes"
  description = "Nodes do cluster Kubernetes"
  vpc_id      = aws_vpc.principal.id

  tags = { Name = "${local.nome}-nodes" }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_do_alb" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "Trafego vindo do balanceador"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_entre_si" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "Comunicacao entre pods e nodes"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "nodes_saida" {
  security_group_id = aws_security_group.nodes.id
  description       = "Saida para registry de imagens e API da AWS"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "banco" {
  name        = "${local.nome}-banco"
  description = "PostgreSQL gerenciado, sem acesso publico"
  vpc_id      = aws_vpc.principal.id

  tags = { Name = "${local.nome}-banco" }
}

# Sem regra com cidr_ipv4 aberto: so quem estiver nestes SGs alcanca o banco.
resource "aws_vpc_security_group_ingress_rule" "banco_dos_nodes" {
  security_group_id            = aws_security_group.banco.id
  description                  = "PostgreSQL a partir dos nodes"
  referenced_security_group_id = aws_security_group.nodes.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "lambda" {
  name        = "${local.nome}-lambda"
  description = "Lambda de autenticacao, quando anexada a VPC"
  vpc_id      = aws_vpc.principal.id

  tags = { Name = "${local.nome}-lambda" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_saida" {
  security_group_id = aws_security_group.lambda.id
  description       = "Saida para o banco"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "banco_da_lambda" {
  security_group_id            = aws_security_group.banco.id
  description                  = "PostgreSQL a partir da Lambda de autenticacao"
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
