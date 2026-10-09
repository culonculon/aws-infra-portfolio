# 내 전용 네트워크
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true # VPC 안에서 이름(주소) 찾기
}

# VPC 오리진 요구 사항: VPC에 인터넷 게이트웨이가 있어야 함
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id # ← "VPC의 id가 필요해" → VPC를 먼저 만들어야 함
}

# 서버가 들어갈 프라이빗 서브넷 (공인 IP 안 줌)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false
}

# 길 안내판: 인터넷으로 가는 길(0.0.0.0/0)은 일부러 만들지 않음
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# 출구: S3로만 가는 무료 지름길 (안내판에 자동으로 한 줄 추가됨)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.ap-northeast-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  # 이 지름길로는 AL2023 패키지 저장소만, 읽기만 허용
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AL2023RepoReadOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::al2023-repos-ap-northeast-2-de612dc2/*"
    }]
  })

}