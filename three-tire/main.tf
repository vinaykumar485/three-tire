terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.66.1"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "three_tier" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "three-tier-vpc"
  }
}

# ============================================================
# INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.three_tier.id

  tags = {
    Name = "three-tier-igw"
  }
}

# ============================================================
# PUBLIC SUBNETS
# ALB
# ============================================================

resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.three_tier.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "three-tier-public-az1"
    Tier = "public"
  }
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.three_tier.id
  cidr_block              = "10.20.4.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "three-tier-public-az2"
    Tier = "public"
  }
}

# ============================================================
# APPLICATION PRIVATE SUBNETS
# ============================================================

resource "aws_subnet" "app_az1" {
  vpc_id            = aws_vpc.three_tier.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "three-tier-app-az1"
    Tier = "application"
  }
}

resource "aws_subnet" "app_az2" {
  vpc_id            = aws_vpc.three_tier.id
  cidr_block        = "10.20.5.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "three-tier-app-az2"
    Tier = "application"
  }
}

# ============================================================
# DATABASE PRIVATE SUBNETS
# ============================================================

resource "aws_subnet" "db_az1" {
  vpc_id            = aws_vpc.three_tier.id
  cidr_block        = "10.20.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "three-tier-db-az1"
    Tier = "database"
  }
}

resource "aws_subnet" "db_az2" {
  vpc_id            = aws_vpc.three_tier.id
  cidr_block        = "10.20.6.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "three-tier-db-az2"
    Tier = "database"
  }
}

# ============================================================
# PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.three_tier.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "three-tier-public-rt"
  }
}

resource "aws_route_table_association" "public_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# NAT GATEWAY
# ============================================================

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "three-tier-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_az1.id

  depends_on = [
    aws_internet_gateway.igw
  ]

  tags = {
    Name = "three-tier-nat"
  }
}

# ============================================================
# APPLICATION ROUTE TABLE
# PRIVATE APP -> NAT -> INTERNET
# ============================================================

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.three_tier.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "three-tier-app-rt"
  }
}

resource "aws_route_table_association" "app_az1" {
  subnet_id      = aws_subnet.app_az1.id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table_association" "app_az2" {
  subnet_id      = aws_subnet.app_az2.id
  route_table_id = aws_route_table.app.id
}

# ============================================================
# DATABASE ROUTE TABLE
# NO INTERNET ROUTE
# ============================================================

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.three_tier.id

  tags = {
    Name = "three-tier-db-rt"
  }
}

resource "aws_route_table_association" "db_az1" {
  subnet_id      = aws_subnet.db_az1.id
  route_table_id = aws_route_table.database.id
}

resource "aws_route_table_association" "db_az2" {
  subnet_id      = aws_subnet.db_az2.id
  route_table_id = aws_route_table.database.id
}

# ============================================================
# ALB SECURITY GROUP
# ALB LISTENS ON 8088
# ============================================================

resource "aws_security_group" "alb_sg" {
  name        = "three-tier-alb-sg"
  description = "Security group for three tier ALB"
  vpc_id      = aws_vpc.three_tier.id

  ingress {
    description = "HTTP from Internet on 8088"
    from_port   = 8088
    to_port     = 8088
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "three-tier-alb-sg"
    Tier = "load-balancer"
  }
}

# ============================================================
# APPLICATION SECURITY GROUP
# ALB -> EC2 ON 8090
# ============================================================

resource "aws_security_group" "app_sg" {
  name        = "three-tier-app-sg"
  description = "Security group for application tier"
  vpc_id      = aws_vpc.three_tier.id

  ingress {
    description     = "ALB to application on 8090"
    from_port       = 8090
    to_port         = 8090
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "SSH from administrator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "three-tier-app-sg"
    Tier = "application"
  }
}

# ============================================================
# DATABASE SECURITY GROUP
# APP -> RDS ON 3307
# ============================================================

resource "aws_security_group" "db_sg" {
  name        = "three-tier-db-sg"
  description = "Security group for database tier"
  vpc_id      = aws_vpc.three_tier.id

  ingress {
    description     = "Application to MySQL on 3307"
    from_port       = 3307
    to_port         = 3307
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    description = "Allow outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "three-tier-db-sg"
    Tier = "database"
  }
}

# ============================================================
# EC2 APP SERVER AZ1
# Ubuntu 24.04
# ============================================================

