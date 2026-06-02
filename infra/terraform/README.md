# Terraform Infrastructure

This folder contains portfolio-ready Infrastructure as Code for App Tracker.

It creates:

- Default VPC lookup
- EC2 security group
- DynamoDB table named `AppTrackerTasks`
- Optional EC2 IAM role and instance profile for DynamoDB access
- Amazon Linux 2023 EC2 instance
- Nginx reverse proxy
- Gunicorn + Flask app service

## Usage

Copy the example variables file:

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit:

```bash
nano terraform.tfvars
```

Set:

```hcl
key_name = "your-existing-key-pair-name"
ssh_cidr = "YOUR_PUBLIC_IP/32"
```

Deploy:

```bash
terraform init
terraform plan
terraform apply
```

Show the app URL:

```bash
terraform output app_url
```

Destroy:

```bash
terraform destroy
```

## Lab Note

The Vocareum/AWS lab account used for this project blocked `iam:CreateRole`.
In that restricted environment, use the Bash deployment scripts or set:

```hcl
create_instance_profile = false
```

For a real AWS account, keep `create_instance_profile = true` so EC2 uses an IAM role instead of stored access keys.

## Security

Do not commit:

- `terraform.tfvars`
- `.terraform/`
- `*.tfstate`
- AWS access keys
- AWS session tokens
- EC2 `.pem` private keys
