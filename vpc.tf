resource "aws_vpc" "vpc" {
  cidr_block           = "10.204.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "msk"
  }
}

resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "msk-ig"
  }
}

resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ig.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_route.id
}

resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.ig]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = element(aws_subnet.public.*.id, 0)

  tags = {
    Name = "msk-nat"
  }
}

data "aws_availability_zones" "azs" {
  state = "available"
}

resource "aws_subnet" "public" {
  count                   = 3
  availability_zone       = data.aws_availability_zones.azs.names[(count.index)]
  cidr_block              = "10.204.${count.index + 1}.0/26"
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = true

  tags = {
    Name = "msk-${data.aws_availability_zones.azs.names[count.index]}-public-subnet"
  }
}

resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.vpc.id
  
  tags = {
    Name = "msk-sg"
    Application = "msk"
    ClusterName = var.cluster_name
  }
}

resource "aws_security_group_rule" "vpc_in" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.vpc.cidr_block]
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "vpc_out" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.vpc.cidr_block]
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "all_out" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}
