terraform {
  backend "s3" {
    bucket         = "itay-project-terraform-state"
    key            = "prod/platform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}