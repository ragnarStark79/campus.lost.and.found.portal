"""
Application entry point.
Run locally with:  flask --app run run --debug
Or directly:       python run.py

Default port is 5001 — macOS reserves port 5000 for the AirPlay Receiver.
Override with:     FLASK_PORT=8080 python run.py
"""

import os
from app import create_app
from app.config import config_map

env = os.environ.get("FLASK_ENV", "development")
config_class = config_map.get(env, config_map["development"])

app = create_app(config_class)

if __name__ == "__main__":
    app.run(
        host=os.environ.get("FLASK_HOST", "127.0.0.1"),  # localhost-only by default
        port=int(os.environ.get("FLASK_PORT", 5001)),     # 5001 avoids macOS AirPlay
        debug=config_class.DEBUG,
    )

