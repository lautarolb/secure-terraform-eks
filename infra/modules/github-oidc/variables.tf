variable "github_repo" {
  description = "Repo de GitHub (owner/name) habilitado a asumir el role de CI via OIDC"
  type        = string
  default     = "lautarolopez4/secure-terraform-eks"
}

variable "state_bucket" {
  description = "Bucket S3 del remote state, para acotar el permiso de lectura del state a este bucket puntual"
  type        = string
}
