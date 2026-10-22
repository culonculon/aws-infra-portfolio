# how-much 감정 서버(CAREER-25) → Amazon Bedrock Nova Pro로 가는 길. 결정: how-much ADR-0002
# NAT 없이 bedrock-runtime만 여는 인터페이스 엔드포인트 하나(AZ 1개 — 서버가 있는 서브넷)

locals {
  # 서울은 교차 리전 프로필 — 요청이 다른 아시아 리전에서 처리될 수 있음
  nova_pro_profile_id = "apac.amazon.nova-pro-v1:0"
}

# 프로필이 보내는 리전별 기반 모델 목록을 손으로 적지 않고 읽어 옴
data "aws_bedrock_inference_profile" "nova_pro" {
  inference_profile_id = local.nova_pro_profile_id
}

# 엔드포인트 방화벽: 웹 서버에서 오는 443만
resource "aws_security_group" "bedrock_endpoint" {
  name        = "portfolio-bedrock-endpoint"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTPS from the web server to the Bedrock runtime endpoint"
}

resource "aws_vpc_security_group_ingress_rule" "bedrock_from_web" {
  security_group_id            = aws_security_group.bedrock_endpoint.id
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from portfolio-web"
}

# 웹 서버 나가기: 엔드포인트로 443번 (기본 '모두 나가기'는 없음 — server.tf)
resource "aws_vpc_security_group_egress_rule" "https_to_bedrock" {
  security_group_id            = aws_security_group.web.id
  referenced_security_group_id = aws_security_group.bedrock_endpoint.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS to the Bedrock runtime endpoint"
}

# private DNS가 기본 주소(bedrock-runtime.ap-northeast-2.amazonaws.com)를 가로챔 → 앱은 주소 설정 없음
resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ap-northeast-2.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.bedrock_endpoint.id]

  tags = {
    Name = "portfolio-bedrock-runtime"
  }
}

# 서버 역할: Nova Pro 부르기 하나만 (키 없이 인스턴스 역할로)
resource "aws_iam_role" "web" {
  name = "portfolio-web"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "web" {
  name = "portfolio-web"
  role = aws_iam_role.web.name
}

resource "aws_iam_role_policy" "web_invoke_nova_pro" {
  name = "invoke-nova-pro"
  role = aws_iam_role.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeThroughProfile"
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = data.aws_bedrock_inference_profile.nova_pro.inference_profile_arn
      },
      {
        # 기반 모델은 프로필을 거칠 때만 (직접 부르기 막음)
        Sid      = "InvokeModelsBehindProfile"
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = [for m in data.aws_bedrock_inference_profile.nova_pro.models : m.model_arn]
        Condition = {
          StringEquals = {
            "bedrock:InferenceProfileArn" = data.aws_bedrock_inference_profile.nova_pro.inference_profile_arn
          }
        }
      },
    ]
  })
}
