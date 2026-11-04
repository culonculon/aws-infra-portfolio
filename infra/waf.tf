# CloudFront 앞 WAF (CAREER-28, 2026-11-04 사용자 결정 — trivy AWS-0011)
# - CloudFront에 붙는 웹 ACL은 us-east-1에만 만들 수 있다 → 그 리전 provider를 따로 둔다
# - 규칙은 2개만: 월 약 $7(웹 ACL $5 + 규칙 $1 × 2 + 요청 100만 건당 $0.6)
#   1) AWS 관리형 IP 평판 목록 — 요청 본문을 보지 않아 사진 업로드를 잘못 막을 일이 없다
#   2) /api/* 를 한 IP가 5분에 100번 넘게 부르면 막기 — 감정 1번 = 요청 1번(how-much app/src/appraise.js)
#      하루 감정 한도(how-much ADR-0006) 앞의 거친 바깥 울타리. 휴대폰은 여러 사람이 IP 하나를 같이 쓰므로 넉넉히 둔다
# - 공통 규칙 묶음(AWSManagedRulesCommonRuleSet)은 넣지 않음: 감정 입구는 본문이 JPEG 그대로(최대 1MB)라
#   본문 8KB 크기 규칙 · 본문 XSS 규칙이 정상 업로드를 막을 수 있다
# - WAF 로그는 켜지 않음(비용) — CloudWatch 지표와 표본 요청만

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = "infra"
    }
  }
}

resource "aws_wafv2_web_acl" "web" {
  provider = aws.us_east_1

  name        = "portfolio-web"
  description = "CloudFront portfolio-web: IP reputation + /api/* rate limit"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-ip-reputation"
    priority = 0

    override_action {
      none {} # 관리형 규칙의 동작(막기)을 그대로 쓴다
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "api-rate-per-ip"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = 100
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string         = "/api/"
            positional_constraint = "STARTS_WITH"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "api-rate-per-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "portfolio-web"
    sampled_requests_enabled   = true
  }
}
