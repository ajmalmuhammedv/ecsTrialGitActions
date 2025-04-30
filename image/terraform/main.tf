provider "aws" {
  region = "us-east-1"
  shared_credentials_files = ["C:/Users/ajmal/.aws/credentials"]# Set the desired region
}
# Get default VPC
data "aws_vpc" "default" {
  default = true
}
# Generate a random suffix to avoid IAM role name collision
resource "random_id" "suffix" {
  byte_length = 4
}

# Get default subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


# Create a security group
resource "aws_security_group" "ecs_sg" {
  name        = "ecs_fargate_sg-${random_id.suffix.hex}"
  description = "Allow all outbound traffic"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS cluster
resource "aws_ecs_cluster" "fargate_cluster" {
  name = "my-fargate-cluster-${random_id.suffix.hex}"
}

# Task execution IAM role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach required policies to the IAM role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS task definition
resource "aws_ecs_task_definition" "fargate_task" {
  family                   = "my-fargate-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "my-app"
      image     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest" # Replace with your ECR URI
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS service to run the task
resource "aws_ecs_service" "fargate_service" {
  name            = "my-fargate-service${random_id.suffix.hex}"
  cluster         = aws_ecs_cluster.fargate_cluster.id
  task_definition = aws_ecs_task_definition.fargate_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_policy]
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.fargate_cluster.name
}

output "ecs_service_name" {
  value = aws_ecs_service.fargate_service.name
}