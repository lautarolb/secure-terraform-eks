terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend remoto (Opción B - partial config).
  # Solo lo NO sensible va acá (se commitea). El resto (bucket, region,
  # profile) va en backend.hcl, que NO se commitea, y se pasa con:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # lock nativo de S3 (.tflock); reemplaza a DynamoDB
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  # Buena práctica: etiquetar TODO lo que cree este provider.
  default_tags {
    tags = {
      Project   = "secure-terraform-eks"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

#tfsec:ignore:aws-s3-enable-bucket-logging
#checkov:skip=CKV_AWS_18:logging del propio bucket de state pendiente, bajo impacto
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name # leemos el nombre desde la variable
}

resource "aws_s3_bucket_versioning" "bucket-configuration-versionning" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}


#tfsec:ignore:aws-s3-encryption-customer-key
#checkov:skip=CKV_AWS_19:SSE con AES256 alcanza por ahora, CMK/KMS pendiente
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket-cfg-sse" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "policy_block_public" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
