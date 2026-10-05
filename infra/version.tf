terraform {
  required_version = "~> 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # 장부를 bootstrap에서 만든 S3 버킷에 보관
  backend "s3" {
    bucket       = "culonculon-aws-infra-portfolio-tfstate"
    key          = "infra/terraform.tfstate" # 버킷 안 경로
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true # S3에 잠금 파일을 만들어 동시 실행을 막음
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = "infra"
    }
  }
}