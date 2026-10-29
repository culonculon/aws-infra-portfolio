# (옆) AWS가 미리 만들어 둔 캐시 규칙 — 읽기만
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# (옆) how-much 감정 입구 /api/* 는 캐시하지 않음 — 읽기만
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# how-much /api/* 가 원본에 넘길 것: 쿼리 전부 + 헤더 둘(how-much contracts/deploy.md §3)
# CloudFront-Viewer-Address = 사람별 요청 수 제한의 '사람'(how-much ADR-0006). 쿠키 없음
resource "aws_cloudfront_origin_request_policy" "how_much_api" {
  name    = "how-much-api"
  comment = "how-much /api/*: all query strings, Content-Type, CloudFront-Viewer-Address"

  cookies_config {
    cookie_behavior = "none"
  }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Content-Type", "CloudFront-Viewer-Address"]
    }
  }
  query_strings_config {
    query_string_behavior = "all"
  }
}

# 4. 전용 출입문: CloudFront → 프라이빗 서버 (AWS 내부망으로만)
resource "aws_cloudfront_vpc_origin" "web" {
  vpc_origin_endpoint_config {
    name                   = "portfolio-web"
    arn                    = aws_instance.web.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    # http-only라 실제로 안 쓰이지만 필수 항목
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

# 5. 앞문: 방문자가 들어오는 주소
resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  comment             = "portfolio-web"
  default_root_object = "index.html"
  price_class         = "PriceClass_200" # 한국 포함, 가장 비싼 지역 제외

  # 원본 주소록: 302호(서버 주소)로, 전용 출입문을 통해
  origin {
    origin_id   = "portfolio-web"
    domain_name = aws_instance.web.private_dns

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.web.id
    }
  }

  # 기본 규칙: 모든 주소 → 위 원본으로
  default_cache_behavior {
    target_origin_id       = "portfolio-web"
    viewer_protocol_policy = "redirect-to-https" # http로 오면 https로 돌려보냄
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true
  }

  # how-much 감정 입구: /api/* → 같은 원본(서버 nginx가 같은 컴퓨터의 api로 넘김). 이 동작이 생기는 때 = 공개
  # 원본·기본 동작은 바꾸지 않는다. 원본 응답 시간 제한은 원본 기본 30초(how-much contracts/deploy.md §3)
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "portfolio-web"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.how_much_api.id
    compress                 = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # xxxx.cloudfront.net 주소용 기본 인증서
  }
}

# 6. 완성된 주소 출력
output "web_url" {
  value = "https://${aws_cloudfront_distribution.web.domain_name}"
}