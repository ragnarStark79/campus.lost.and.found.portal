"""
Route-level tests for the Campus Lost and Found Portal.

These tests use Flask's test client (no real HTTP connection).
Every test runs against an isolated in-memory database.
"""

import json


# ── Health check ──────────────────────────────────────────────────────────────

def test_health_returns_200(client):
    response = client.get("/health")
    assert response.status_code == 200


def test_health_response_body(client):
    response = client.get("/health")
    data = json.loads(response.data)
    assert data["status"] == "ok"
    assert data["service"] == "campus-lost-and-found"


# ── Homepage & static assets ──────────────────────────────────────────────────

def test_homepage_returns_200(client):
    response = client.get("/")
    assert response.status_code == 200


def test_homepage_contains_brand(client):
    response = client.get("/")
    assert b"Lost" in response.data
    assert b"Found" in response.data


def test_static_css_loads(client):
    response = client.get("/static/css/main.css")
    assert response.status_code == 200


def test_static_js_loads(client):
    response = client.get("/static/js/main.js")
    assert response.status_code == 200


# ── Browse ────────────────────────────────────────────────────────────────────

def test_browse_returns_200(client):
    assert client.get("/items").status_code == 200


def test_browse_lost_filter(client):
    assert client.get("/items?type=lost").status_code == 200


def test_browse_found_filter(client):
    assert client.get("/items?type=found").status_code == 200


def test_browse_search(client):
    assert client.get("/items?q=wallet").status_code == 200


def test_browse_location_filter(client):
    client.post("/report/lost", data={
        "title": "Laptop Charger",
        "category": "Electronics",
        "location": "Laboratory",
        "date_occurred": "2026-11-01",
        "reporter_name": "Student X",
        "contact_info": "studentx@example.com",
    })
    res = client.get("/items?location=Laboratory")
    assert res.status_code == 200
    assert b"Laptop Charger" in res.data


# ── Report lost form ──────────────────────────────────────────────────────────

def test_report_lost_get(client):
    assert client.get("/report/lost").status_code == 200


def test_report_lost_post_valid(client):
    """Submitting a complete valid form should redirect (302) to the detail page."""
    response = client.post("/report/lost", data={
        "title":         "Blue Water Bottle",
        "category":      "Water Bottle",
        "location":      "Library",
        "date_occurred": "2026-11-01",
        "description":   "1-litre blue Nalgene bottle",
        "reporter_name": "Test Student",
        "contact_info":  "test@example.com",
    })
    assert response.status_code == 302
    assert "/items/" in response.headers["Location"]


def test_report_lost_post_missing_title(client):
    """Missing required field should return 200 with error, not redirect."""
    response = client.post("/report/lost", data={
        "title":         "",
        "category":      "Keys",
        "location":      "Canteen",
        "date_occurred": "2026-11-01",
        "reporter_name": "Test Student",
        "contact_info":  "test@example.com",
    })
    assert response.status_code == 200
    assert b"required" in response.data.lower()


def test_report_lost_post_future_date(client):
    """A date in the future should fail validation."""
    response = client.post("/report/lost", data={
        "title":         "Keys",
        "category":      "Keys",
        "location":      "Library",
        "date_occurred": "2099-01-01",
        "reporter_name": "Test Student",
        "contact_info":  "test@example.com",
    })
    assert response.status_code == 200
    assert b"future" in response.data.lower()


def test_report_lost_post_short_contact_rejected(client):
    """Too-short contact string should fail validation."""
    response = client.post("/report/lost", data={
        "title":         "Keys",
        "category":      "Keys",
        "location":      "Library",
        "date_occurred": "2026-11-01",
        "reporter_name": "Test Student",
        "contact_info":  "abc",
    })
    assert response.status_code == 200
    assert b"valid email address or phone number" in response.data.lower()


