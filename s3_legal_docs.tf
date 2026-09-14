resource "aws_kms_key" "legal_docs_key" {
  description             = "KMS key for encrypting legal escalation documents"
  deletion_window_in_days = 7

  tags = {
    Project = "crm-portfolio"
  }
}

resource "aws_s3_bucket" "legal_documents" {
  bucket = "crm-legal-documents-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project = "crm-portfolio"
  }
}

resource "aws_s3_bucket_public_access_block" "legal_documents_block" {
  bucket = aws_s3_bucket.legal_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "legal_documents_encryption" {
  bucket = aws_s3_bucket.legal_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.legal_docs_key.arn
    }
    bucket_key_enabled = true
  }
}

data "aws_caller_identity" "current" {}