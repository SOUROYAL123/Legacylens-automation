# 1. IAM Role for ECS Task Execution
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

# FIX #1: Explicitly grant permission to create the CloudWatch Log Group
resource "aws_iam_role_policy" "ecs_execution_logs_policy" {
  name = "legacylens-ecs-logs-policy"
  role = aws_iam_role.ecs_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
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
    name = "legacylens-bot-container"
    # UPDATED: Now dynamically references your actual ECR repository URL
    image     = "${aws_ecr_repository.legacylens_repo.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 3000
      hostPort      = 3000
    }]
    environment = [
      { name = "DB_HOST", value = aws_db_instance.postgres_db.address },
      { name = "DB_PORT", value = tostring(aws_db_instance.postgres_db.port) },
      { name = "DB_NAME", value = "legacylens_prod" },
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
    # NOTE: If you don't have a NAT Gateway, these MUST be changed to your public subnets
    # e.g., aws_subnet.public_app_az1.id
    subnets = [
      aws_subnet.private_app_az1.id,
      aws_subnet.private_app_az2.id
    ]
    security_groups = [aws_security_group.private_app_sg.id]

    # FIX #2: Fargate needs a public IP to reach the ECR registry over the internet
    assign_public_ip = true
  }
}