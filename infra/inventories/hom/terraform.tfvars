ambiente = "hom"
region   = "us-east-1"
vpc_cidr = "10.0.0.0/16"

# Minimo 2: o subnet group do RDS exige duas zonas.
quantidade_azs = 2

# Cluster EKS e NAT Gateway ligados a partir de 30/08/2026, para exercitar a
# promocao develop -> homolog -> main com a infraestrutura completa nos tres
# ambientes.
#
# Custa ~US$ 3,50/dia por ambiente enquanto estiver true: US$ 0,10/hora do
# control plane, que NAO e suspenso com a sessao do lab, mais o NAT. Voltar para
# false destroi cluster e NAT juntos.
criar_cluster = true
