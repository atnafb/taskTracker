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
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Task Tracker</title>
    <style>
        body {
            margin: 0;
            font-family: Inter, system-ui, sans-serif;
            background: #f5f7fb;
            color: #1f2937;
        }
        .page {
            max-width: 960px;
            margin: 0 auto;
            padding: 32px 24px 40px;
        }
        header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 20px;
            margin-bottom: 24px;
        }
        h1 {
            margin: 0;
            font-size: 2.4rem;
        }
        .subtitle {
            color: #4b5563;
            max-width: 720px;
            line-height: 1.6;
        }
        .card {
            background: #ffffff;
            border-radius: 24px;
            box-shadow: 0 24px 80px rgba(15, 23, 42, 0.08);
            padding: 28px;
            margin-bottom: 24px;
        }
        .form-grid {
            display: grid;
            gap: 16px;
        }
        input,
        textarea {
            width: 100%;
            border-radius: 14px;
            border: 1px solid #d1d5db;
            padding: 14px 16px;
            font-size: 1rem;
            outline: none;
            transition: border-color 0.2s ease, box-shadow 0.2s ease;
        }
        input:focus,
        textarea:focus {
            border-color: #2563eb;
            box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
        }
        textarea {
            min-height: 96px;
            resize: vertical;
        }
        button {
            border: none;
            border-radius: 14px;
            padding: 14px 20px;
            background: #2563eb;
            color: white;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.2s ease;
        }
        button:hover {
            background: #1d4ed8;
        }
        .message {
            margin-top: 12px;
            min-height: 24px;
            color: #047857;
        }
        .message.error {
            color: #b91c1c;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.95rem;
        }
        th,
        td {
            padding: 14px 12px;
            text-align: left;
        }
        th {
            color: #6b7280;
            font-weight: 600;
            border-bottom: 1px solid #e5e7eb;
        }
        tr {
            background: #ffffff;
        }
        tr:not(:last-child) {
            border-bottom: 1px solid #e5e7eb;
        }
        td:last-child {
            width: 200px;
        }
        .actions button {
            margin-right: 8px;
            background: #f3f4f6;
            color: #111827;
        }
        .actions button:last-child {
            margin-right: 0;
        }
        .actions button:hover {
            background: #e5e7eb;
        }
        .description {
            color: #4b5563;
            margin-top: 8px;
            line-height: 1.6;
        }
        .section-title {
            margin-top: 0;
            margin-bottom: 16px;
            font-size: 1.15rem;
        }
        .table-wrapper {
            overflow-x: auto;
        }
    </style>
</head>
<body>
<div class="page">
    <header>
        <div>
            <h1>Task Tracker</h1>
            <p class="subtitle">Add tasks with descriptions, update them instantly, and remove completed work. Your task list is stored in DynamoDB and managed through a clean web UI.</p>
        </div>
    </header>

    <section class="card">
        <h2 class="section-title">Create or update a task</h2>
        <form id="task-form" class="form-grid">
            <input id="task-title" name="task" placeholder="Task title" required />
            <textarea id="task-description" name="description" placeholder="Task description"></textarea>
            <div style="display: flex; gap: 12px; flex-wrap: wrap; align-items: center;">
                <button id="submit-btn" type="submit">Add Task</button>
                <button id="cancel-btn" type="button" style="background: #9ca3af;">Cancel</button>
            </div>
            <div id="message" class="message"></div>
        </form>
    </section>

    <section class="card">
        <h2 class="section-title">Your tasks</h2>
        <div class="table-wrapper">
            <table>
                <thead>
                    <tr>
                        <th>Title</th>
                        <th>Description</th>
                        <th>Created</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody id="task-list"></tbody>
            </table>
        </div>
    </section>
</div>

<script>
let editingTaskId = null;
const form = document.getElementById('task-form');
const titleInput = document.getElementById('task-title');
const descriptionInput = document.getElementById('task-description');
const submitBtn = document.getElementById('submit-btn');
const cancelBtn = document.getElementById('cancel-btn');
const message = document.getElementById('message');
const taskList = document.getElementById('task-list');

const showMessage = (text, isError = false) => {
    message.textContent = text;
    message.className = isError ? 'message error' : 'message';
};

const formatDate = iso => {
    try {
        const date = new Date(iso);
        return date.toLocaleString();
    } catch (err) {
        return iso;
    }
};

