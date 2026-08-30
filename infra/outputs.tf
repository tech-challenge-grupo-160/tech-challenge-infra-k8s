output "vpc_id" {
  description = "Id da VPC."
  value       = aws_vpc.principal.id
}

output "subnets_publicas" {
  description = "Subnets publicas: ALB e NAT Gateway."
  value       = aws_subnet.publica[*].id
}

output "subnets_privadas" {
  description = "Subnets privadas: banco de dados, Lambda e nodes do cluster."
  value       = aws_subnet.privada[*].id
}

output "sg_alb" {
  description = "Security group do balanceador."
  value       = aws_security_group.alb.id
}

output "sg_nodes" {
  description = "Security group dos nodes do cluster."
  value       = aws_security_group.nodes.id
}

output "sg_banco" {
  description = "Security group do banco. Consumido pelo repositorio infra-database."
  value       = aws_security_group.banco.id
}

output "sg_lambda" {
  description = "Security group da Lambda de autenticacao."
  value       = aws_security_group.lambda.id
}

output "lab_role_arn" {
  description = "ARN da LabRole, unica role utilizavel no Learner Lab."
  value       = data.aws_iam_role.lab.arn
}

output "azs" {
  description = "Zonas de disponibilidade em uso."
  value       = local.azs
}

output "jwt_secret_name" {
  description = "Nome do secret com a chave de assinatura do JWT. Consumido pela Lambda, pelo authorizer e pela API - nunca o valor."
  value       = aws_secretsmanager_secret.jwt_signing_key.name
}

output "jwt_secret_arn" {
  description = "ARN do secret da chave de assinatura do JWT."
  value       = aws_secretsmanager_secret.jwt_signing_key.arn
}

output "gateway_url" {
  description = "URL base do API Gateway. Rota de autenticacao: POST <url>/auth."
  value       = aws_apigatewayv2_stage.principal.invoke_url
}

output "gateway_api_id" {
  description = "Id do HTTP API. Consumido pela issue #43 ao criar o authorizer."
  value       = aws_apigatewayv2_api.principal.id
}

output "gateway_rotas_do_cluster_ativas" {
  description = "Falso enquanto alb_listener_arn estiver vazio: so a rota de autenticacao existe."
  value       = local.integrar_cluster
}

output "sg_endpoints" {
  description = "Security group dos endpoints de interface da VPC."
  value       = aws_security_group.endpoints.id
}

output "endpoint_secrets_manager" {
  description = "Id do endpoint de interface do Secrets Manager. A Lambda na VPC depende dele para ler segredos."
  value       = aws_vpc_endpoint.secrets_manager.id
}

# ------------------------------------------------------------------ cluster
#
# Nulos enquanto criar_cluster estiver desligado. Quem consome deve tratar isso,
# em vez de assumir que o cluster existe.

output "cluster_existe" {
  description = "Se o cluster EKS foi provisionado neste ambiente."
  value       = var.criar_cluster
}

output "cluster_nome" {
  description = "Nome do cluster EKS. Usado no `aws eks update-kubeconfig` das pipelines."
  value       = one(aws_eks_cluster.principal[*].name)
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster."
  value       = one(aws_eks_cluster.principal[*].endpoint)
}

output "cluster_oidc_issuer" {
  description = "Issuer OIDC do cluster, base para IRSA."
  value       = one(aws_eks_cluster.principal[*].identity[0].oidc[0].issuer)
}

output "cluster_kubeconfig_comando" {
  description = "Comando que gera o kubeconfig. E assim que as pipelines se conectam ao cluster."
  value = var.criar_cluster ? join(" ", [
    "aws eks update-kubeconfig",
    "--region ${var.region}",
    "--name ${aws_eks_cluster.principal[0].name}"
  ]) : null
}

output "nat_ip_publico" {
  description = "IP fixo de saida das subnets privadas. Util para liberar em firewall de terceiros."
  value       = one(aws_eip.nat[*].public_ip)
}
