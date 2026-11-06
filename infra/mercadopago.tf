# Credenciais do Mercado Pago do Billing Service (F4-06).
#
# Um segredo por ambiente, com o access token da aplicacao e a assinatura
# secreta dos webhooks. O Billing le o segredo em runtime pelo nome (mesmo
# padrao do JWT em secrets.tf) - o valor nunca vai para ConfigMap, manifest ou
# arquivo versionado.
#
# Diferente do JWT, o valor nao pode ser gerado aqui: ele vem do painel do
# Mercado Pago. Entra por TF_VAR_mercadopago_access_token e
# TF_VAR_mercadopago_webhook_secret, alimentadas pelos secrets do GitHub na
# pipeline. O passo a passo para gerar as credenciais esta no repositorio do
# Billing, em docs/MERCADO-PAGO.md.
#
# Sem as variaveis, o segredo e criado vazio (sem versao). Assim o plan e o
# apply continuam funcionando para quem nao tem as credenciais, e o Billing
# falha no startup com uma mensagem clara em vez de usar um valor falso.

resource "aws_secretsmanager_secret" "mercadopago" {
  name        = "${var.project}/${var.ambiente}/mercadopago"
  description = "Access token da aplicacao e assinatura secreta dos webhooks do Mercado Pago, usados pelo Billing Service."

  # Mesmo motivo do JWT: o Learner Lab e destruido ao fim de cada sessao e a
  # janela padrao de 30 dias deixaria o nome reservado, quebrando o proximo apply.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mercadopago" {
  # nonsensitive so no booleano: o valor continua sensivel, mas o Terraform nao
  # aceita valor sensivel em count.
  count = nonsensitive(var.mercadopago_access_token != "") ? 1 : 0

  secret_id = aws_secretsmanager_secret.mercadopago.id
  secret_string = jsonencode({
    access_token   = var.mercadopago_access_token
    webhook_secret = var.mercadopago_webhook_secret
  })
}
