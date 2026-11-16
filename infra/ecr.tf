# Registry das imagens dos servicos (issue #52 / F3-18; Billing e Execucao na F4-08).
#
# Ate aqui o deploy usava `kind load docker-image` com uma imagem local e
# imagePullPolicy: Never - o cluster nunca puxava nada de lugar nenhum. Com o
# EKS isso deixa de funcionar: os nodes sao efemeros e cada um precisa buscar a
# imagem em algum lugar alcancavel.
#
# Um repositorio por ambiente, seguindo o mesmo modelo do resto deste Terraform,
# em que cada ambiente tem o seu state e os seus recursos. Compartilhar um
# registry entre ambientes exigiria coloca-lo no bootstrap e criaria acoplamento
# entre states que hoje nao existe.
#
# Nao depende de criar_cluster: o registry nao cobra por hora, so por
# armazenamento, e manter as imagens entre sessoes evita rebuild desnecessario
# quando o cluster e recriado.

# Um repositorio por servico. `api` e o OS Service, com o nome que ja tinha
# antes da Fase 4: o `sobe-tudo.sh` e o pipeline montam esse nome.
locals {
  imagens_ecr = toset(["api", "billing", "execucao"])
}

resource "aws_ecr_repository" "imagem" {
  for_each = local.imagens_ecr

  name = "${local.nome}-${each.key}"

  # MUTABLE porque a tag `latest` e reescrita a cada deploy. As tags versionadas
  # por commit continuam servindo de referencia imutavel na pratica - o que o
  # rollback usa e o SHA, nunca `latest`.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    # Varredura de vulnerabilidades no push. E gratuita no nivel basico e o
    # resultado vale para a issue de seguranca da fase.
    scan_on_push = true
  }

  # O ambiente do lab e recriado com frequencia e o repositorio precisa sumir
  # junto no destroy, mesmo com imagens dentro.
  force_delete = true

  tags = { Name = "${local.nome}-${each.key}" }
}

# Sem isto o repositorio cresce sem limite: cada commit publica uma imagem nova
# de ~100 MB e nada nunca e removido. O S3 do state e barato, o ECR nao tanto.
resource "aws_ecr_lifecycle_policy" "imagem" {
  for_each = aws_ecr_repository.imagem

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantem apenas as ${var.ecr_imagens_mantidas} imagens mais recentes."
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_imagens_mantidas
        }
        action = { type = "expire" }
      }
    ]
  })
}

# O repositorio da API ja existia como recurso unico. Sem o moved, o plan
# destruiria e recriaria o registry do OS Service, com as imagens dentro.
moved {
  from = aws_ecr_repository.api
  to   = aws_ecr_repository.imagem["api"]
}

moved {
  from = aws_ecr_lifecycle_policy.api
  to   = aws_ecr_lifecycle_policy.imagem["api"]
}
