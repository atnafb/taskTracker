output "app_url" {
  description = "Public HTTP URL for the App Tracker web app."
  value       = "http://${aws_instance.app.public_ip}"
}

output "public_ip" {
  description = "EC2 public IPv4 address."
  value       = aws_instance.app.public_ip
}

output "ssh_command" {
  description = "SSH command template."
  value       = "ssh -i /path/to/${var.key_name}.pem ec2-user@${aws_instance.app.public_ip}"
}

output "dynamodb_table_name" {
  description = "DynamoDB table used by the app."
  value       = aws_dynamodb_table.tasks.name
}

output "security_group_id" {
  description = "Security group attached to EC2."
  value       = aws_security_group.app.id
}
