# 장부(state) 버킷 2곳을 암호화하는 고객 관리 키 (CAREER-28, 2026-11-04 사용자 결정 — trivy AWS-0132)
# - 키 하나를 두 버킷(포트폴리오 · how-much)이 같이 쓴다. 키 월 $1 + 요청 소액
# - 버킷 키(bucket_key_enabled)를 켜서 KMS 요청을 줄인다
# - 키 정책은 기본값: 이 계정의 IAM 정책이 권한을 정한다. 역할마다 필요한 kms 동작은 그 역할 정책에 둔다
#   (github-actions-deploy는 Admin이라 따로 안 둠 · plan 역할 둘은 plan.tf · how-much.tf)
# - 이미 AES256으로 들어 있는 장부 파일은 그대로 읽힌다. 다음에 쓸 때부터 이 키로 암호화된다

resource "aws_kms_key" "tfstate" {
  description             = "terraform state buckets (portfolio, how-much)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  # 이 키를 지우면 장부를 못 읽는다
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/tfstate"
  target_key_id = aws_kms_key.tfstate.key_id
}
