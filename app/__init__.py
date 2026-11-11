"""
Campus Lost and Found Portal — Application Factory
Phase 1: database initialisation, blueprint registration, error handlers.
"""

from flask import Flask, render_template

from .config import Config
from .database import init_app as db_init_app, init_db


def create_app(config_class=Config):
    """Create and configure the Flask application instance."""
    app = Flask(__name__)
    app.config.from_object(config_class)

    # Register the per-request DB teardown hook
    db_init_app(app)

    # Register blueprints
    from .routes import main as main_blueprint
    app.register_blueprint(main_blueprint)

    # Initialise the database schema inside an app context.
    # This is safe to call on every startup — the schema uses CREATE TABLE IF
    # NOT EXISTS so existing data is never lost.
    with app.app_context():
        init_db()

    # ── Error handlers ────────────────────────────────────────────────────────

    @app.errorhandler(404)
    def not_found(e):
        return render_template("404.html"), 404

    @app.errorhandler(500)
    def internal_error(e):
        return render_template("500.html"), 500

    return app
