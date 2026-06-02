variable "aws_region" {
  description = "AWS region for the app infrastructure."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name used for EC2, security group, IAM, and tags."
  type        = string
  default     = "app-tracker"
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "portfolio"
}

variable "table_name" {
  description = "DynamoDB table name for tasks."
  type        = string
  default     = "AppTrackerTasks"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Existing EC2 key pair name."
  type        = string
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH to EC2. Use your public IP with /32."
  type        = string
}

variable "http_cidr" {
  description = "CIDR allowed to access HTTP."
  type        = string
  default     = "0.0.0.0/0"
}

variable "git_repo_url" {
  description = "GitHub repository URL for the app code."
  type        = string
  default     = "https://github.com/atnafb/taskTracker.git"
}

variable "git_branch" {
  description = "Git branch to deploy."
  type        = string
  default     = "main"
}

variable "create_instance_profile" {
  description = "Create an EC2 IAM role/profile with DynamoDB permissions. Set false in restricted labs."
  type        = bool
  default     = true
}

variable "existing_instance_profile_name" {
  description = "Existing instance profile to attach when create_instance_profile is false."
  type        = string
  default     = ""
}
