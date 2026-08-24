# O id da conta vem do data source em vez de ser escrito no codigo:
# os quatro repositorios sao publicos.
data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  table_name  = "${var.project}-tflock"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # A conta do Learner Lab e reciclada entre turmas. force_destroy evita
  # que a limpeza final trave por causa de versoes antigas de state.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  # Versionamento e o que permite recuperar um state corrompido.
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  # O state guarda endpoints, ARNs e atributos sensiveis em texto claro.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tflock" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
