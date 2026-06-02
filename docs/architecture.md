# App Tracker Architecture

```mermaid
flowchart TB
    User["User Browser"] -->|HTTP :80| Internet["Internet"]
    Internet --> SG["Security Group: app-tracker-sg"]
    SG --> EC2["EC2 Instance: app-tracker"]

    subgraph Server["Inside EC2"]
        Nginx["Nginx :80"]
        Gunicorn["Gunicorn 127.0.0.1:8000"]
        Flask["Flask App"]
        Files["/opt/app-tracker"]
    end

    EC2 --> Nginx
    Nginx -->|Reverse proxy| Gunicorn
    Gunicorn --> Flask
    Flask --> Files
    Flask -->|boto3 API calls| DynamoDB["DynamoDB: AppTrackerTasks"]

    GitHub["GitHub: atnafb/taskTracker"] -->|git clone / git pull| Files
    Mac["Developer Mac"] -->|SSH :22| EC2
    Mac -->|git push| GitHub
```

## Request Flow

1. The user opens the EC2 public IP in a browser.
2. The security group allows HTTP traffic on port `80`.
3. Nginx receives the request and proxies it to Gunicorn.
4. Gunicorn runs the Flask app.
5. Flask reads and writes task data in DynamoDB using `boto3`.
6. DynamoDB returns task records, and Flask renders the HTML page.

## AWS Resources

| Resource | Name |
| --- | --- |
| EC2 instance | `app-tracker` |
| Security group | `app-tracker-sg` |
| DynamoDB table | `AppTrackerTasks` |
| DynamoDB partition key | `task_id` |
| App directory | `/opt/app-tracker` |
| Public app port | `80` |
| Internal app port | `127.0.0.1:8000` |
