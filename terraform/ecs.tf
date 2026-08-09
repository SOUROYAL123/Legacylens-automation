# ====================================================================
# SERVERLESS CONTAINER ORCHESTRATION (ecs.tf)
# ====================================================================

# 1. IAM Execution Role & Secrets Policy
resource "aws_iam_role" "ecs_execution_role" {
  name = "legacylens-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Explicitly grant permission to create CloudWatch Logs and read Secrets Manager
resource "aws_iam_role_policy" "ecs_execution_secrets_and_logs" {
  name = "legacylens-ecs-execution-secrets-logs"
  role = aws_iam_role.ecs_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        # Requires the aws_secretsmanager_secret.db_credentials resource in main.tf
        Resource = [aws_secretsmanager_secret.db_credentials.arn]
      }
    ]
  })
}

# 2. ECS Cluster
resource "aws_ecs_cluster" "legacylens_cluster" {
  name = "legacylens-production-cluster"
}

# 3. Task Definition
resource "aws_ecs_task_definition" "whatsapp_bot" {
  family                   = "legacylens-whatsapp-bot"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "legacylens-bot-container"
    image     = "${aws_ecr_repository.legacylens_repo.repository_url}:latest"
    essential = true
    
    portMappings = [{
      containerPort = 3000
      hostPort      = 3000
      protocol      = "tcp"
    }]

    # Securely map credentials from AWS Secrets Manager instead of plaintext environment variables
    secrets = [
      {
        name      = "DB_HOST"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:host::"
      },
      {
        name      = "DB_PORT"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:port::"
      },
      {
        name      = "DB_NAME"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:dbname::"
      },
      {
        name      = "DB_USER"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"
      },
      {
        name      = "DB_PASSWORD"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
      }
    ]

    environment = [
      { name = "NODE_ENV", value = "production" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/legacylens-task"
        "awslogs-region"        = "ap-south-1"
        "awslogs-stream-prefix" = "whatsapp-bot"
        "awslogs-create-group"  = "true"
      }
    }
  }])
}

# 4. The ECS Service
resource "aws_ecs_service" "whatsapp_bot_service" {
  name            = "legacylens-bot-service"
  cluster         = aws_ecs_cluster.legacylens_cluster.id
  task_definition = aws_ecs_task_definition.whatsapp_bot.arn
  launch_type     = "FARGATE"
  desired_count   = 1 # Reduced to 1 for faster testing

  network_configuration {
    subnets = [
      aws_subnet.private_app_az1.id,
      aws_subnet.private_app_az2.id
    ]
    security_groups = [aws_security_group.private_app_sg.id]

    # Outbound traffic now securely routes through your NAT Gateways
    assign_public_ip = false
  }

  # Connects the ALB to the Fargate containers
  load_balancer {
    target_group_arn = aws_lb_target_group.whatsapp_bot_tg.arn
    container_name   = "legacylens-bot-container"
    container_port   = 3000
  }

  # Ensure the ALB listener exists before the service tries to register targets
  depends_on = [aws_lb_listener.http_ingress]
}