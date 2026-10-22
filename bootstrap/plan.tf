# 이 저장소의 PR에서 terraform plan만 도는 역할 (CAREER-25, 2026-10-22 사용자 결정)
# - 왜: main에 머지하면 deploy.yml이 바로 apply한다 → 머지 전에 무엇이 바뀌는지 PR에서 먼저 본다
# - 읽기 전용 + 이 저장소 state 읽기 + 잠금 파일만 쓰기. apply는 여전히 main의 github-actions-deploy만
# OIDC 공급자는 oidc.tf의 것을 같이 쓴다.

locals {
  portfolio_repo_sub = "repo:culonculon@162904282/aws-infra-portfolio@1400854727" # 바뀌지 않는 subject(소유자·저장소 ID)
}

resource "aws_iam_role" "portfolio_plan" {
  name = "github-actions-portfolio-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PortfolioPullRequestOnly"
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${local.portfolio_repo_sub}:pull_request"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "portfolio_plan_readonly" {
  role       = aws_iam_role.portfolio_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "portfolio_plan_state" {
  name = "portfolio-plan-state"
  role = aws_iam_role.portfolio_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PortfolioStateList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.tfstate.arn
      },
      {
        Sid      = "PortfolioStateRead"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.tfstate.arn}/infra/*"
      },
      {
        # plan도 잠금 파일을 만들고 지운다(use_lockfile)
        Sid      = "PortfolioStateLock"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tfstate.arn}/infra/*.tflock"
      },
    ]
  })
}

output "portfolio_plan_role_arn" {
  value = aws_iam_role.portfolio_plan.arn
}
