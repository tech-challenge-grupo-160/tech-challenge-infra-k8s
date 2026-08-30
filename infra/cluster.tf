# Cluster Kubernetes gerenciado (issue #60 / F3-26).
#
# Tudo aqui e opcional por design: com criar_cluster desligado - o padrao - nada
# neste arquivo existe, e o ambiente volta a custar praticamente zero. A RFC-0001
# registra a disciplina: "Cluster criado tarde, proximo a gravacao do video, e
# destruido logo depois."
#
# O control plane cobra US$ 0,10/hora ENQUANTO EXISTIR, e nao e suspenso junto
# com a sessao do Learner Lab - diferente das instancias EC2. Somado ao NAT dao
# ~US$ 3,50/dia contra um orcamento de US$ 100. Ligar e uma decisao consciente;
# por isso a variavel nao vem ligada em nenhum inventory.
#
# A LabRole e usada como role do cluster E dos nodes. Nao e desenho, e limitacao:
# o Learner Lab nao permite criar roles. Ver RFC-0001 e issue #59.

resource "aws_eks_cluster" "principal" {
  count = var.criar_cluster ? 1 : 0

  name     = local.nome
  role_arn = data.aws_iam_role.lab.arn
  version  = var.cluster_version

  vpc_config {
    # Publicas e privadas: o control plane distribui as ENIs de comunicacao com
    # os nodes, e ter as duas familias evita depender de uma unica AZ.
    subnet_ids = concat(aws_subnet.privada[*].id, aws_subnet.publica[*].id)

    # Publico continua ligado porque as pipelines rodam no GitHub Actions, cujos
    # runners tem IP dinamico - restringir por CIDR nao e praticavel aqui.
    # O acesso segue autenticado por IAM; publico e o endpoint, nao o cluster.
    endpoint_private_access = true
    endpoint_public_access  = true

    security_group_ids = [aws_security_group.nodes.id]
  }

  access_config {
    # API_AND_CONFIG_MAP em vez de so CONFIG_MAP: o aws-auth ConfigMap esta
    # depreciado, e os access entries abaixo dependem do modo API.
    authentication_mode = "API_AND_CONFIG_MAP"

    # Quem aplica o Terraform vira admin do cluster automaticamente, por um
    # access entry que o proprio EKS cria. Ele e gravado com o ARN da IAM role
    # por tras da sessao - `arn:aws:iam::<conta>:role/voclabs` -, nao com o ARN
    # da sessao. Como todas as sessoes do lab, inclusive as das pipelines,
    # assumem essa mesma role, um unico entry cobre todo mundo.
    #
    # Nao ha access entry explicito aqui de proposito: ele colidiria com o que o
    # bootstrap cria para o mesmo principal, e o apply falharia com
    # ResourceInUseException. Se um dia for preciso liberar outro principal,
    # monte o ARN com data.aws_caller_identity.atual.account_id - o lab nega
    # iam:GetRole ate sobre a propria voclabs, entao `data aws_iam_role` nao
    # serve. E o mesmo motivo que fez o api-gateway.tf montar o ARN da Lambda.
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = { Name = local.nome }
}

# ------------------------------------------------------------------- nodes

resource "aws_eks_node_group" "principal" {
  count = var.criar_cluster ? 1 : 0

  cluster_name    = aws_eks_cluster.principal[0].name
  node_group_name = "${local.nome}-nodes"
  node_role_arn   = data.aws_iam_role.lab.arn
  version         = var.cluster_version

  # Subnets privadas, como pede o criterio de aceite da #60. Alcancam a internet
  # pelo NAT - ver nat.tf.
  subnet_ids = aws_subnet.privada[*].id

  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # A rota do NAT precisa existir ANTES dos nodes. Se o node subir sem saida,
  # ele nao consegue baixar as imagens do plano de controle nem se registrar, e
  # o node group falha depois de ~15 minutos de espera.
  depends_on = [aws_route.privada_nat]

  lifecycle {
    # O desired_size passa a ser gerido por quem escala - HPA via cluster
    # autoscaler, ou ajuste manual. Sem isto, todo apply devolveria a contagem
    # para o valor da variavel e desfaria o autoscaling.
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = { Name = "${local.nome}-nodes" }
}

# ------------------------------------------------------------------ addons
#
# O EKS ja instala vpc-cni, coredns e kube-proxy por padrao ao criar o cluster.
# O metrics-server nao vem: e ele que alimenta o HPA com uso de CPU e memoria, e
# sem ele o HPA fica em <unknown> e nunca escala. Como addon gerenciado, entra
# pelo Terraform sem precisar de kubectl nem Helm na pipeline.

resource "aws_eks_addon" "metrics_server" {
  count = var.criar_cluster ? 1 : 0

  cluster_name = aws_eks_cluster.principal[0].name
  addon_name   = "metrics-server"

  # Precisa de node pronto para agendar o pod.
  depends_on = [aws_eks_node_group.principal]
}
