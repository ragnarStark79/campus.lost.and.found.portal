"""
Application entry point.
Run locally with:  flask --app run run --debug
Or directly:       python run.py
"""

import os
from app import create_app
from app.config import config_map

env = os.environ.get("FLASK_ENV", "development")
config_class = config_map.get(env, config_map["development"])

app = create_app(config_class)

if __name__ == "__main__":
    app.run(
        host=os.environ.get("FLASK_HOST", "0.0.0.0"),
        port=int(os.environ.get("FLASK_PORT", 5000)),
        debug=config_class.DEBUG,
    )
