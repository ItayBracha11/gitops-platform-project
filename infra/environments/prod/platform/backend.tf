terraform {
  backend "s3" {
    bucket         = "itay-project-terraform-state"
    key            = "prod/platform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}