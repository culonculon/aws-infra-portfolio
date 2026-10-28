locals {
  # AL2023 · kernel 6.12 · arm64 — al2023-ami-2023.12.20260930.0-kernel-6.12-arm64 (2026-09-29)
  # 바꿀 때는 get-parameter로 새 번호를 받아 PR로 교체 (서버는 새로 만들어짐)
  web_ami_id = "ami-0d8d71a28c118c486"
}

# AWS가 관리하는 주소 목록 (내 리소스 아님, 읽기만)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_ec2_managed_prefix_list" "s3" {
  name = "com.amazonaws.ap-northeast-2.s3"
}

# 서버 방화벽 (기본 '모두 나가기' 규칙은 Terraform이 지움)
resource "aws_security_group" "web" {
  name        = "portfolio-web"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTP from CloudFront, HTTPS to S3"

}

# 들어오기: CloudFront에서 80번만
resource "aws_vpc_security_group_ingress_rule" "http_from_cloudfront" {
  security_group_id = aws_security_group.web.id
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# 나가기: S3로 443번만 (dnf 패키지 저장소가 S3에 있음)
resource "aws_vpc_security_group_egress_rule" "https_to_s3" {
  security_group_id = aws_security_group.web.id
  prefix_list_id    = data.aws_ec2_managed_prefix_list.s3.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_instance" "web" {
  ami                    = local.web_ami_id
  instance_type          = "t4g.small"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name # Bedrock 부르기(bedrock.tf) — 붙여도 서버는 그대로


  # CPU 크레딧을 넘겨 써도 추가 요금이 안 나가게 (t4g 기본값은 unlimited)
  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_tokens = "required" # IMDSv2만 허용
  }

  root_block_device {
    encrypted = true
  }

  # 처음 켤 때 한 번만 실행 (v1은 인라인, 다음엔 파일/이미지로)
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
  EOF

  # user_data가 바뀌면 서버를 새로 만듦 (고친 스크립트가 실제로 반영되게)
  user_data_replace_on_change = true

  tags = {
    Name = "portfolio-web"
  }

  # 서버 교체·삭제 막기(CAREER-30, how-much plan D7) — 루트 디스크 홈에 how-much 하루 셈 파일이 있다.
  # user_data·AMI를 바꾸면 교체 plan이 생기는데, 그때 plan이 오류로 멈춘다. v1을 내리려면 이 줄을 먼저 지우는 PR이 필요하다
  lifecycle {
    prevent_destroy = true
  }
}

