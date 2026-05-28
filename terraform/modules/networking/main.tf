# ----------------------------------------------------------------------
# VPC
# ----------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project}-vpc"
  }
}

# ----------------------------------------------------------------------
# Private subnets (one per AZ)
# ----------------------------------------------------------------------
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}

# ----------------------------------------------------------------------
# Route table for private subnets (no IGW, no NAT)
# ----------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "${var.project}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ----------------------------------------------------------------------
# Security groups
# ----------------------------------------------------------------------
resource "aws_security_group" "lambda" {
  name        = "${var.project}-lambda-sg"
  description = "Lambda functions running inside the VPC"
  vpc_id      = aws_vpc.this.id

  # Aurora - scoped to VPC only
  egress {
    description = "Postgres to Aurora"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  # HTTPS to VPC interface endpoints (bedrock-runtime, secretsmanager, logs)
  egress {
    description = "HTTPS to VPC interface endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  # HTTPS to S3 and DynamoDB gateway endpoints.
  # Gateway endpoints route at the routing layer but the source SG still
  # needs an outbound rule matching the destination IPs (S3/DynamoDB use
  # public IP ranges even when accessed via gateway endpoint).
  egress {
    description = "HTTPS to S3 and DynamoDB via gateway endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-lambda-sg" }
}

resource "aws_security_group" "aurora" {
  name        = "${var.project}-aurora-sg"
  description = "Aurora Serverless v2 cluster"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Postgres from Lambda SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  tags = { Name = "${var.project}-aurora-sg" }
}

resource "aws_security_group" "endpoints" {
  name        = "${var.project}-endpoints-sg"
  description = "VPC interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from inside VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  tags = { Name = "${var.project}-endpoints-sg" }
}

# ----------------------------------------------------------------------
# Gateway endpoints (free)
# ----------------------------------------------------------------------
data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.project}-s3-endpoint" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.project}-dynamodb-endpoint" }
}

# ----------------------------------------------------------------------
# Interface endpoints (hourly cost)
# ----------------------------------------------------------------------
locals {
  interface_endpoints = [
    "bedrock-runtime",
    "secretsmanager",
    "logs",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-${each.key}-endpoint" }
}
