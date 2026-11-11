"""
Application routes — Phase 0 skeleton.
Only the homepage and health-check endpoints are defined here.
Full lost-and-found routes will be added in Phase 1.
"""

from flask import Blueprint, jsonify, render_template

main = Blueprint("main", __name__)


@main.route("/")
def index():
    """Render the homepage."""
    return render_template("index.html")


@main.route("/health")
def health():
    """Health-check endpoint used by monitoring tools and load balancers."""
    return jsonify(
        {
            "status": "ok",
            "service": "campus-lost-and-found",
            "version": "0.1.0",
        }
    ), 200
