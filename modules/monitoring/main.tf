############################################
# modules/monitoring/main.tf
# - Logs Auto Scaling scale events into DynamoDB
# - Sends email alerts via SNS
# - EventBridge rule triggers a Lambda on ASG launch/terminate events
############################################

# -----------------------
# DynamoDB table to store scaling events
# -----------------------
resource "aws_dynamodb_table" "scale_logs" {
  name         = "${var.project}-${var.environment}-scale-logs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------
# SNS Topic for alerts
# -----------------------
resource "aws_sns_topic" "scale_alerts" {
  name = "${var.project}-${var.environment}-scale-alerts"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# Email subscription (you must confirm the subscription email)
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.scale_alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# -----------------------
# IAM role for Lambda
# -----------------------
resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-${var.environment}-scale-lambda-role"

  # Lambda trust policy: allows AWS Lambda service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# Inline policy for Lambda:
# - PutItem to DynamoDB
# - Publish to SNS
# - Write logs to CloudWatch Logs
# - DescribeAutoScalingGroups to fetch current running instance count
resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.scale_logs.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.scale_alerts.arn
      },
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
        Effect   = "Allow"
        Action   = ["autoscaling:DescribeAutoScalingGroups"]
        Resource = "*"
      }
    ]
  })
}

# -----------------------
# Lambda function (packaged as ZIP)
# -----------------------
resource "aws_lambda_function" "scale_logger" {
  function_name = "${var.project}-${var.environment}-scale-logger"
  runtime       = "python3.12"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_role.arn

  # Path to your zipped lambda package (created by deploy.bat)
  filename = "./lambda/scale_logger.zip"

  # Optional but recommended: force update when ZIP changes
  # (prevents "no change" when file updated)
  source_code_hash = filebase64sha256("./lambda/scale_logger.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.scale_logs.name
      SNS_TOPIC  = aws_sns_topic.scale_alerts.arn
      ASG_NAME   = var.asg_name
    }
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------
# EventBridge rule for Auto Scaling events
# -----------------------
resource "aws_cloudwatch_event_rule" "asg_events" {
  name = "${var.project}-${var.environment}-asg-scale"

  # Trigger on successful instance launch/terminate events for this ASG
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    "detail-type" = [
      "EC2 Instance Launch Successful",
      "EC2 Instance Terminate Successful"
    ]
    detail = {
      AutoScalingGroupName = [var.asg_name]
    }
  })

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# Connect EventBridge rule to Lambda target
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.asg_events.name
  arn  = aws_lambda_function.scale_logger.arn
}

# Allow EventBridge to invoke the Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scale_logger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.asg_events.arn
}
