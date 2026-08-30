resource "aws_sns_topic" "notificacoes_os" {
  name = "${local.nome}-notificacoes-os"
}

resource "aws_sns_topic" "alertas_operacionais" {
  name = "${local.nome}-alertas-operacionais"
}

# Assinatura por e-mail 
resource "aws_sns_topic_subscription" "notificacoes_os_email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.notificacoes_os.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_sns_topic_subscription" "alertas_operacionais_email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alertas_operacionais.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

variable "notification_email" {
  description = <<-EOT
    E-mail para assinar os topicos SNS de notificacao (opcional, so para
    validacao manual/demo). Vazio por padrao - nenhuma assinatura e criada.
  EOT
  type    = string
  default = ""
}

output "sns_topic_notificacoes_os_arn" {
  description = "ARN do topico de notificacoes de ordem de servico. A API (repositorio principal) publica aqui a cada mudanca de status."
  value       = aws_sns_topic.notificacoes_os.arn
}

output "sns_topic_alertas_operacionais_arn" {
  description = "ARN do topico de alertas operacionais. Consumido pelos CloudWatch Alarms (ver alarms.tf)."
  value       = aws_sns_topic.alertas_operacionais.arn
}
