# GitHub를 신분증 발급처로 등록 ("GitHub 도장은 믿는다")
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com" # 신분증의 iss (발급처)
  client_id_list = ["sts.amazonaws.com"]                         # 신분증의 aud (AWS STS용)
  # thumbprint는 생략: AWS가 GitHub 인증서를 직접 확인
}

# GitHub Actions가 쓰는 배포 역할
resource "aws_iam_role" "github_deploy" {
  name = "github-actions-deploy"

  # 도어락 명단: 내 저장소의 main에서 온 신분증만 들어옴
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubMainOnly"
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:culonculon@162904282/aws-infra-portfolio@1400854727:ref:refs/heads/main" # 진짜 자물쇠
        }
      }
    }]
  })
}

# 역할에 권한 붙이기 (v1은 Admin, v2에서 좁힘)
resource "aws_iam_role_policy_attachment" "github_deploy_admin" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 워크플로에 넣을 역할 주소 출력
output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}