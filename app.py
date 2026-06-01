import os
import uuid
import logging
from datetime import datetime

from flask import Flask, request, jsonify, render_template_string
import boto3
from botocore.exceptions import BotoCoreError, ClientError
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

logging.basicConfig(level=logging.INFO)

# Configuration from environment
TABLE_NAME = os.getenv("DYNAMODB_TABLE", "TaskTrackerTable")
AWS_REGION = os.getenv("AWS_REGION", "us-west-2")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(TABLE_NAME)

HOME_HTML = """
<h1>Task Tracker App</h1>
<form action="/add" method="post">
	<input name="task" placeholder="Enter task">
	<button type="submit">Add Task</button>
</form>
<br>
<a href="/tasks">View Tasks</a>
"""


@app.route("/")
def home():
	return render_template_string(HOME_HTML)


@app.route("/add", methods=["POST"])
def add_task():
	# Accept JSON or form data
	data = request.get_json(silent=True) or request.form
	task = None
	if isinstance(data, dict):
		task = data.get("task")
	else:
		task = data.get("task") if data is not None else None

	if not task or not str(task).strip():
		return jsonify({"error": "Task is required"}), 400

	item = {
		"task_id": str(uuid.uuid4()),
		"task": str(task).strip(),
		"created_at": datetime.utcnow().isoformat() + "Z",
	}

	try:
		table.put_item(Item=item)
	except (BotoCoreError, ClientError):
		app.logger.exception("Failed to write item to DynamoDB")
		return jsonify({"error": "Failed to save task"}), 500

	return jsonify({"message": "Task added", "item": item}), 201


@app.route("/tasks")
def get_tasks():
	try:
		items = []
		response = table.scan()
		items.extend(response.get("Items", []))
		# handle pagination
		while response.get("LastEvaluatedKey"):
			response = table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
			items.extend(response.get("Items", []))
		return jsonify(items)
	except (BotoCoreError, ClientError):
		app.logger.exception("Failed to scan DynamoDB table")
		return jsonify({"error": "Failed to fetch tasks"}), 500


if __name__ == "__main__":
	host = os.getenv("FLASK_RUN_HOST", "0.0.0.0")
	port = int(os.getenv("FLASK_RUN_PORT", "5000"))
	debug = os.getenv("FLASK_DEBUG", "false").lower() in ("1", "true", "yes")
	app.run(host=host, port=port, debug=debug)