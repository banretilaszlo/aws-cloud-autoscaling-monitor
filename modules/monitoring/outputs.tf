output "dynamodb_table" {
  value = aws_dynamodb_table.scale_logs.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.scale_alerts.arn
}