const escapeHtml = str => {
    return String(str || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
};

const loadTasks = async () => {
    try {
        const response = await fetch('/api/tasks');
        if (!response.ok) throw new Error('Unable to fetch tasks');
        const tasks = await response.json();
        taskList.innerHTML = tasks.map(task => `
            <tr>
                <td>${escapeHtml(task.task)}</td>
                <td>${escapeHtml(task.description)}</td>
                <td>${escapeHtml(task.created_at ? formatDate(task.created_at) : '')}</td>
                <td class="actions">
                    <button type="button" onclick="editTask('${task.task_id}', '${encodeURIComponent(task.task || '')}', '${encodeURIComponent(task.description || '')}')">Edit</button>
                    <button type="button" onclick="deleteTask('${task.task_id}')">Delete</button>
                </td>
            </tr>
        `).join('');
        if (tasks.length === 0) {
            taskList.innerHTML = '<tr><td colspan="4" style="color: #6b7280; padding: 20px 12px;">No tasks yet. Add one above.</td></tr>';
        }
    } catch (error) {
        showMessage('Unable to load tasks.', true);
    }
};

window.editTask = (taskId, title, description) => {
    editingTaskId = taskId;
    titleInput.value = decodeURIComponent(title);
    descriptionInput.value = decodeURIComponent(description);
    submitBtn.textContent = 'Update Task';
    showMessage('Editing task. Make your changes and save.');
};

cancelBtn.addEventListener('click', () => {
    editingTaskId = null;
    titleInput.value = '';
    descriptionInput.value = '';
    submitBtn.textContent = 'Add Task';
    showMessage('');
});

form.addEventListener('submit', async event => {
    event.preventDefault();
    const payload = {
        task: titleInput.value.trim(),
        description: descriptionInput.value.trim(),
    };
    if (!payload.task) {
        showMessage('Task title is required.', true);
        return;
    }

    try {
        const url = editingTaskId ? `/api/task/${editingTaskId}` : '/api/task';
        const method = editingTaskId ? 'PUT' : 'POST';
        const response = await fetch(url, {
            method,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.error || 'Unable to save task');
        }
        showMessage(editingTaskId ? 'Task updated.' : 'Task added.');
        editingTaskId = null;
        titleInput.value = '';
        descriptionInput.value = '';
        submitBtn.textContent = 'Add Task';
        loadTasks();
    } catch (error) {
        showMessage(error.message, true);
    }
});

window.deleteTask = async taskId => {
    if (!confirm('Delete this task permanently?')) return;
    try {
        const response = await fetch(`/api/task/${taskId}`, { method: 'DELETE' });
        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.error || 'Unable to delete task');
        }
        showMessage('Task deleted.');
        loadTasks();
    } catch (error) {
        showMessage(error.message, true);
    }
};

loadTasks();
</script>
</body>
</html>
"""


@app.route("/")
def home():
    return render_template_string(HOME_HTML)


@app.route("/api/task", methods=["POST"])
def add_task():
    data = request.get_json(silent=True) or request.form
    title = data.get("task") if isinstance(data, dict) else data.get("task")
    description = data.get("description") if isinstance(data, dict) else data.get("description")

    if not title or not str(title).strip():
        return jsonify({"error": "Task title is required"}), 400

    item = {
        "task_id": str(uuid.uuid4()),
        "task": str(title).strip(),
        "description": str(description or "").strip(),
        "created_at": datetime.utcnow().isoformat() + "Z",
    }

    try:
        table.put_item(Item=item)
    except (BotoCoreError, ClientError):
        app.logger.exception("Failed to write item to DynamoDB")
        return jsonify({"error": "Failed to save task"}), 500

    return jsonify({"message": "Task added", "item": item}), 201


@app.route("/api/task/<task_id>", methods=["PUT"])
def update_task(task_id):
    data = request.get_json(silent=True) or request.form
    title = data.get("task") if isinstance(data, dict) else data.get("task")
    description = data.get("description") if isinstance(data, dict) else data.get("description")

    if not title or not str(title).strip():
        return jsonify({"error": "Task title is required"}), 400

    try:
        response = table.update_item(
            Key={"task_id": task_id},
            UpdateExpression="SET #task = :task, description = :description",
            ExpressionAttributeNames={"#task": "task"},
            ExpressionAttributeValues={
                ":task": str(title).strip(),
                ":description": str(description or "").strip(),
            },
            ReturnValues="ALL_NEW",
        )
    except (BotoCoreError, ClientError):
        app.logger.exception("Failed to update DynamoDB item")
        return jsonify({"error": "Failed to update task"}), 500

    return jsonify({"message": "Task updated", "item": response.get("Attributes", {})}), 200


@app.route("/api/task/<task_id>", methods=["DELETE"])
def delete_task(task_id):
    try:
        table.delete_item(Key={"task_id": task_id})
    except (BotoCoreError, ClientError):
        app.logger.exception("Failed to delete DynamoDB item")
        return jsonify({"error": "Failed to delete task"}), 500

    return jsonify({"message": "Task deleted"}), 200


@app.route("/api/tasks")
def get_tasks():
    try:
        items = []
        response = table.scan()
        items.extend(response.get("Items", []))
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
