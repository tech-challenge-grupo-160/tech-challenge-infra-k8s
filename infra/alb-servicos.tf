# Billing e Execucao atras do mesmo ALB do OS Service (F4-14).
#
# Roteamento por caminho, sem prefixo por servico: as rotas dos tres nao se
# sobrepoem, entao o ALB escolhe o target group pelo caminho e o que nao casar
# com nenhuma regra segue para o OS Service (default_action em alb.tf). O API
# Gateway nao muda - a rota ANY /api/v1/{proxy+} com o authorizer ja cobre os
# tres. Prefixos como /billing exigiriam reescrever o caminho no gateway, porque
# o ALB nao reescreve. Decisao registrada na issue #145 em 09/11.
#
# Mesmo desenho do OS Service, um por servico: NodePort fixo no Service do
# Kubernetes (k8s/service.yaml de cada repositorio), target group do tipo
# instancia, ASG do node group inscrevendo os nodes e regra no SG do EKS
# liberando a porta para o ALB. Os motivos de cada peca estao em alb.tf.
#
# A porta de cada servico precisa casar com o nodePort do manifest dele.
# Divergir derruba o health check e o ALB devolve 502 so para aquele servico.

locals {
  servicos_roteados = {
    billing = {
      node_port  = 30081
      prioridade = 10
      caminhos   = ["/api/v1/orcamentos*", "/api/v1/pagamentos*"]
    }
    execucao = {
      node_port  = 30082
      prioridade = 20
      # O ALB aceita no maximo 5 valores por condicao de caminho. Passando
      # disso, a Execucao precisa de uma segunda regra.
      caminhos = ["/api/v1/catalogo*", "/api/v1/diagnosticos*", "/api/v1/estoque*", "/api/v1/execucoes*"]
    }
  }
}

resource "aws_lb_target_group" "servico" {
  for_each = var.criar_cluster ? local.servicos_roteados : {}

  name        = "${local.nome}-${each.key}"
  port        = each.value.node_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.principal.id

  health_check {
    enabled             = true
    path                = "/health/live"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = { Name = "${local.nome}-${each.key}", Service = each.key }
}

resource "aws_lb_listener_rule" "servico" {
  for_each = var.criar_cluster ? local.servicos_roteados : {}

  listener_arn = aws_lb_listener.api[0].arn
  priority     = each.value.prioridade

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.servico[each.key].arn
  }

  # O ALB aceita ate 5 valores por condicao.
  condition {
    path_pattern {
      values = each.value.caminhos
    }
  }

  tags = { Name = "${local.nome}-${each.key}" }
}

resource "aws_autoscaling_attachment" "servico" {
  for_each = var.criar_cluster ? local.servicos_roteados : {}

  autoscaling_group_name = aws_eks_node_group.principal[0].resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.servico[each.key].arn
}

resource "aws_vpc_security_group_ingress_rule" "nodes_do_alb_eks_servico" {
  for_each = var.criar_cluster ? local.servicos_roteados : {}

  security_group_id            = aws_eks_cluster.principal[0].vpc_config[0].cluster_security_group_id
  description                  = "NodePort do ${each.key} a partir do balanceador"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = each.value.node_port
  to_port                      = each.value.node_port
  ip_protocol                  = "tcp"
}
