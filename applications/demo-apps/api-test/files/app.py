#!/usr/bin/env python3
"""
Simple API Service for IDP Demo
Provides health checks, metrics, and demo endpoints
"""

import os
import json
import time
import psutil
from datetime import datetime
from flask import Flask, jsonify, request
from werkzeug.middleware.dispatcher import DispatcherMiddleware
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

# Initialize Flask app
app = Flask(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration')
ACTIVE_CONNECTIONS = Gauge('active_connections', 'Active connections')

# Application startup time
START_TIME = time.time()

# Service configuration
SERVICE_NAME = os.getenv('SERVICE_NAME', 'unknown-api')
API_PORT = int(os.getenv('API_PORT', '8080'))
LOG_LEVEL = os.getenv('LOG_LEVEL', 'info')
ENVIRONMENT = os.getenv('ENVIRONMENT', 'development')

# Mock database for demo
MOCK_USERS = [
    {"id": 1, "name": "John Doe", "email": "john@example.com", "role": "admin"},
    {"id": 2, "name": "Jane Smith", "email": "jane@example.com", "role": "user"},
    {"id": 3, "name": "Bob Johnson", "email": "bob@example.com", "role": "user"},
    {"id": 4, "name": "Alice Brown", "email": "alice@example.com", "role": "moderator"}
]

def get_system_stats():
    """Get current system statistics"""
    return {
        "cpu_percent": psutil.cpu_percent(interval=1),
        "memory_percent": psutil.virtual_memory().percent,
        "disk_usage": psutil.disk_usage('/').percent,
        "load_average": os.getloadavg()[0] if hasattr(os, 'getloadavg') else 0.0
    }

@app.before_request
def before_request():
    """Track request metrics"""
    request.start_time = time.time()
    ACTIVE_CONNECTIONS.inc()

@app.after_request
def after_request(response):
    """Record request metrics"""
    request_duration = time.time() - getattr(request, 'start_time', time.time())
    REQUEST_DURATION.observe(request_duration)
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.endpoint or 'unknown',
        status=response.status_code
    ).inc()
    ACTIVE_CONNECTIONS.dec()
    return response

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    uptime = time.time() - START_TIME
    return jsonify({
        "status": "healthy",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat(),
        "uptime_seconds": round(uptime, 2),
        "environment": ENVIRONMENT,
        "version": "1.0.0"
    })

@app.route('/ready', methods=['GET'])
def readiness_check():
    """Readiness check for Kubernetes"""
    return jsonify({
        "status": "ready",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/api/users', methods=['GET'])
def get_users():
    """Get all users"""
    page = request.args.get('page', 1, type=int)
    limit = request.args.get('limit', 10, type=int)
    
    start = (page - 1) * limit
    end = start + limit
    
    paginated_users = MOCK_USERS[start:end]
    
    return jsonify({
        "users": paginated_users,
        "pagination": {
            "page": page,
            "limit": limit,
            "total": len(MOCK_USERS),
            "pages": (len(MOCK_USERS) + limit - 1) // limit
        },
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/api/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    """Get specific user by ID"""
    user = next((u for u in MOCK_USERS if u["id"] == user_id), None)
    if not user:
        return jsonify({"error": "User not found", "user_id": user_id}), 404
    
    return jsonify({
        "user": user,
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get system and service statistics"""
    uptime = time.time() - START_TIME
    system_stats = get_system_stats()
    
    return jsonify({
        "service": {
            "name": SERVICE_NAME,
            "uptime_seconds": round(uptime, 2),
            "uptime_human": f"{int(uptime // 3600)}h {int((uptime % 3600) // 60)}m {int(uptime % 60)}s",
            "environment": ENVIRONMENT,
            "port": API_PORT
        },
        "system": system_stats,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/api/info', methods=['GET'])
def get_info():
    """Get service information"""
    return jsonify({
        "service": SERVICE_NAME,
        "version": "1.0.0",
        "environment": ENVIRONMENT,
        "features": [
            "rest-api",
            "health-checks", 
            "metrics",
            "user-management",
            "system-monitoring"
        ],
        "endpoints": {
            "health": "/health",
            "ready": "/ready", 
            "metrics": "/metrics",
            "users": "/api/users",
            "user_detail": "/api/users/{id}",
            "stats": "/api/stats",
            "info": "/api/info"
        },
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/', methods=['GET'])
def root():
    """Root endpoint"""
    return jsonify({
        "message": f"Welcome to {SERVICE_NAME}",
        "status": "running",
        "documentation": "/api/info",
        "health": "/health",
        "timestamp": datetime.utcnow().isoformat()
    })

@app.errorhandler(404)
def not_found(error):
    """404 error handler"""
    return jsonify({
        "error": "Not Found",
        "message": "The requested resource was not found",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    }), 404

@app.errorhandler(500)
def internal_error(error):
    """500 error handler"""
    return jsonify({
        "error": "Internal Server Error",
        "message": "An internal error occurred",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    }), 500

if __name__ == '__main__':
    print(f"Starting {SERVICE_NAME} on port {API_PORT}")
    print(f"Environment: {ENVIRONMENT}")
    print(f"Log Level: {LOG_LEVEL}")
    
    app.run(
        host='0.0.0.0',
        port=API_PORT,
        debug=(ENVIRONMENT == 'development')
    )
