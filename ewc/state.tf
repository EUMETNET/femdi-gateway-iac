terraform {
  backend "s3" {
    bucket  = "femdi-gateway-iac-terraform-state"
    key     = "terraform-state/state"
    region  = "eu-north-1"
    profile = "femdi-iac"
  }
}
