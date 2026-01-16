import os
import sys
import time
import signal
import socket
import requests
from flask import Flask, jsonify
from datetime import datetime

app = Flask(__name__)

# --- Настройки ---
SERVICE_NAME = os.getenv('SERVICE_NAME', 'api')
PORT = int(os.getenv('PORT', 8000))
CONSUL_URL = 'http://consul:8500'
SERVICE_ID = f"{SERVICE_NAME}-instance"
CHECK_ID = f"service:{SERVICE_ID}"

# Глобальная переменная для управления статусом здоровья
is_healthy = True

# --- Маршруты Flask ---

@app.route('/')
@app.route('/api')
@app.route('/api/')
def index():
    return jsonify({
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat(),
        "message": "Service is running!"
    }), 200

@app.route('/health')
def health():
    if is_healthy:
        return jsonify({"status": "healthy"}), 200
    else:
        return jsonify({"status": "unhealthy"}), 500

@app.route('/fail')
def fail():
    global is_healthy
    is_healthy = False
    print("⚠️  Health check status changed to UNHEALTHY", flush=True)
    return "Service is now UNHEALTHY", 200

# --- Регистрация в Consul ---

def get_ip():
    try:
        return socket.gethostbyname(socket.gethostname())
    except:
        return "127.0.0.1"

def register_service():
    ip = get_ip()

    # Регистрация самого сервиса
    service_payload = {
        "ID": SERVICE_ID,
        "Name": SERVICE_NAME,
        "Address": ip,
        "Port": PORT,
        "Tags": [
            "traefik.enable=true",
            f"traefik.http.routers.{SERVICE_NAME}.rule=PathPrefix(`/{SERVICE_NAME}`)",
            f"traefik.http.services.{SERVICE_NAME}.loadbalancer.server.port={PORT}",
            f"traefik.http.middlewares.{SERVICE_NAME}-strip.stripprefix.prefixes=/{SERVICE_NAME}",
            f"traefik.http.routers.{SERVICE_NAME}.middlewares={SERVICE_NAME}-strip",
            # Отключаем внутренние проверки Traefik
            f"traefik.http.services.{SERVICE_NAME}.loadbalancer.healthcheck.interval=0s"
        ]
    }

    try:
        # 1. Регистрируем сервис
        requests.put(f"{CONSUL_URL}/v1/agent/service/register", json=service_payload).raise_for_status()

        # 2. Регистрируем отдельный Health Check в Consul
        check_payload = {
            "ID": CHECK_ID,
            "Name": f"{SERVICE_NAME} health",
            "ServiceID": SERVICE_ID,
            "HTTP": f"http://{ip}:{PORT}/health",
            "Method": "GET",
            "Interval": "12s", # Наш большой интервал для теста
            "Timeout": "2s",
            "DeregisterCriticalServiceAfter": "30s"
        }
        requests.put(f"{CONSUL_URL}/v1/agent/check/register", json=check_payload).raise_for_status()

        print(f"✅ Service '{SERVICE_NAME}' registered at {ip}:{PORT}", flush=True)
    except Exception as e:
        print(f"❌ Registration failed: {e}", flush=True)
        sys.exit(1)

def signal_handler(sig, frame):
    print(f"Stopping service...", flush=True)
    try:
        requests.put(f"{CONSUL_URL}/v1/agent/service/deregister/{SERVICE_ID}", timeout=2)
    except:
        pass
    sys.exit(0)

if __name__ == '__main__':
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Даем Consul время проснуться
    time.sleep(5)
    register_service()

    app.run(host='0.0.0.0', port=PORT)