def test_report_lost_post_long_description_rejected(client):
    """Description over 1000 chars should fail validation."""
    response = client.post("/report/lost", data={
        "title":         "Keys",
        "category":      "Keys",
        "location":      "Library",
        "date_occurred": "2026-11-01",
        "description":   "x" * 1001,
        "reporter_name": "Test Student",
        "contact_info":  "test@example.com",
    })
    assert response.status_code == 200
    assert b"1000 characters" in response.data.lower()


# ── Report found form ─────────────────────────────────────────────────────────

def test_report_found_get(client):
    assert client.get("/report/found").status_code == 200


def test_report_found_post_valid(client):
    response = client.post("/report/found", data={
        "title":         "Student ID Card",
        "category":      "ID Card / Documents",
        "location":      "Library",
        "date_occurred": "2026-11-01",
        "description":   "LPU student card",
        "reporter_name": "Honest Finder",
        "contact_info":  "finder@example.com",
    })
    assert response.status_code == 302
    assert "/items/" in response.headers["Location"]


def test_report_found_post_invalid_category(client):
    response = client.post("/report/found", data={
        "title":         "Student ID Card",
        "category":      "InvalidCategory",
        "location":      "Library",
        "date_occurred": "2026-11-01",
        "reporter_name": "Honest Finder",
        "contact_info":  "finder@example.com",
    })
    assert response.status_code == 200
    assert b"valid category" in response.data.lower()


# ── Item detail ───────────────────────────────────────────────────────────────

def test_item_detail_not_found(client):
    assert client.get("/items/99999").status_code == 404


def test_item_detail_after_submission(client):
    """Create an item, then verify its detail page loads."""
    r = client.post("/report/lost", data={
        "title":         "Black Backpack",
        "category":      "Bag / Backpack",
        "location":      "Main Building",
        "date_occurred": "2026-11-01",
        "reporter_name": "Student A",
        "contact_info":  "a@example.com",
    })
    detail_url = r.headers["Location"]
    detail = client.get(detail_url)
    assert detail.status_code == 200
    assert b"Black Backpack" in detail.data


# ── Claim workflow ────────────────────────────────────────────────────────────

def test_claim_found_item(client):
    """A found item with status 'open' should be claimable."""
    r = client.post("/report/found", data={
        "title":         "Silver Keys",
        "category":      "Keys",
        "location":      "Canteen",
        "date_occurred": "2026-11-01",
        "reporter_name": "Finder",
        "contact_info":  "finder@example.com",
    })
    detail_url = r.headers["Location"]
    item_id = detail_url.rstrip("/").split("/")[-1]

    claim_r = client.post(f"/items/{item_id}/claim", follow_redirects=True)
    assert claim_r.status_code == 200
    assert b"claimed" in claim_r.data.lower()


def test_claim_already_claimed_item_rejected(client):
    """Claiming an already-claimed item should warn and not re-claim."""
    r = client.post("/report/found", data={
        "title":         "Earbuds Case",
        "category":      "Electronics",
        "location":      "Library",
        "date_occurred": "2026-11-01",
        "reporter_name": "Finder",
        "contact_info":  "finder@example.com",
    })
    item_id = r.headers["Location"].rstrip("/").split("/")[-1]
    client.post(f"/items/{item_id}/claim")

    second = client.post(f"/items/{item_id}/claim", follow_redirects=True)
    assert second.status_code == 200
    assert b"already claimed" in second.data.lower()


def test_claim_lost_item_rejected(client):
    """Trying to claim a *lost* item should be rejected."""
    r = client.post("/report/lost", data={
        "title":         "Red Umbrella",
        "category":      "Other",
        "location":      "Library",
        "date_occurred": "2026-11-01",
        "reporter_name": "Owner",
        "contact_info":  "owner@example.com",
    })
    detail_url = r.headers["Location"]
    item_id = detail_url.rstrip("/").split("/")[-1]

    claim_r = client.post(f"/items/{item_id}/claim", follow_redirects=True)
    assert claim_r.status_code == 200
    assert b"only found items can be claimed" in claim_r.data.lower()


# ── 404 handler ───────────────────────────────────────────────────────────────

def test_unknown_route_returns_404(client):
    assert client.get("/this/does/not/exist").status_code == 404
