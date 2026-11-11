"""
Database helpers — Phase 1 implementation.

Pattern: one SQLite connection per Flask request, stored on Flask's `g` object.
The connection is opened lazily on first access and closed when the app context
tears down (registered via init_app).

Usage inside a view or model function:
    from .database import get_db
    db = get_db()
    rows = db.execute("SELECT * FROM items").fetchall()
"""

import os
import sqlite3

from flask import current_app, g


# ── Schema ────────────────────────────────────────────────────────────────────

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    type          TEXT    NOT NULL CHECK(type IN ('lost', 'found')),
    title         TEXT    NOT NULL,
    description   TEXT    NOT NULL DEFAULT '',
    category      TEXT    NOT NULL DEFAULT 'Other',
    location      TEXT    NOT NULL DEFAULT '',
    date_occurred TEXT    NOT NULL,
    reporter_name TEXT    NOT NULL,
    contact_info  TEXT    NOT NULL,
    status        TEXT    NOT NULL DEFAULT 'open'
                          CHECK(status IN ('open', 'claimed', 'closed')),
    created_at    TEXT    NOT NULL
);
"""


# ── Connection helpers ────────────────────────────────────────────────────────

# Module-level cache for the shared in-memory connection (testing only).
# File-backed databases use the per-request g pattern instead.
_memory_conn: sqlite3.Connection | None = None


def _get_memory_conn() -> sqlite3.Connection:
    """Return (or create) the single shared in-memory connection."""
    global _memory_conn
    if _memory_conn is None:
        _memory_conn = sqlite3.connect(
            "file::memory:?cache=shared",
            uri=True,
            detect_types=sqlite3.PARSE_DECLTYPES,
        )
        _memory_conn.row_factory = sqlite3.Row
        _memory_conn.execute("PRAGMA foreign_keys=ON")
    return _memory_conn


def get_db() -> sqlite3.Connection:
    """Return the per-request SQLite connection, opening it if necessary.

    For file-backed databases, one connection is opened per Flask request
    and stored on Flask's g object. For in-memory databases (testing), a
    single shared connection is reused across all requests so the schema
    created by init_db() remains visible.
    """
    if "db" not in g:
        db_path = current_app.config["DATABASE_PATH"]

        if db_path == ":memory:":
            g.db = _get_memory_conn()
        else:
            os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
            g.db = sqlite3.connect(db_path, detect_types=sqlite3.PARSE_DECLTYPES)
            g.db.row_factory = sqlite3.Row
            g.db.execute("PRAGMA journal_mode=WAL")
            g.db.execute("PRAGMA foreign_keys=ON")

    return g.db


def close_db(exception=None) -> None:
    """Close the per-request connection (called automatically by Flask).

    For the shared in-memory connection used in testing, closing must be
    skipped — the connection is managed by the test fixture instead.
    """
    db = g.pop("db", None)
    if db is not None and db is not _memory_conn:
        db.close()


def init_db() -> None:
    """Create all tables if they do not already exist."""
    db = get_db()
    db.executescript(SCHEMA)
    db.commit()


def init_app(app) -> None:
    """Register teardown hook so close_db is called after every request."""
    app.teardown_appcontext(close_db)
