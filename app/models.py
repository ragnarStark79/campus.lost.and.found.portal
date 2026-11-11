"""
Data models — Phase 1 implementation.

This module defines the Item dataclass and all database query functions
(the "repository" layer). Views import these functions; they never call
sqlite3 directly.

Design decisions:
- Raw sqlite3 is used instead of an ORM to keep dependencies minimal and
  to demonstrate direct SQL, which is easier to explain in a viva.
- sqlite3.Row objects are converted to Item dataclasses at the boundary so
  the rest of the application never imports sqlite3.
- All query functions accept and return plain Python types.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from .database import get_db


# ── Item dataclass ────────────────────────────────────────────────────────────

@dataclass
class Item:
    id: int
    type: str           # 'lost' | 'found'
    title: str
    description: str
    category: str
    location: str
    date_occurred: str  # ISO date string YYYY-MM-DD
    reporter_name: str
    contact_info: str
    status: str         # 'open' | 'claimed' | 'closed'
    created_at: str     # ISO datetime string

    @property
    def status_label(self) -> str:
        """Human-readable status badge text."""
        return {"open": "Open", "claimed": "Claimed", "closed": "Closed"}.get(
            self.status, self.status.title()
        )

    @property
    def type_label(self) -> str:
        """Human-readable report type text."""
        return "Lost" if self.type == "lost" else "Found"


def _row_to_item(row) -> Item:
    """Convert a sqlite3.Row to an Item dataclass."""
    return Item(**{k: row[k] for k in row.keys()})


# ── Query helpers ─────────────────────────────────────────────────────────────

def get_all_items(
    *,
    item_type: Optional[str] = None,
    category: Optional[str] = None,
    status: Optional[str] = None,
    search: Optional[str] = None,
    location: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> list[Item]:
    """
    Return all items, newest first, with optional filters.

    Parameters
    ----------
    item_type : 'lost' | 'found' | None
    category  : exact category string | None
    status    : 'open' | 'claimed' | 'closed' | None
    search    : substring matched against title, description, location | None
    location  : substring matched against location | None
    date_from : ISO date string lower bound on date_occurred | None
    date_to   : ISO date string upper bound on date_occurred | None
    """
    query = "SELECT * FROM items WHERE 1=1"
    params: list[str] = []

    if item_type in ("lost", "found"):
        query += " AND type = ?"
        params.append(item_type)

    if category:
        query += " AND category = ?"
        params.append(category)

    if status:
        query += " AND status = ?"
        params.append(status)

    if search:
        query += " AND (title LIKE ? OR description LIKE ? OR location LIKE ?)"
        like = f"%{search}%"
        params.extend([like, like, like])

    if location:
        query += " AND location LIKE ?"
        params.append(f"%{location}%")

    if date_from:
        query += " AND date_occurred >= ?"
        params.append(date_from)

    if date_to:
        query += " AND date_occurred <= ?"
        params.append(date_to)

    # Order by created_at and id descending so items inserted within the
    # same second still keep deterministic newest-first ordering.
    query += " ORDER BY created_at DESC, id DESC"

    rows = get_db().execute(query, params).fetchall()
    return [_row_to_item(r) for r in rows]


def get_item_by_id(item_id: int) -> Optional[Item]:
    """Return a single item by primary key, or None if not found."""
    row = get_db().execute(
        "SELECT * FROM items WHERE id = ?", (item_id,)
    ).fetchone()
    return _row_to_item(row) if row else None


def create_item(data: dict) -> int:
    """
    Insert a new item record and return its new primary key.

    Expected keys in `data`:
        type, title, description, category, location,
        date_occurred, reporter_name, contact_info
    Status defaults to 'open'; created_at is set to now (UTC).
    """
    db = get_db()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    cursor = db.execute(
        """
        INSERT INTO items
            (type, title, description, category, location,
             date_occurred, reporter_name, contact_info, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'open', ?)
        """,
        (
            data["type"],
            data["title"].strip(),
            data.get("description", "").strip(),
            data.get("category", "Other"),
            data.get("location", "").strip(),
            data["date_occurred"],
            data["reporter_name"].strip(),
            data["contact_info"].strip(),
            now,
        ),
    )
    db.commit()
    assert cursor.lastrowid is not None
    return cursor.lastrowid


def update_item_status(item_id: int, new_status: str) -> bool:
    """
    Change the status of an item. Returns True if a row was updated.
    new_status must be one of: 'open', 'claimed', 'closed'.
    """
    db = get_db()
    cursor = db.execute(
        "UPDATE items SET status = ? WHERE id = ?", (new_status, item_id)
    )
    db.commit()
    return cursor.rowcount > 0


def get_stats() -> dict[str, int]:
    """Return aggregate counts used on the homepage dashboard."""
    db = get_db()
    row = db.execute(
        """
        SELECT
            COUNT(*)                                          AS total,
            SUM(CASE WHEN type = 'lost' THEN 1 ELSE 0 END)    AS lost,
            SUM(CASE WHEN type = 'found' THEN 1 ELSE 0 END)   AS found,
            SUM(CASE WHEN status = 'claimed' THEN 1 ELSE 0 END) AS claimed
        FROM items
        """
    ).fetchone()
    return {
        "total": row["total"] or 0,
        "lost": row["lost"] or 0,
        "found": row["found"] or 0,
        "claimed": row["claimed"] or 0,
    }
