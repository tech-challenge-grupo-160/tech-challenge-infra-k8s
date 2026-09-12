# Cluster Kubernetes gerenciado (issue #60 / F3-26).
#
# Tudo aqui e opcional por design: com criar_cluster desligado - o padrao - nada
# neste arquivo existe, e o ambiente volta a custar praticamente zero. A RFC-0001
# registra a disciplina: "Cluster criado tarde, proximo a gravacao do video, e
# destruido logo depois."
#
# O control plane cobra por hora ENQUANTO EXISTIR. Somado ao NAT, o custo pode
# ser relevante. Ligar e uma decisao consciente; por isso a variavel nao vem
# ligada em nenhum inventory.
#
# O Learner Lab nao permite criar roles IAM. A LabRole preexistente e usada tanto
# pelo control plane quanto pelos nodes.

resource "aws_eks_cluster" "principal" {
  count = var.criar_cluster ? 1 : 0

  name     = local.nome
  role_arn = "arn:aws:iam::${data.aws_caller_identity.atual.account_id}:role/LabRole"
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

    # Quem aplica o Terraform vira admin do cluster automaticamente.
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = { Name = local.nome }
}

# ------------------------------------------------------------------- nodes

resource "aws_eks_node_group" "principal" {
  count = var.criar_cluster ? 1 : 0

  cluster_name    = aws_eks_cluster.principal[0].name
  node_group_name = "${local.nome}-nodes"
  node_role_arn   = "arn:aws:iam::${data.aws_caller_identity.atual.account_id}:role/LabRole"
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

# --------------------------------------------- acesso dos pods ao banco
#
# Um node group gerenciado sem launch template recebe APENAS o security group
# que o proprio EKS cria - o `eks-cluster-sg-<cluster>`. O `sg_nodes` deste
# repositorio vai em vpc_config.security_group_ids, e isso o coloca nas ENIs do
# control plane, nao nas instancias dos nodes.
#
# Como o VPC CNI da aos pods IPs secundarios das ENIs do node, o trafego que sai
# de um pod carrega o security group do node - ou seja, o do EKS. A regra que o
# security-groups.tf cria liberando o `sg_nodes` no PostgreSQL nao vale para
# nenhum node de verdade.
#
# Diagnosticado em 2026-08-30 no primeiro deploy da API: os pods subiam e
# falhavam com "Failed to connect to <ip>:5432 - Timeout during connection
# attempt", que e timeout de rede e nao erro de credencial.
#
# A alternativa estrutural seria um launch template no node group so para
# atachar o `sg_nodes` as instancias, o que tornaria todas as regras existentes
# verdadeiras de novo. Fica registrado como o caminho mais correto; nao foi
# adotado agora porque launch template com node group gerenciado tem arestas
# proprias (AMI e user data) e o prazo nao comporta o risco.
resource "aws_vpc_security_group_ingress_rule" "banco_dos_nodes_eks" {
  count = var.criar_cluster ? 1 : 0

  security_group_id            = aws_security_group.banco.id
  description                  = "PostgreSQL a partir dos nodes do EKS"
  referenced_security_group_id = aws_eks_cluster.principal[0].vpc_config[0].cluster_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ------------------------------------------------ descoberta do autoscaler
#
# O Cluster Autoscaler nao recebe a lista de node groups por parametro: ele
# varre os Auto Scaling groups da regiao e fica com os que carregam estas duas
# tags. E o modo `--node-group-auto-discovery=asg:tag=...`, que o manifest em
# k8s/cluster-autoscaler usa.
#
# As tags vao no ASG, nao no node group. Sao coisas diferentes: o `tags` do
# aws_eks_node_group marca o recurso do EKS, e o autoscaler nunca olha para ele
# - ele fala com a API do Auto Scaling. Por isso o aws_autoscaling_group_tag,
# que alcanca o ASG que o EKS criou por baixo.
#
# A segunda tag traz o nome do cluster de proposito. Os tres ambientes vivem na
# MESMA conta do Learner Lab: com apenas a tag `enabled`, o autoscaler de `dev`
# descobriria tambem os ASGs de `hom` e `prod` e escalaria os nodes deles.
#
# propagate_at_launch = false porque isto descreve o grupo, nao as instancias.
# Propagar so encheria cada EC2 de tag sem uso.

resource "aws_autoscaling_group_tag" "autoscaler_habilitado" {
  count = var.criar_cluster ? 1 : 0

  autoscaling_group_name = aws_eks_node_group.principal[0].resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "autoscaler_cluster" {
  count = var.criar_cluster ? 1 : 0

  autoscaling_group_name = aws_eks_node_group.principal[0].resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${local.nome}"
    value               = "owned"
    propagate_at_launch = false
  }
}
