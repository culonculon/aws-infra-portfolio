# (옆) AWS가 미리 만들어 둔 캐시 규칙 — 읽기만
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
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