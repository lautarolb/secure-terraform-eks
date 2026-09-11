variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI local (se provee por terraform.tfvars). Vacío en CI: usa las credenciales OIDC del entorno en vez de un perfil nombrado."
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "state_bucket" {
  description = "Bucket S3 del remote state (mismo valor que backend.hcl) - se provee por terraform.tfvars"
  type        = string
}