resource "aws_instance" "app_az1" {
  ami                    = "ami-0c7217cdde317cfec"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.app_az1.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx

              cat > /etc/nginx/sites-available/default <<'NGINX'
              server {
                  listen 8090;
                  server_name _;

                  location / {
                      default_type text/html;
                      return 200 '<html>
                      <body>
                      <h1>Three Tier Architecture</h1>
                      <h2>Application Server - AZ1</h2>
                      <p>Application Port: 8090</p>
                      </body>
                      </html>';
                  }
              }
              NGINX

              systemctl restart nginx
              systemctl enable nginx
              EOF

  tags = {
    Name = "three-tier-app-az1"
    Tier = "application"
  }
}

# ============================================================
# EC2 APP SERVER AZ2
# ============================================================

resource "aws_instance" "app_az2" {
  ami                    = "ami-0c7217cdde317cfec"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.app_az2.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx

              cat > /etc/nginx/sites-available/default <<'NGINX'
              server {
                  listen 8090;
                  server_name _;

                  location / {
                      default_type text/html;
                      return 200 '<html>
                      <body>
                      <h1>Three Tier Architecture</h1>
                      <h2>Application Server - AZ2</h2>
                      <p>Application Port: 8090</p>
                      </body>
                      </html>';
                  }
              }
              NGINX

              systemctl restart nginx
              systemctl enable nginx
              EOF

  tags = {
    Name = "three-tier-app-az2"
    Tier = "application"
  }
}

# ============================================================
# APPLICATION LOAD BALANCER
# ============================================================

resource "aws_lb" "three_tier_alb" {
  name               = "three-tier-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb_sg.id
  ]

  subnets = [
    aws_subnet.public_az1.id,
    aws_subnet.public_az2.id
  ]

  tags = {
    Name = "three-tier-alb"
    Tier = "load-balancer"
  }
}

# ============================================================
# TARGET GROUP
# EC2 PORT = 8090
# ============================================================

resource "aws_lb_target_group" "app" {
  name        = "three-tier-app-tg"
  port        = 8090
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.three_tier.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "8090"
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = {
    Name = "three-tier-app-tg"
  }
}

# ============================================================
# TARGET AZ1
# ============================================================

resource "aws_lb_target_group_attachment" "app_az1" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app_az1.id
  port             = 8090
}

# ============================================================
# TARGET AZ2
# ============================================================

resource "aws_lb_target_group_attachment" "app_az2" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app_az2.id
  port             = 8090
}

# ============================================================
# ALB LISTENER
# INTERNET -> ALB :8088
# ============================================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.three_tier_alb.arn
  port              = 8088
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ============================================================
# RDS SUBNET GROUP
# ============================================================

resource "aws_db_subnet_group" "mysql" {
  name = "three-tier-db-subnet-group"

  subnet_ids = [
    aws_subnet.db_az1.id,
    aws_subnet.db_az2.id
  ]

  tags = {
    Name = "three-tier-db-subnet-group"
  }
}

# ============================================================
# RDS MYSQL
# PORT = 3307
# ============================================================

resource "aws_db_instance" "mysql" {
  identifier = "three-tier-mysql"

  engine         = "mysql"
  engine_version = "8.0"

  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"

  db_name  = "three_tier_db"
  username = "admin"
  password = "ThreeTierDB2026!"

  port = 3307

  db_subnet_group_name = aws_db_subnet_group.mysql.name

  vpc_security_group_ids = [
    aws_security_group.db_sg.id
  ]

  publicly_accessible = false

  multi_az = false

  backup_retention_period = 0

  deletion_protection = false

  skip_final_snapshot = true

  tags = {
    Name = "three-tier-mysql"
    Tier = "database"
  }
}

# ============================================================
# OUTPUTS
# ============================================================

output "vpc_id" {
  value = aws_vpc.three_tier.id
}

output "public_subnet_ids" {
  value = [
    aws_subnet.public_az1.id,
    aws_subnet.public_az2.id
  ]
}

output "app_subnet_ids" {
  value = [
    aws_subnet.app_az1.id,
    aws_subnet.app_az2.id
  ]
}

output "database_subnet_ids" {
  value = [
    aws_subnet.db_az1.id,
    aws_subnet.db_az2.id
  ]
}

output "app_private_ips" {
  value = [
    aws_instance.app_az1.private_ip,
    aws_instance.app_az2.private_ip
  ]
}

output "alb_dns_name" {
  value = aws_lb.three_tier_alb.dns_name
}

output "application_url" {
  value = "http://${aws_lb.three_tier_alb.dns_name}:8088"
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

output "rds_port" {
  value = aws_db_instance.mysql.port
}

