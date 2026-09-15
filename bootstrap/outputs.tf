output "state_bucket" {
  description = "Bucket S3 que guarda o state. Use no -backend-config dos outros modulos."
  value       = aws_s3_bucket.tfstate.id
}

output "lock_table" {
  description = "Tabela DynamoDB usada para lock do state."
  value       = aws_dynamodb_table.tflock.name
}

output "backend_config" {
  description = "Comando pronto para inicializar os outros modulos com este backend."
  value       = <<-CMD
    terraform init \
      -backend-config="bucket=${aws_s3_bucket.tfstate.id}" \
      -backend-config="dynamodb_table=${aws_dynamodb_table.tflock.name}" \
      -backend-config="region=${var.region}" \
      -backend-config="key=<ambiente>/<modulo>.tfstate"
  CMD
}
