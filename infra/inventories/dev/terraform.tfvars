ambiente = "dev"
region   = "us-east-1"
vpc_cidr = "10.0.0.0/16"

# Minimo 2: o subnet group do RDS exige duas zonas.
quantidade_azs = 2

# Cluster EKS e NAT Gateway ligados em dev a partir de 29/08/2026, para a carga
# do schema no RDS (issue #62) e o deploy da aplicacao (issue #52).
#
# Custa ~US$ 3,50/dia enquanto estiver true: US$ 0,10/hora do control plane, que
# NAO e suspenso com a sessao do lab, mais o NAT. Volte para false ao terminar -
# a RFC-0001 pede o cluster destruido ao fim de cada sessao de trabalho.
criar_cluster = true
