# 장부(state)를 보관할 버킷
resource "aws_s3_bucket" "tfstate" {
  bucket = "culonculon-tfstate-1"   # 전 세계에서 하나뿐이어야 함

  # destroy를 해도 이 버킷은 지워지지 않게 막음
  lifecycle {
    prevent_destroy = true
  }
}

# 버전 관리: 장부를 덮어써도 이전 버전으로 되살릴 수 있음
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


# 공개 접근 차단 (장부에는 비밀이 들어 있음)
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}