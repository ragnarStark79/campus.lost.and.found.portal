"""
Form validation helpers — Phase 1.

Flask-WTF is intentionally not used to keep the dependency list minimal
and to demonstrate plain-Python validation, which is easier to explain.

All validation functions return a dict of {field_name: error_message}.
An empty dict means the form is valid.
"""

from datetime import date


# ── Constants ─────────────────────────────────────────────────────────────────

CATEGORIES = [
    "Electronics",
    "Books & Notes",
    "Keys",
    "ID Card / Documents",
    "Clothing",
    "Water Bottle",
    "Bag / Backpack",
    "Jewellery",
    "Sports Equipment",
    "Other",
]

LOCATIONS = [
    "Main Building",
    "Library",
    "Canteen / Cafeteria",
    "Laboratory",
    "Lecture Hall",
    "Sports Complex",
    "Hostel / Dormitory",
    "Parking Area",
    "Administrative Block",
    "Other / Not Sure",
]


# ── Validators ────────────────────────────────────────────────────────────────

def validate_item_form(data: dict) -> dict[str, str]:
    """
    Validate the shared report form (used for both lost and found items).

    Returns a dict mapping field names to error messages.
    An empty dict means validation passed.
    """
    errors: dict[str, str] = {}

    # Title — required, 3–120 characters
    title = data.get("title", "").strip()
    if not title:
        errors["title"] = "Item title is required."
    elif len(title) < 3:
        errors["title"] = "Title must be at least 3 characters."
    elif len(title) > 120:
        errors["title"] = "Title must be 120 characters or fewer."

    # Category — must be one of the known values
    if data.get("category", "") not in CATEGORIES:
        errors["category"] = "Please select a valid category."

    # Date occurred — required, must be a valid ISO date, not in the future
    date_occurred = data.get("date_occurred", "").strip()
    if not date_occurred:
        errors["date_occurred"] = "Date is required."
    else:
        try:
            parsed = date.fromisoformat(date_occurred)
            if parsed > date.today():
                errors["date_occurred"] = "Date cannot be in the future."
        except ValueError:
            errors["date_occurred"] = "Enter a valid date (YYYY-MM-DD)."

    # Location — required, max 200 characters
    location = data.get("location", "").strip()
    if not location:
        errors["location"] = "Location is required."
    elif len(location) > 200:
        errors["location"] = "Location must be 200 characters or fewer."

    # Description — optional, max 1000 characters
    description = data.get("description", "").strip()
    if len(description) > 1000:
        errors["description"] = "Description must be 1000 characters or fewer."

    # Reporter name — required, 2–100 characters
    reporter_name = data.get("reporter_name", "").strip()
    if not reporter_name:
        errors["reporter_name"] = "Your name is required."
    elif len(reporter_name) < 2:
        errors["reporter_name"] = "Name must be at least 2 characters."
    elif len(reporter_name) > 100:
        errors["reporter_name"] = "Name must be 100 characters or fewer."

    # Contact info — required, 5–150 characters
    contact_info = data.get("contact_info", "").strip()
    if not contact_info:
        errors["contact_info"] = "Contact information (email or phone) is required."
    elif len(contact_info) < 5:
        errors["contact_info"] = "Please enter a valid email address or phone number."
    elif len(contact_info) > 150:
        errors["contact_info"] = "Contact info must be 150 characters or fewer."

    return errors
