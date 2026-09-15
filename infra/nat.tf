# Saida para a internet das subnets privadas (issue #60 / F3-26).
#
# A RFC-0001 decidiu nao ter NAT Gateway e colocar os nodes em subnet publica,
# por custo. A decisao foi revista em 2026-08-29 pelo mesmo motivo que reverteu
# o RDS Single-AZ em 27/08: o credito e renovavel, entao custo deixou de ser o
# fator de decisao. A issue #60 exige "nodes em subnets privadas" e a #58 exigia
# "gateway de saida para as subnets privadas" - este arquivo entrega as duas.
#
# Por que os nodes precisam de saida: para ENTRAR no cluster. O kubelet puxa as
# imagens do kube-proxy, do VPC CNI e do CoreDNS no ECR e registra o node na API
# do EKS. Sem rota, os nodes sobem e ficam NotReady para sempre, sem mensagem
# obvia - e a falha classica de EKS em VPC sem NAT.
#
# Um NAT so, nao um por AZ. Alta disponibilidade de NAT protege contra queda de
# uma zona inteira; para um ambiente de estudo isso e pagar o dobro por um risco
# que nao corremos. Se a AZ do NAT cair, o cluster para - e aceitavel aqui.
#
# Tudo neste arquivo depende de criar_cluster: sem cluster nao ha nodes, e um
# NAT ocioso custa ~US$ 1,08/dia sem entregar nada.

resource "aws_eip" "nat" {
  count = var.criar_cluster ? 1 : 0

  domain = "vpc"

  tags = { Name = "${local.nome}-nat" }
}

resource "aws_nat_gateway" "principal" {
  count = var.criar_cluster ? 1 : 0

  allocation_id = aws_eip.nat[0].id

  # Fica na subnet publica: e de la que ele alcanca o internet gateway.
  subnet_id = aws_subnet.publica[0].id

  tags = { Name = local.nome }

  # O internet gateway precisa existir antes: sem ele o NAT sobe sem rota de
  # saida e falha de forma silenciosa.
  depends_on = [aws_internet_gateway.principal]
}

# Rota default da tabela privada. Com ela, quem esta em subnet privada passa a
# ter saida para a internet - o que inclui a Lambda de autenticacao, alem dos
# nodes.
#
# O endpoint de interface do Secrets Manager continua valendo a pena mesmo
# assim: o trafego nao sai da VPC, e o custo por AZ e menor que o do NAT mais
# transferencia. Ver a emenda de 27/08 na RFC-0001.
resource "aws_route" "privada_nat" {
  count = var.criar_cluster ? 1 : 0

  route_table_id         = aws_route_table.privada.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.principal[0].id
}
