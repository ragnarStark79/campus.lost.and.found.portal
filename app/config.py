"""
Application configuration.
Reads values from environment variables — never hardcode secrets here.
"""

import os


class Config:
    """Base configuration shared across all environments."""

    # Flask internals
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-change-in-production")
    DEBUG = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
    TESTING = False

    # Database — SQLite file path (can be overridden per environment)
    BASE_DIR = os.path.abspath(os.path.dirname(__file__))
    DATABASE_PATH = os.environ.get(
        "DATABASE_PATH",
        os.path.join(BASE_DIR, "..", "data", "lostandfound.db"),
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # Application metadata
    APP_NAME = "Campus Lost and Found Portal"
    APP_VERSION = "0.1.0"


class DevelopmentConfig(Config):
    """Development-specific overrides."""

    DEBUG = True


class TestingConfig(Config):
    """Testing-specific overrides."""

    TESTING = True
    DATABASE_PATH = ":memory:"


class ProductionConfig(Config):
    """Production-specific overrides.
    All sensitive values MUST come from environment variables.
    """

    DEBUG = False


# Map string names to config classes — used by FLASK_ENV
config_map = {
    "development": DevelopmentConfig,
    "testing": TestingConfig,
    "production": ProductionConfig,
}
