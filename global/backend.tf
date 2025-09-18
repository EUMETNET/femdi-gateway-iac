terraform {
  backend "s3" {
    bucket  = "meteogate-iac-terraform-states"
    key     = "global/terraform.tfstate"
    region  = "eu-north-1"
    profile = "fmi_meteogate"
  }
}