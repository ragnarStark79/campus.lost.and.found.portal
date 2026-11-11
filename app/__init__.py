"""
Campus Lost and Found Portal — Application Factory
Phase 0: Foundation skeleton only.
"""

from flask import Flask
from .config import Config


def create_app(config_class=Config):
    """Create and configure the Flask application instance."""
    app = Flask(__name__)
    app.config.from_object(config_class)

    # Register blueprints
    from .routes import main as main_blueprint
    app.register_blueprint(main_blueprint)

    return app
