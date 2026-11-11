"""
Database-layer tests for the Campus Lost and Found Portal.

These tests call model functions directly (no HTTP) inside an in-memory
app context, verifying the SQL layer independently of the routes.
"""

import pytest

from app import create_app
from app.config import Config, TestingConfig
from app.models import (
    create_item,
    get_all_items,
    get_item_by_id,
    get_stats,
    update_item_status,
)


SAMPLE_LOST = {
    "type":          "lost",
    "title":         "Blue Notebook",
    "description":   "A5 blue spiral notebook",
    "category":      "Books & Notes",
    "location":      "Library",
    "date_occurred": "2026-11-01",
    "reporter_name": "Alice",
    "contact_info":  "alice@example.com",
}

SAMPLE_FOUND = {
    "type":          "found",
    "title":         "Silver Keys",
    "description":   "Three keys on a blue keyring",
    "category":      "Keys",
    "location":      "Canteen",
    "date_occurred": "2026-11-02",
    "reporter_name": "Bob",
    "contact_info":  "bob@example.com",
}


@pytest.fixture
def ctx():
    """Push an app context with an empty in-memory database."""
    app = create_app(TestingConfig)
    with app.app_context():
        yield


# ── create_item ───────────────────────────────────────────────────────────────

def test_create_item_returns_int_id(ctx):
    item_id = create_item(SAMPLE_LOST)
    assert isinstance(item_id, int)
    assert item_id > 0


def test_create_item_stores_correct_type(ctx):
    item_id = create_item(SAMPLE_FOUND)
    item = get_item_by_id(item_id)
    assert item is not None
    assert item.type == "found"


def test_create_item_default_status_is_open(ctx):
    item_id = create_item(SAMPLE_LOST)
    item = get_item_by_id(item_id)
    assert item is not None
    assert item.status == "open"


def test_create_item_stores_title(ctx):
    item_id = create_item(SAMPLE_LOST)
    item = get_item_by_id(item_id)
    assert item is not None
    assert item.title == "Blue Notebook"


# ── get_item_by_id ────────────────────────────────────────────────────────────

def test_get_item_by_id_returns_none_for_missing(ctx):
    assert get_item_by_id(99999) is None


def test_get_item_by_id_returns_item(ctx):
    item_id = create_item(SAMPLE_LOST)
    item = get_item_by_id(item_id)
    assert item is not None
    assert item.id == item_id


# ── get_all_items ─────────────────────────────────────────────────────────────

def test_get_all_items_empty_at_start(ctx):
    assert get_all_items() == []


def test_get_all_items_returns_created_items(ctx):
    create_item(SAMPLE_LOST)
    create_item(SAMPLE_FOUND)
    items = get_all_items()
    assert len(items) == 2


def test_get_all_items_filter_by_type_lost(ctx):
    create_item(SAMPLE_LOST)
    create_item(SAMPLE_FOUND)
    lost = get_all_items(item_type="lost")
    assert all(i.type == "lost" for i in lost)
    assert len(lost) == 1


def test_get_all_items_filter_by_type_found(ctx):
    create_item(SAMPLE_LOST)
    create_item(SAMPLE_FOUND)
    found = get_all_items(item_type="found")
    assert all(i.type == "found" for i in found)


def test_get_all_items_search_by_keyword(ctx):
    create_item(SAMPLE_LOST)
    create_item(SAMPLE_FOUND)
    results = get_all_items(search="Notebook")
    assert len(results) == 1
    assert results[0].title == "Blue Notebook"


def test_get_all_items_search_no_match(ctx):
    create_item(SAMPLE_LOST)
    results = get_all_items(search="xyzzy_no_match")
    assert results == []


def test_get_all_items_filter_by_category(ctx):
    create_item(SAMPLE_LOST)
    create_item(SAMPLE_FOUND)
    results = get_all_items(category="Keys")
    assert len(results) == 1
    assert results[0].category == "Keys"


def test_get_all_items_filter_by_location(ctx):
    create_item(SAMPLE_LOST)
    create_item(SAMPLE_FOUND)
    results = get_all_items(location="Library")
    assert len(results) == 1
    assert results[0].title == "Blue Notebook"


def test_get_all_items_filter_by_date_range(ctx):
    create_item(SAMPLE_LOST)   # 2026-11-01
    create_item(SAMPLE_FOUND)  # 2026-11-02
    results = get_all_items(date_from="2026-11-02")
    assert len(results) == 1
    assert results[0].title == "Silver Keys"


def test_get_all_items_ordered_newest_first(ctx):
    create_item(SAMPLE_LOST)
    create_item(SAMPLE_FOUND)
    items = get_all_items()
    # Ordered by created_at DESC, id DESC so second item always comes first
    assert items[0].title == "Silver Keys"
    assert items[1].title == "Blue Notebook"


# ── update_item_status ────────────────────────────────────────────────────────

def test_update_status_to_claimed(ctx):
    item_id = create_item(SAMPLE_FOUND)
    result = update_item_status(item_id, "claimed")
    assert result is True
    item = get_item_by_id(item_id)
    assert item is not None
    assert item.status == "claimed"


def test_update_status_returns_false_for_missing_id(ctx):
    result = update_item_status(99999, "claimed")
    assert result is False


# ── get_stats ─────────────────────────────────────────────────────────────────

def test_get_stats_all_zeros_initially(ctx):
    s = get_stats()
    assert s == {"total": 0, "lost": 0, "found": 0, "claimed": 0}


def test_get_stats_counts_correctly(ctx):
    create_item(SAMPLE_LOST)
    fid = create_item(SAMPLE_FOUND)
    update_item_status(fid, "claimed")

    s = get_stats()
    assert s["total"] == 2
    assert s["lost"] == 1
    assert s["found"] == 1
    assert s["claimed"] == 1


# ── Item dataclass properties ─────────────────────────────────────────────────

def test_item_type_label_lost(ctx):
    item_id = create_item(SAMPLE_LOST)
    item = get_item_by_id(item_id)
    assert item is not None
    assert item.type_label == "Lost"


def test_item_type_label_found(ctx):
    item_id = create_item(SAMPLE_FOUND)
    item = get_item_by_id(item_id)
    assert item is not None
    assert item.type_label == "Found"


def test_item_status_label_open(ctx):
    item_id = create_item(SAMPLE_LOST)
    item = get_item_by_id(item_id)
    assert item is not None
    assert item.status_label == "Open"


def test_item_status_label_claimed(ctx):
    item_id = create_item(SAMPLE_FOUND)
    update_item_status(item_id, "claimed")
    item = get_item_by_id(item_id)
    assert item is not None
    assert item.status_label == "Claimed"


# ── Persistence across restart ────────────────────────────────────────────────

def test_file_database_persists_across_app_restart(tmp_path):
    """Data written in one app instance must remain readable in a new instance."""
    db_file = str(tmp_path / "persist_test.db")

    class FileConfig(Config):
        TESTING = True
        DATABASE_PATH = db_file

    app1 = create_app(FileConfig)
    with app1.app_context():
        item_id = create_item(SAMPLE_FOUND)

    app2 = create_app(FileConfig)
    with app2.app_context():
        loaded = get_item_by_id(item_id)
        assert loaded is not None
        assert loaded.title == "Silver Keys"
        assert loaded.location == "Canteen"
