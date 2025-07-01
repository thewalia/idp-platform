#!/usr/bin/env python3
import os
import json
import time
import platform
from datetime import datetime
from flask import Flask, jsonify, request

app = Flask(__name__)

SERVICE_NAME = os.getenv('SERVICE_NAME', 'unknown-api')
API_PORT = int(os.getenv('API_PORT', '8080'))
START_TIME = time.time()

MOCK_USERS = [
    {"id": 1, "name": "John Doe", "email": "john@example.com", "role": "admin"},
    {"id": 2, "name": "Jane Smith", "email": "jane@example.com", "role": "user"},
    {"id": 3, "name": "Bob Johnson", "email": "bob@example.com", "role": "user"},
]

@app.route('/health', methods=['GET'])
def health_check():
    uptime = time.time() - START_TIME
    return jsonify({
        "status": "healthy",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat(),
        "uptime_seconds": round(uptime, 2)
    })

@app.route('/ready', methods=['GET'])
def readiness_check():
    return jsonify({"status": "ready", "service": SERVICE_NAME})

@app.route('/metrics', methods=['GET'])
def metrics():
    uptime = time.time() - START_TIME
    return f"""# HELP api_uptime_seconds Total uptime in seconds
# TYPE api_uptime_seconds counter
api_uptime_seconds {uptime}
# HELP api_requests_total Total requests
# TYPE api_requests_total counter  
api_requests_total 1
""", 200, {'Content-Type': 'text/plain'}

@app.route('/api/users', methods=['GET'])
def get_users():
    return jsonify({
        "users": MOCK_USERS,
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/api/stats', methods=['GET'])
def get_stats():
    uptime = time.time() - START_TIME
    return jsonify({
        "service": SERVICE_NAME,
        "uptime_seconds": round(uptime, 2),
        "platform": platform.system(),
        "python_version": platform.python_version(),
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/', methods=['GET'])
def root():
    return jsonify({
        "message": f"Welcome to {SERVICE_NAME}",
        "endpoints": ["/health", "/ready", "/metrics", "/api/users", "/api/stats"],
        "timestamp": datetime.utcnow().isoformat()
    })

if __name__ == '__main__':
    print(f"Starting {SERVICE_NAME} on port {API_PORT}")
    app.run(host='0.0.0.0', port=API_PORT, debug=False)
