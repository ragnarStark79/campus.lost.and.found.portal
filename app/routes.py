"""
Application routes — Phase 1 implementation.

All URL endpoints for the Campus Lost and Found Portal are defined here
as a single Blueprint called 'main'.

Route overview:
    GET  /                      – Homepage with dashboard stats and recent items
    GET  /items                 – Browse all items with search/filter
    GET  /items/<id>            – Item detail page
    GET  /report/lost           – Show "report lost item" form
    POST /report/lost           – Submit a lost-item report
    GET  /report/found          – Show "report found item" form
    POST /report/found          – Submit a found-item report
    POST /items/<id>/claim      – Mark a found item as claimed
    GET  /health                – Health-check endpoint (unchanged from Phase 0)
"""

from datetime import date

from flask import (
    Blueprint,
    abort,
    flash,
    jsonify,
    redirect,
    render_template,
    request,
    url_for,
)

from .forms import CATEGORIES, LOCATIONS, validate_item_form
from .models import (
    create_item,
    get_all_items,
    get_item_by_id,
    get_stats,
    update_item_status,
)

main = Blueprint("main", __name__)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _handle_report(item_type: str, template: str, success_message: str):
    """Shared GET/POST handler for lost and found item submission forms."""
    errors: dict[str, str] = {}
    form_data: dict[str, str] = {}

    if request.method == "POST":
        form_data = request.form.to_dict()
        errors = validate_item_form(form_data)

        if not errors:
            item_id = create_item({**form_data, "type": item_type})
            flash(success_message, "success")
            return redirect(url_for("main.item_detail", item_id=item_id))

    return render_template(
        template,
        errors=errors,
        form_data=form_data,
        categories=CATEGORIES,
        locations=LOCATIONS,
        today=date.today().isoformat(),
    )


# ── Homepage ──────────────────────────────────────────────────────────────────

@main.route("/")
def index():
    """Render the homepage with live stats and the six most recent reports."""
    stats = get_stats()
    recent = get_all_items()[:6]
    return render_template("index.html", stats=stats, recent_items=recent)


# ── Browse / search ───────────────────────────────────────────────────────────

@main.route("/items")
def browse():
    """
    List all items with optional filtering.

    Query parameters:
        q        – keyword search (title, description, location)
        type     – 'lost' | 'found'
        category – exact category name
        status   – 'open' | 'claimed' | 'closed'
        location – substring match on campus location
        date_from / date_to – ISO date bounds
    """
    q = request.args.get("q", "").strip()
    item_type = request.args.get("type", "").strip()
    category = request.args.get("category", "").strip()
    status = request.args.get("status", "").strip()
    location = request.args.get("location", "").strip()
    date_from = request.args.get("date_from", "").strip()
    date_to = request.args.get("date_to", "").strip()

    items = get_all_items(
        item_type=item_type or None,
        category=category or None,
        status=status or None,
        search=q or None,
        location=location or None,
        date_from=date_from or None,
        date_to=date_to or None,
    )

    return render_template(
        "items.html",
        items=items,
        categories=CATEGORIES,
        # Pass current filter values back so form fields stay populated
        filters={
            "q": q,
            "type": item_type,
            "category": category,
            "status": status,
            "location": location,
            "date_from": date_from,
            "date_to": date_to,
        },
    )


# ── Item detail ───────────────────────────────────────────────────────────────

@main.route("/items/<int:item_id>")
def item_detail(item_id: int):
    """Show full details for a single report."""
    item = get_item_by_id(item_id)
    if item is None:
        abort(404)
    return render_template("item_detail.html", item=item)


# ── Report lost / found ───────────────────────────────────────────────────────

@main.route("/report/lost", methods=["GET", "POST"])
def report_lost():
    """Display and process the 'report a lost item' form."""
    return _handle_report(
        item_type="lost",
        template="report_lost.html",
        success_message="Your lost-item report has been submitted. We hope it is found soon!",
    )


@main.route("/report/found", methods=["GET", "POST"])
def report_found():
    """Display and process the 'report a found item' form."""
    return _handle_report(
        item_type="found",
        template="report_found.html",
        success_message="Found-item report submitted. Thank you for being honest!",
    )


# ── Claim ─────────────────────────────────────────────────────────────────────

@main.route("/items/<int:item_id>/claim", methods=["POST"])
def claim_item(item_id: int):
    """
    Mark a found item as 'claimed'.

    Only found items with status 'open' can be claimed. The claim is a
    lightweight workflow — the person viewing contacts the reporter using the
    contact_info displayed on the detail page. Full claim management (with
    authentication) is listed as future scope in the synopsis.
    """
    item = get_item_by_id(item_id)
    if item is None:
        abort(404)

    if item.type != "found":
        flash("Only found items can be claimed.", "warning")
        return redirect(url_for("main.item_detail", item_id=item_id))

    if item.status != "open":
        flash(
            f"This item is already {item.status_label.lower()} and cannot be claimed again.",
            "warning",
        )
        return redirect(url_for("main.item_detail", item_id=item_id))

    update_item_status(item_id, "claimed")
    flash(
        "Item marked as claimed. Please use the contact information above to arrange collection.",
        "success",
    )
    return redirect(url_for("main.item_detail", item_id=item_id))


# ── Health check ──────────────────────────────────────────────────────────────

@main.route("/health")
def health():
    """Health-check endpoint used by Docker, monitoring tools and load balancers."""
    return jsonify(
        {
            "status": "ok",
            "service": "campus-lost-and-found",
            "version": "0.1.0",
        }
    ), 200
