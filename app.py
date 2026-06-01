import os
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Attr
from flask import Flask, redirect, render_template, request, url_for


APP_REGION = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "us-east-1"
TABLE_NAME = os.getenv("TASKS_TABLE", "AppTrackerTasks")

app = Flask(__name__)
dynamodb = boto3.resource("dynamodb", region_name=APP_REGION)
table = dynamodb.Table(TABLE_NAME)


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def get_tasks():
    response = table.scan()
    items = response.get("Items", [])

    while "LastEvaluatedKey" in response:
        response = table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
        items.extend(response.get("Items", []))

    return sorted(items, key=lambda task: task.get("created_at", ""), reverse=True)


@app.get("/")
def index():
    status_filter = request.args.get("status", "all")
    tasks = get_tasks()

    if status_filter == "open":
        tasks = [task for task in tasks if not task.get("completed")]
    elif status_filter == "done":
        tasks = [task for task in tasks if task.get("completed")]

    return render_template("index.html", tasks=tasks, status_filter=status_filter)


@app.post("/tasks")
def add_task():
    title = request.form.get("title", "").strip()
    description = request.form.get("description", "").strip()
    priority = request.form.get("priority", "Normal")

    if title:
        table.put_item(
            Item={
                "task_id": str(uuid.uuid4()),
                "title": title,
                "description": description,
                "priority": priority,
                "completed": False,
                "created_at": now_iso(),
                "updated_at": now_iso(),
            }
        )

    return redirect(url_for("index"))


@app.post("/tasks/<task_id>/edit")
def edit_task(task_id):
    title = request.form.get("title", "").strip()
    description = request.form.get("description", "").strip()
    priority = request.form.get("priority", "Normal")

    if title:
        table.update_item(
            Key={"task_id": task_id},
            UpdateExpression="SET title = :title, description = :description, priority = :priority, updated_at = :updated_at",
            ConditionExpression=Attr("task_id").exists(),
            ExpressionAttributeValues={
                ":title": title,
                ":description": description,
                ":priority": priority,
                ":updated_at": now_iso(),
            },
        )

    return redirect(url_for("index"))


@app.post("/tasks/<task_id>/toggle")
def toggle_task(task_id):
    completed = request.form.get("completed") == "true"
    table.update_item(
        Key={"task_id": task_id},
        UpdateExpression="SET completed = :completed, updated_at = :updated_at",
        ConditionExpression=Attr("task_id").exists(),
        ExpressionAttributeValues={":completed": completed, ":updated_at": now_iso()},
    )

    return redirect(url_for("index"))


@app.post("/tasks/<task_id>/delete")
def delete_task(task_id):
    table.delete_item(Key={"task_id": task_id})
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
