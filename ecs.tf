module "ecs" {
  source       = "terraform-aws-modules/ecs/aws"
  cluster_name = "${var.project}-${var.environment}"
}

resource "aws_ecs_task_definition" "task" {
  family = "${var.project}-${var.environment}"
  requires_compatibilities = [
    "FARGATE",
  ]
  execution_role_arn = aws_iam_role.pinnacle_role.arn
  network_mode       = local.ecs_network_mode
  cpu                = local.ecs_task_cpu
  memory             = local.ecs_task_memory
  container_definitions = jsonencode([
    {
      name      = local.ecs_task_container_name
      image     = local.ecs_task_image
      cpu       = local.ecs_task_cpu
      memory    = local.ecs_task_memory
      essential = true
      secrets   = [for key in keys(local.ssm) : { "name" : key, "valueFrom" : aws_ssm_parameter.ssm[key].arn }]
      portMappings = [
        {
          containerPort = local.application_port
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.log.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "service" {
  name            = "${var.project}-${var.environment}"
  cluster         = module.ecs.cluster_id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 3

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.private.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_alb_tg.arn
    container_name   = local.ecs_task_container_name
    container_port   = local.application_port
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

}
