# Segredo de assinatura do JWT (issue #46 / F3-12).
#
# Fonte unica para os tres consumidores: a Lambda de autenticacao assina, o
# authorizer do API Gateway valida e a API .NET valida. Todos leem daqui em
# runtime - nenhum recebe o valor por variavel de ambiente em claro.
#
# O valor e gerado pelo Terraform e nunca aparece em arquivo versionado.
# Ele existe no state, que vive no bucket S3 com criptografia e acesso
# restrito (ver bootstrap/). Essa e a razao de o state nunca ser local.

resource "random_password" "jwt_signing_key" {
  length  = 64
  special = false

  # Sem o keeper, cada apply geraria uma chave nova e invalidaria todos os
  # tokens em circulacao. Trocar o valor daqui e a forma deliberada de rotacionar.
  keepers = {
    ambiente = var.ambiente
  }
}

resource "aws_secretsmanager_secret" "jwt_signing_key" {
  name        = "${var.project}/${var.ambiente}/jwt-signing-key"
  description = "Chave HMAC-SHA256 de assinatura do JWT emitido pela Lambda de autenticacao."

  # O Learner Lab e destruido ao fim de cada sessao de trabalho (RFC-0001).
  # Com a janela padrao de 30 dias, o nome ficaria reservado e o proximo
  # apply falharia com InvalidRequestException. Zero permite recriar na hora.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt_signing_key" {
  secret_id     = aws_secretsmanager_secret.jwt_signing_key.id
  secret_string = random_password.jwt_signing_key.result
}

# ---------------------------------------------------------------- privilegio
#
# O criterio de menor privilegio da issue #46 exige uma role por consumidor,
# com secretsmanager:GetSecretValue restrito a este ARN. A role da Lambda e
# publicada pelo repositorio da aplicacao; este modulo apenas cria o segredo.
# O desenho correto fica documentado para constar na entrega:
#
#   data "aws_iam_policy_document" "leitura_jwt" {
#     statement {
#       actions   = ["secretsmanager:GetSecretValue"]
#       resources = [aws_secretsmanager_secret.jwt_signing_key.arn]
#     }
#   }
