terraform {
  # 이 코드를 실행할 수 있는 Terraform 프로그램 버전
  required_version = "~> 1.13"

  # 이 코드가 쓰는 확장팩(provider)과 허용 버전
  required_providers {
    aws = {
      source  = "hashicorp/aws" # 어디서 받아 올지 (Terraform Registry 주소)
      version = "~> 6.0"        # 6점대만 허용
    }
  }
}

provider "aws" {
  region = "ap-northeast-2" # 서울

  # 이 폴더에서 만드는 모든 자원에 자동으로 붙는 이름표
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}