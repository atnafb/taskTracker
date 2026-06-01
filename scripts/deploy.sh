#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-app-tracker}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
TABLE_NAME="${TABLE_NAME:-AppTrackerTasks}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
GIT_BRANCH="${GIT_BRANCH:-main}"
SSH_CIDR="${SSH_CIDR:-$(curl -fsS https://checkip.amazonaws.com)/32}"
HTTP_CIDR="${HTTP_CIDR:-0.0.0.0/0}"
KEY_NAME="${KEY_NAME:-}"
GIT_REPO_URL="${GIT_REPO_URL:-}"

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required. Install and configure it first: aws configure"
  exit 1
fi

if [[ -z "$GIT_REPO_URL" ]]; then
  echo "Set GIT_REPO_URL to your GitHub repo URL before deploying."
  echo "Example: GIT_REPO_URL=https://github.com/YOUR_USER/app-tracker.git ./scripts/deploy.sh"
  exit 1
fi

if [[ -z "$KEY_NAME" ]]; then
  echo "Set KEY_NAME to an existing EC2 key pair name so you can SSH if needed."
  echo "Example: KEY_NAME=my-key GIT_REPO_URL=https://github.com/YOUR_USER/app-tracker.git ./scripts/deploy.sh"
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
VPC_ID="$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)"

if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  echo "No default VPC found in $AWS_REGION."
  exit 1
fi

SUBNET_ID="$(aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query 'Subnets[0].SubnetId' \
  --output text)"

echo "Using account $ACCOUNT_ID in $AWS_REGION"
echo "Using default VPC $VPC_ID and subnet $SUBNET_ID"

if aws dynamodb describe-table --region "$AWS_REGION" --table-name "$TABLE_NAME" >/dev/null 2>&1; then
  echo "DynamoDB table $TABLE_NAME already exists"
else
  echo "Creating DynamoDB table $TABLE_NAME"
  aws dynamodb create-table \
    --region "$AWS_REGION" \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=task_id,AttributeType=S \
    --key-schema AttributeName=task_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
  aws dynamodb wait table-exists --region "$AWS_REGION" --table-name "$TABLE_NAME"
fi

ROLE_NAME="${APP_NAME}-ec2-role"
PROFILE_NAME="${APP_NAME}-instance-profile"
POLICY_NAME="${APP_NAME}-dynamodb-policy"

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "IAM role $ROLE_NAME already exists"
else
  echo "Creating IAM role $ROLE_NAME"
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "ec2.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' >/dev/null
fi

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [
        \"dynamodb:DeleteItem\",
        \"dynamodb:DescribeTable\",
        \"dynamodb:GetItem\",
        \"dynamodb:PutItem\",
        \"dynamodb:Scan\",
        \"dynamodb:UpdateItem\"
      ],
      \"Resource\": \"arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/${TABLE_NAME}\"
    }]
  }"

if aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1; then
  echo "Instance profile $PROFILE_NAME already exists"
else
  echo "Creating instance profile $PROFILE_NAME"
  aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null
fi

if aws iam get-instance-profile \
  --instance-profile-name "$PROFILE_NAME" \
  --query "InstanceProfile.Roles[?RoleName=='$ROLE_NAME'].RoleName" \
  --output text | grep -q "$ROLE_NAME"; then
  echo "Role already attached to instance profile"
else
  aws iam add-role-to-instance-profile \
    --instance-profile-name "$PROFILE_NAME" \
    --role-name "$ROLE_NAME"
  echo "Waiting for IAM instance profile propagation"
  sleep 12
fi

SG_NAME="${APP_NAME}-sg"
SG_ID="$(aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)"

if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
  SG_ID="$(aws ec2 create-security-group \
    --region "$AWS_REGION" \
    --group-name "$SG_NAME" \
    --description "Security group for $APP_NAME" \
    --vpc-id "$VPC_ID" \
    --query GroupId \
    --output text)"
  echo "Created security group $SG_ID"
fi

aws ec2 authorize-security-group-ingress \
  --region "$AWS_REGION" \
  --group-id "$SG_ID" \
  --ip-permissions "[
    {\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"IpRanges\":[{\"CidrIp\":\"${HTTP_CIDR}\",\"Description\":\"HTTP\"}]},
    {\"IpProtocol\":\"tcp\",\"FromPort\":22,\"ToPort\":22,\"IpRanges\":[{\"CidrIp\":\"${SSH_CIDR}\",\"Description\":\"SSH\"}]}
  ]" >/dev/null 2>&1 || true

AMI_ID="$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' \
  --output text)"

USER_DATA_FILE="$(mktemp)"
cat > "$USER_DATA_FILE" <<USERDATA
#!/bin/bash
set -euxo pipefail

dnf update -y
dnf install -y git python3 python3-pip nginx

mkdir -p /opt/${APP_NAME}
git clone --branch ${GIT_BRANCH} ${GIT_REPO_URL} /opt/${APP_NAME}
cd /opt/${APP_NAME}

python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

cat >/etc/systemd/system/${APP_NAME}.service <<SERVICE
[Unit]
Description=${APP_NAME} Flask app
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/${APP_NAME}
Environment=AWS_REGION=${AWS_REGION}
Environment=TASKS_TABLE=${TABLE_NAME}
ExecStart=/opt/${APP_NAME}/.venv/bin/gunicorn --workers 3 --bind 127.0.0.1:8000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

cat >/etc/nginx/conf.d/${APP_NAME}.conf <<NGINX
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX

rm -f /etc/nginx/conf.d/default.conf
chown -R ec2-user:ec2-user /opt/${APP_NAME}
systemctl daemon-reload
systemctl enable --now ${APP_NAME}
systemctl enable --now nginx
USERDATA

INSTANCE_ID="$(aws ec2 run-instances \
  --region "$AWS_REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name="$PROFILE_NAME" \
  --user-data "file://${USER_DATA_FILE}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${APP_NAME}}]" \
  --query 'Instances[0].InstanceId' \
  --output text)"

rm -f "$USER_DATA_FILE"

echo "Launched instance $INSTANCE_ID"
aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"

PUBLIC_DNS="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicDnsName' \
  --output text)"

echo
echo "Deployment started."
echo "App URL: http://${PUBLIC_DNS}"
echo "SSH: ssh -i /path/to/key.pem ec2-user@${PUBLIC_DNS}"
echo "User-data may need 2-5 minutes to finish installing dependencies."
