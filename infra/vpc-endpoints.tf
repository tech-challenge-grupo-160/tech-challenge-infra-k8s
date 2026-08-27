# Endpoints de interface da VPC (issues #46 e #61).
#
# A Lambda de autenticacao precisa entrar na VPC para alcancar o RDS, que fica
# em subnet privada sem acesso publico. Ao entrar, ela perde a saida para a
# internet: a subnet privada nao tem rota default - nao ha NAT Gateway, decisao
# de custo da RFC-0001 - e o sg_lambda so tem egress para o CIDR da VPC.
#
# Sem isto, anexar a Lambda a VPC quebraria a leitura do segredo do JWT no cold
# start, que e como a issue #46 foi implementada. O endpoint devolve o acesso ao
# Secrets Manager por dentro da rede.
#
# Custo: ~US$ 0,01/hora por AZ, contra ~US$ 0,045/hora do NAT Gateway mais o
# trafego. Com duas AZs, cerca de US$ 0,48/dia.

resource "aws_security_group" "endpoints" {
  name        = "${local.nome}-endpoints"
  description = "Endpoints de interface da VPC"
  vpc_id      = aws_vpc.principal.id

  tags = { Name = "${local.nome}-endpoints" }
}

# So quem esta na VPC alcanca o endpoint, e so em 443.
resource "aws_vpc_security_group_ingress_rule" "endpoints_da_lambda" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS a partir da Lambda de autenticacao"
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# Os nodes tambem vao precisar quando a API passar a ler segredos da mesma
# fonte. Eles estao em subnet publica e hoje alcancam o Secrets Manager pela
# internet, mas pelo endpoint o trafego nao sai da VPC.
resource "aws_vpc_security_group_ingress_rule" "endpoints_dos_nodes" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS a partir dos nodes do cluster"
  referenced_security_group_id = aws_security_group.nodes.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id            = aws_vpc.principal.id
  service_name      = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type = "Interface"

  subnet_ids         = aws_subnet.privada[*].id
  security_group_ids = [aws_security_group.endpoints.id]

  # Com o DNS privado, o SDK continua chamando
  # secretsmanager.<regiao>.amazonaws.com e a resolucao aponta para o endpoint.
  # Nenhuma mudanca de codigo na Lambda. Depende de enable_dns_support e
  # enable_dns_hostnames na VPC, ambos ja habilitados em rede.tf.
  private_dns_enabled = true

  tags = { Name = "${local.nome}-secretsmanager" }
}
