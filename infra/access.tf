# how-much 서버에 들어가는 운영 길(CAREER-30, how-much plan D3 · ADR-0007)
# EC2 Instance Connect Endpoint — 공인 IP·NAT·배스천 없이 프라이빗 서버에 ssh. 엔드포인트 요금 0
# 키는 그때그때 send-ssh-public-key로 60초만 밀어 넣는다(서버에 키 파일 없음)

# EIC 방화벽: 들어오기 없음 · 나가기는 웹 서버 22만
resource "aws_security_group" "eic" {
  name        = "portfolio-eic"
  vpc_id      = aws_vpc.main.id
  description = "EC2 Instance Connect Endpoint - SSH to the web server only"
}

resource "aws_vpc_security_group_egress_rule" "eic_ssh_to_web" {
  security_group_id            = aws_security_group.eic.id
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  description                  = "SSH to portfolio-web"
}

# 웹 서버 들어오기: EIC에서 22만 (인터넷 주소 범위에서 오는 규칙 아님)
resource "aws_vpc_security_group_ingress_rule" "ssh_from_eic" {
  security_group_id            = aws_security_group.web.id
  referenced_security_group_id = aws_security_group.eic.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  description                  = "SSH from the EC2 Instance Connect Endpoint"
}

resource "aws_ec2_instance_connect_endpoint" "main" {
  subnet_id          = aws_subnet.private.id
  security_group_ids = [aws_security_group.eic.id]
  preserve_client_ip = false # 출처가 EIC 보안 그룹이 되어 위 22 규칙과 맞는다

  tags = {
    Name = "portfolio-eic"
  }
}

output "eic_endpoint_id" {
  value = aws_ec2_instance_connect_endpoint.main.id
}

output "web_instance_id" {
  value = aws_instance.web.id
}

# how-much 저장소 변수 EIC_DNS_NAME · DEPLOY_PRIVATE_IP용(터널을 열 때 Describe 없이 — how-much PR #17)
output "eic_dns_name" {
  value = aws_ec2_instance_connect_endpoint.main.dns_name
}

output "web_private_ip" {
  value = aws_instance.web.private_ip
}
