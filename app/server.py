import os
from flask import Flask, jsonify
from datetime import datetime

app = Flask(__name__)

SERVICE_NAME = os.getenv('SERVICE_NAME', 'api')
PORT = int(os.getenv('PORT', 8000))

@app.route('/health')
def health():
    return jsonify({"status": "healthy"}), 200

@app.route('/')
@app.route('/api')
@app.route('/api/')
def index():
    return jsonify({
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat(),
        "message": "Service is running!"
    }), 200

if __name__ == '__main__':
    print(f"Starting Flask on port {PORT}", flush=True)
    app.run(host='0.0.0.0', port=PORT)
