"""
Pytest fixtures shared across the test suite.

SQLite :memory: limitation: each new connection to ":memory:" is a separate
empty database. To share schema across requests inside the Flask test client
we use a URI in-memory database with shared cache:
  "file::memory:?cache=shared"

A module-level shared connection is held open for the lifetime of the test
so its schema and data are visible to every request the test client makes.
The connection is reset between tests via the `app` fixture's teardown.
"""

import pytest

from app import create_app
from app.config import TestingConfig
import app.database as _db_module


@pytest.fixture(autouse=True)
def reset_memory_db():
    """
    Reset the shared in-memory connection before every test.
    This ensures each test starts with an empty, freshly-initialised schema.
    """
    _db_module._memory_conn = None
    yield
    if _db_module._memory_conn is not None:
        _db_module._memory_conn.close()
    _db_module._memory_conn = None


@pytest.fixture
def app(reset_memory_db):
    """Create a testing application instance backed by an in-memory database."""
    application = create_app(TestingConfig)
    yield application


@pytest.fixture
def client(app):
    """Return a Flask test client."""
    return app.test_client()


@pytest.fixture
def db_ctx(app):
    """
    Push an application context and yield the get_db() function.
    Useful for testing the database layer directly without HTTP.
    """
    from app.database import get_db
    with app.app_context():
        yield get_db
