# how-much 저장소용 (CAREER-23, 2026-10-20 사용자 결정)
# - state 버킷: 포트폴리오와 같은 설정, 잠금은 S3 잠금 파일(use_lockfile)
# - plan 역할: how-much의 PR에서만, 읽기 전용 + 포트폴리오 state 읽기 금지
# OIDC 공급자는 oidc.tf의 것을 같이 쓴다.

locals {
  how_much_repo_sub = "repo:culonculon@162904282/how-much@1426358191" # 바뀌지 않는 subject(소유자·저장소 ID)
}

resource "aws_s3_bucket" "how_much_tfstate" {
  bucket = "culonculon-how-much-tfstate"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "how_much_tfstate" {
  bucket = aws_s3_bucket.how_much_tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "how_much_tfstate" {
  bucket = aws_s3_bucket.how_much_tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "how_much_tfstate" {
  bucket                  = aws_s3_bucket.how_much_tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# PR에서 terraform plan만 도는 역할 (apply 역할은 나중에 따로)
resource "aws_iam_role" "how_much_plan" {
  name = "github-actions-how-much-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "HowMuchPullRequestOnly"
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${local.how_much_repo_sub}:pull_request"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "how_much_plan_readonly" {
  role       = aws_iam_role.how_much_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "how_much_plan_state" {
  name = "how-much-plan-state"
  role = aws_iam_role.how_much_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ReadOnlyAccess는 S3 객체도 읽을 수 있다 — 비밀이 든 포트폴리오 state는 막는다
        Sid      = "DenyOtherState"
        Effect   = "Deny"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.tfstate.arn}/*"
      },
      {
        Sid      = "HowMuchStateList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.how_much_tfstate.arn
      },
      {
        Sid      = "HowMuchStateRead"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.how_much_tfstate.arn}/*"
      },
      {
        # plan도 잠금 파일을 만들고 지운다(use_lockfile)
        Sid      = "HowMuchStateLock"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.how_much_tfstate.arn}/*.tflock"
      },
    ]
  })
}

output "how_much_plan_role_arn" {
  value = aws_iam_role.how_much_plan.arn
}

output "how_much_tfstate_bucket" {
  value = aws_s3_bucket.how_much_tfstate.bucket
}

# ── how-much 배포 역할 (CAREER-30, how-much plan D4·D5 · ADR-0007) ──────────────────
# how-much의 수동 배포 워크플로(.github/workflows/deploy.yml)만, GitHub 환경 production에서만 받는다.
# 할 수 있는 일: 그 EIC로 그 서버 22번 터널 · 그 서버에 ec2-user 키 60초 밀어 넣기 · 그 CloudFront 배포 무효화. S3·관리형 정책 없음
# 이 역할로 서버에서 sudo가 되므로(install-release.sh) 좁게 둔다. infra/ state와 따로라 EIC·배포는 변수로, 서버는 Name 태그로 찾는다

variable "how_much_eic_endpoint_id" {
  description = "infra 출력 eic_endpoint_id (eice-…) — PR #3 apply 뒤 값"
  type        = string
}

variable "how_much_cf_distribution_id" {
  description = "v1 CloudFront 배포 id (portfolio-web)"
  type        = string
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_instance" "web" {
  filter {
    name   = "tag:Name"
    values = ["portfolio-web"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

locals {
  how_much_eic_arn      = "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:instance-connect-endpoint/${var.how_much_eic_endpoint_id}"
  how_much_instance_arn = "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:instance/${data.aws_instance.web.id}"
  how_much_cf_arn       = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${var.how_much_cf_distribution_id}"
}

resource "aws_iam_role" "how_much_deploy" {
  name = "github-actions-how-much-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "HowMuchProductionEnvironmentOnly"
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${local.how_much_repo_sub}:environment:production"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "how_much_deploy" {
  name = "how-much-deploy"
  role = aws_iam_role.how_much_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 그 EIC로, 그 서버의 사설 IP 22번만, 터널 1시간 이하
        Sid      = "TunnelToWebSsh"
        Effect   = "Allow"
        Action   = "ec2-instance-connect:OpenTunnel"
        Resource = local.how_much_eic_arn
        Condition = {
          NumericEquals         = { "ec2-instance-connect:remotePort" = "22" }
          IpAddress             = { "ec2-instance-connect:privateIpAddress" = "${data.aws_instance.web.private_ip}/32" }
          NumericLessThanEquals = { "ec2-instance-connect:maxTunnelDuration" = "3600" }
        }
      },
      {
        # 그 서버에 ec2-user 키만 (60초)
        Sid       = "PushKeyToWebEc2User"
        Effect    = "Allow"
        Action    = "ec2-instance-connect:SendSSHPublicKey"
        Resource  = local.how_much_instance_arn
        Condition = { StringEquals = { "ec2:osuser" = "ec2-user" } }
      },
      {
        Sid      = "InvalidateWebDistribution"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = local.how_much_cf_arn
      },
    ]
  })
}

output "how_much_deploy_role_arn" {
  value = aws_iam_role.how_much_deploy.arn
}
