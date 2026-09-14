# Balanceador da API no cluster (issue #64 / F3-30).
#
# INTERNO, nao voltado para a internet. A porta publica da aplicacao e o API
# Gateway, que ja atende em https://<id>.execute-api.<regiao>.amazonaws.com com
# certificado valido da AWS. Um ALB publico exigiria certificado do ACM, e o ACM
# so emite para dominio cuja posse se prova - ninguem valida amazonaws.com. Sem
# um dominio do grupo, um ALB exposto ficaria em HTTP puro.
#
# O caminho fica:
#
#   cliente --HTTPS--> API Gateway --VPC Link--> ALB interno --> nodes --> pods
#
# Assim o TLS sai de graca e existe uma unica porta de entrada, que e onde o
# authorizer da issue #43 vai morar.
#
# ---------------------------------------------------------------------------
# Por que target_type "instance" e nao "ip"
#
# Alvos por IP de pod exigiriam o AWS Load Balancer Controller, que por sua vez
# exige IRSA - uma IAM role para a service account. O Learner Lab nao permite
# criar roles (ver RFC-0001 e issue #59), entao esse caminho esta fechado.
#
# Com alvos por instancia, o trafego chega no NodePort do Service e o kube-proxy
# encaminha ao pod. Custa um salto extra dentro do cluster e nao preserva o IP
# de origem - aceitavel aqui, e o preco de nao depender de IRSA.
#
# O registro dos nodes fica por conta do autoscaling attachment mais abaixo: e
# o proprio ASG do node group que inscreve e remove instancias no target group,
# entao nodes reciclados pelo lab nao deixam alvo orfao.

resource "aws_lb" "api" {
  count = var.criar_cluster ? 1 : 0

  name               = "${local.nome}-api"
  internal           = true
  load_balancer_type = "application"
  subnets            = aws_subnet.privada[*].id
  security_groups    = [aws_security_group.alb.id]

  # O ambiente do lab e recriado com frequencia; protecao contra delecao so
  # atrapalharia o destroy.
  enable_deletion_protection = false

  tags = { Name = "${local.nome}-api" }
}

resource "aws_lb_target_group" "api" {
  count = var.criar_cluster ? 1 : 0

  name        = "${local.nome}-api"
  port        = var.node_port_api
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.principal.id

  health_check {
    enabled = true
    # /health/live e nao /health: o segundo devolve a descricao dos checks, que
    # pode carregar mensagem de excecao do banco. Ver a matriz de autorizacao.
    path                = "/health/live"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Sem isto, tirar um node do ar deixaria conexoes penduradas por 5 minutos, o
  # padrao. O lab recicla instancias com frequencia.
  deregistration_delay = 30

  tags = { Name = "${local.nome}-api" }
}

resource "aws_lb_listener" "api" {
  count = var.criar_cluster ? 1 : 0

  load_balancer_arn = aws_lb.api[0].arn
  port              = 80
  protocol          = "HTTP"

  # HTTP puro de proposito: o balanceador e interno e so o VPC Link o alcanca.
  # O TLS termina no API Gateway, antes de entrar na VPC.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[0].arn
  }
}

# E isto que mantem o target group em dia. O node group gerenciado cria um ASG;
# prendendo o target group a ele, cada instancia que nasce se inscreve e cada
# uma que morre sai, sem ninguem registrar nada a mao.
resource "aws_autoscaling_attachment" "api" {
  count = var.criar_cluster ? 1 : 0

  autoscaling_group_name = aws_eks_node_group.principal[0].resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.api[0].arn
}

# ------------------------------------------------------------ regras de rede
#
# Duas pontas precisam ser abertas, e a segunda e a que ja nos custou um deploy.

# O VPC Link cria ENIs que compartilham o sg_alb com o balanceador. A regra e
# auto-referenciada: permite que essas ENIs alcancem o ALB na porta 80.
resource "aws_vpc_security_group_ingress_rule" "alb_do_vpc_link" {
  count = var.criar_cluster ? 1 : 0

  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP a partir das ENIs do VPC Link"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

# A regra nodes_do_alb em security-groups.tf libera o trafego do ALB para o
# `sg_nodes` - que, como descobrimos na issue #52, nao esta em node algum. Node
# group gerenciado sem launch template recebe apenas o security group criado
# pelo proprio EKS. Sem esta regra, o health check do target group falha em
# todos os alvos e o ALB devolve 502, sem dizer por que.
resource "aws_vpc_security_group_ingress_rule" "nodes_do_alb_eks" {
  count = var.criar_cluster ? 1 : 0

  security_group_id            = aws_eks_cluster.principal[0].vpc_config[0].cluster_security_group_id
  description                  = "NodePort da API a partir do balanceador"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.node_port_api
  to_port                      = var.node_port_api
  ip_protocol                  = "tcp"
}
