resource "aws_security_group" "alb_sg" {
  name        = "legacylens-alb-sg"
  description = "Inbound internet firewall for Webhook ingress"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description = "Allow HTTP inbound from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound to private application subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "legacylens-alb-sg" }
}

resource "aws_lb" "external_alb" {
  name               = "legacylens-webhook-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_az1.id, aws_subnet.public_az2.id]

  tags = { Name = "legacylens-webhook-alb" }
}

resource "aws_lb_target_group" "whatsapp_bot_tg" {
  name        = "legacylens-bot-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.legacylens.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http_ingress" {
  load_balancer_arn = aws_lb.external_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.whatsapp_bot_tg.arn
  }
}