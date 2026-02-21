# -----------------------
# Security Group for Load Balancer
# -----------------------
resource "aws_security_group" "alb_sg" {
  name   = "${var.project}-${var.environment}-alb-sg"
  vpc_id = var.vpc_id

  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-alb-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------
# Security Group for EC2 instances
# -----------------------
resource "aws_security_group" "ec2_sg" {
  name   = "${var.project}-${var.environment}-ec2-sg"
  vpc_id = var.vpc_id

  # Allow traffic only from the ALB
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }


  # Python burner server port for testing
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }


  # Allow all outbound (needed to reach the internet via NAT for updates/packages)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-ec2-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------
# Application Load Balancer (must be in at least 2 subnets across 2 AZs)
# -----------------------
resource "aws_lb" "this" {
  name               = "${var.project}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name        = "${var.project}-${var.environment}-alb"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------
# Target Group
# -----------------------
resource "aws_lb_target_group" "this" {
  name     = "${var.project}-${var.environment}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name        = "${var.project}-${var.environment}-tg"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------
# Listener
# -----------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# -----------------------
# Launch Template
# -----------------------
resource "aws_launch_template" "this" {
  name_prefix   = "${var.project}-${var.environment}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  # Enable EC2 Detailed Monitoring (1-minute metrics)
  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  user_data = base64encode(var.user_data)

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "${var.project}-${var.environment}-ec2"
      Project     = var.project
      Environment = var.environment
    }
  }
}

# -----------------------
# Auto Scaling Group
# -----------------------
resource "aws_autoscaling_group" "this" {
  desired_capacity    = 1
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = var.private_subnet_ids

  target_group_arns = [aws_lb_target_group.this.arn]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # Enable ASG metrics collection (needed so GroupInServiceInstances is reliable in CloudWatch)
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupInServiceInstances",
    "GroupDesiredCapacity"
  ]

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# -----------------------
# Scale up policy
# -----------------------
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project}-${var.environment}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.this.name
}

# -----------------------
# Scale down policy
# -----------------------
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project}-${var.environment}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.this.name
}

# -----------------------
# CPU high alarm (triggers scale up)
# -----------------------
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 50

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}

# -----------------------
# CPU low alarm (triggers scale down)
# -----------------------
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project}-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 15

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}

# -----------------------
# CloudWatch Dashboard (CPU + InServiceInstances on right axis)
# -----------------------
resource "aws_cloudwatch_dashboard" "asg_dashboard" {
  dashboard_name = "${var.project}-${var.environment}-scaling-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 12

        properties = {
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          title   = "CPU (left) + InServiceInstances (right)"

          metrics = [
            [ "AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.this.name ],
            [ "AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.this.name, { "yAxis": "right" } ],
            [ "AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", aws_autoscaling_group.this.name, { "yAxis": "right" } ]
          ]

          yAxis = {
            left  = { min = 0, max = 100, label = "CPU %" }
            right = { min = 0, max = 5, label = "Instances" }
          }
        }
      }
    ]
  })
}
