# ------------------------------------------------------------
# modules/network/main.tf
# Creates a 2-AZ VPC with:
# - 2 public subnets (for ALB + NAT)
# - 2 private subnets (for EC2/ASG)
# - 1 Internet Gateway
# - 1 NAT Gateway (in the first public subnet)
# - Public route table -> IGW
# - Private route table -> NAT
# ------------------------------------------------------------

# -----------------------
# Fetch available AZs in the current region
# -----------------------
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------
# VPC
# -----------------------
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project}-${var.environment}-vpc"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------
# Internet Gateway (public internet access)
# -----------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.project}-${var.environment}-igw"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------
# Public Subnets (2 AZs)
# - map_public_ip_on_launch = true so instances (if any) can get public IPs
# - ALB will live in public subnets
# -----------------------
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project}-${var.environment}-public-${count.index}"
    Project     = var.project
    Environment = var.environment
    Tier        = "public"
  }
}

# -----------------------
# Private Subnets (2 AZs)
# - no public IPs
# - ASG instances will live in private subnets
# -----------------------
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project}-${var.environment}-private-${count.index}"
    Project     = var.project
    Environment = var.environment
    Tier        = "private"
  }
}

# -----------------------
# Elastic IP for NAT Gateway
# - NAT Gateway needs a stable public IP (EIP)
# -----------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.project}-${var.environment}-nat-eip"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------
# NAT Gateway (in public subnet 0)
# - allows private subnets to access the internet for updates (yum, etc.)
# - cost-effective: single NAT GW for dev
# -----------------------
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name        = "${var.project}-${var.environment}-nat"
    Project     = var.project
    Environment = var.environment
  }

  # IGW must exist first, otherwise NAT creation can fail
  depends_on = [aws_internet_gateway.this]
}

# -----------------------
# Public Route Table
# - route 0.0.0.0/0 to the Internet Gateway
# -----------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${var.project}-${var.environment}-public-rt"
    Project     = var.project
    Environment = var.environment
  }
}

# Associate public route table with BOTH public subnets
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------
# Private Route Table
# - route 0.0.0.0/0 to the NAT Gateway
# -----------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name        = "${var.project}-${var.environment}-private-rt"
    Project     = var.project
    Environment = var.environment
  }
}

# Associate private route table with BOTH private subnets
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
