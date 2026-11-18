"""
Unit and integration tests for deployment metadata loading,
timezone conversion to Asia/Kolkata (IST), and UI card rendering.
"""

import base64
import binascii
import json
import os
import re
import subprocess
import pytest
from app.deployment import (
    load_deployment_metadata,
    parse_timestamp_to_ist,
    DEFAULT_MESSAGE,
    DEFAULT_PATH,
    DEFAULT_PIPELINE,
)


def test_default_metadata_when_file_missing(monkeypatch, tmp_path):
    """When deployment.json does not exist, return sensible defaults."""
    non_existent = str(tmp_path / "missing_deployment.json")
    monkeypatch.setenv("DEPLOYMENT_METADATA_FILE", non_existent)

    meta = load_deployment_metadata()
    assert meta["status"] == "Successful"
    assert meta["is_confirmed"] is True
    assert meta["message"] == DEFAULT_MESSAGE
    assert meta["pipeline"] == DEFAULT_PIPELINE
    assert meta["deployment_path"] == DEFAULT_PATH
    assert "IST" in meta["timestamp_ist"]
    assert meta["commit"] == "0bf459f"


def test_custom_metadata_file_loading(monkeypatch, tmp_path):
    """Test loading dynamic deployment metadata from a verified JSON file."""
    meta_file = tmp_path / "deployment.json"
    data = {
        "deployment_status": "Successful",
        "deployment_message": "Production deployment verified on EC2.",
        "deployment_timestamp_utc": "2026-11-18T14:30:00Z",
        "deployment_commit": "1a2b3c4d5e6f",
        "deployment_commit_message": "fix(auth): secure session token handling",
        "deployment_image_tag": "sha-1a2b3c4",
        "deployment_workflow_run": "98765432",
    }
    meta_file.write_text(json.dumps(data))
    monkeypatch.setenv("DEPLOYMENT_METADATA_FILE", str(meta_file))

    meta = load_deployment_metadata()
    assert meta["status"] == "Successful"
    assert meta["is_confirmed"] is True
    assert meta["message"] == "Production deployment verified on EC2."
    assert meta["commit"] == "1a2b3c4"  # Short SHA
    assert meta["commit_message"] == "fix(auth): secure session token handling"
    assert meta["image_tag"] == "sha-1a2b3c4"
    assert meta["workflow_run"] == "98765432"
    # UTC 14:30 + 5:30 = 20:00 (08:00 PM) IST
    assert "08:00 PM IST" in meta["timestamp_ist"]
    assert "18 Nov 2026" in meta["timestamp_ist"]


def test_replacement_behavior_replaces_previous_deployment(monkeypatch, tmp_path):
    """Verify that every successful deployment cleanly replaces the previous metadata."""
    meta_file = tmp_path / "deployment.json"

    # 1. Deployment A
    deploy_a = {
        "deployment_status": "Successful",
        "deployment_commit": "aaaaaaa1111",
        "deployment_commit_message": "Commit A message",
        "deployment_timestamp_utc": "2026-11-18T10:00:00Z",
    }
    meta_file.write_text(json.dumps(deploy_a))
    monkeypatch.setenv("DEPLOYMENT_METADATA_FILE", str(meta_file))

    meta_a = load_deployment_metadata()
    assert meta_a["commit"] == "aaaaaaa"
    assert meta_a["commit_message"] == "Commit A message"
    # UTC 10:00 + 5:30 = 15:30 (03:30 PM) IST
    assert "03:30 PM IST" in meta_a["timestamp_ist"]

    # 2. Deployment B atomically replaces Deployment A
    deploy_b = {
        "deployment_status": "Successful",
        "deployment_commit": "bbbbbbb2222",
        "deployment_commit_message": "Commit B message",
        "deployment_timestamp_utc": "2026-11-18T16:00:00Z",
    }
    # Atomic write pattern: write to tmp then replace
    tmp_staging = tmp_path / "deployment.json.tmp"
    tmp_staging.write_text(json.dumps(deploy_b))
    tmp_staging.replace(meta_file)

    meta_b = load_deployment_metadata()
    assert meta_b["commit"] == "bbbbbbb"
    assert meta_b["commit_message"] == "Commit B message"
    # UTC 16:00 + 5:30 = 21:30 (09:30 PM) IST
    assert "09:30 PM IST" in meta_b["timestamp_ist"]


def test_corrupted_json_file_handled_gracefully(monkeypatch, tmp_path):
    """Verify corrupted JSON file does not crash the application."""
    bad_file = tmp_path / "deployment.json"
    bad_file.write_text("{invalid_json: true, unterminated")
    monkeypatch.setenv("DEPLOYMENT_METADATA_FILE", str(bad_file))

    meta = load_deployment_metadata()
    assert meta["status"] == "Successful"
    assert meta["commit"] == "0bf459f"


def test_timezone_conversion_utc_to_ist():
    """Verify UTC ISO-8601 conversion to Asia/Kolkata (IST)."""
    # UTC: 2026-06-01 00:00:00 UTC -> IST is 05:30 AM
    ist_str, utc_str = parse_timestamp_to_ist("2026-06-01T00:00:00Z")
    assert "05:30 AM IST" in ist_str
    assert "01 Jun 2026" in ist_str
    assert "2026-06-01 00:00:00 UTC" in utc_str

    # Invalid timestamp fallback
    fallback_ist, fallback_utc = parse_timestamp_to_ist("invalid-date-string")
    assert "IST" in fallback_ist


def test_homepage_renders_deployment_card(client, monkeypatch, tmp_path):
    """Verify the homepage renders the latest deployment status card with all elements."""
    meta_file = tmp_path / "deployment.json"
    data = {
        "deployment_status": "Successful",
        "deployment_message": "Live automated verification on port 5001.",
        "deployment_timestamp_utc": "2026-11-18T12:00:00Z",
        "deployment_commit": "c0ffee7",
        "deployment_commit_message": "feat(status): add live deployment status indicator",
        "deployment_image_tag": "sha-c0ffee7",
        "deployment_workflow_run": "456",
    }
    meta_file.write_text(json.dumps(data))
    monkeypatch.setenv("DEPLOYMENT_METADATA_FILE", str(meta_file))

    response = client.get("/")
    assert response.status_code == 200
    html = response.get_data(as_text=True)

    # 1. Heading and status
    assert "Latest Deployment" in html
    assert "Successful" in html
    assert "deployment-badge-success" in html
    assert "status-dot-success" in html

    # 2. Message and pipeline
    assert "Live automated verification on port 5001." in html
    assert "GitHub Actions" in html
    assert "GitHub Actions → GHCR → Puppet Master → Puppet Agent" in html

    # 3. Dynamic commit and IST timestamp
    assert "c0ffee7" in html
    assert "feat(status): add live deployment status indicator" in html
    # UTC 12:00 + 5:30 = 17:30 (05:30 PM) IST
    assert "05:30 PM IST" in html


def test_complex_commit_message_serialization(client, monkeypatch, tmp_path):
    """Verify arbitrary commit messages with quotes, backslashes, and newlines
    load and render safely without breaking JSON or template parsing.
    """
    meta_file = tmp_path / "deployment.json"
    complex_msg = 'fix(core): "sanitize" \\path\\to\\file\nnew line with \ttab and "quotes"'
    data = {
        "deployment_status": "Successful",
        "deployment_message": "Production deployment with complex message.",
        "deployment_timestamp_utc": "2026-11-18T15:00:00Z",
        "deployment_commit": "abcdef1",
        "deployment_commit_message": complex_msg,
        "deployment_image_tag": "sha-abcdef1",
        "deployment_workflow_run": "789",
    }
    # Simulate python json.dumps serialization as done by update-app-version.sh
    serialized = json.dumps(data)
    meta_file.write_text(serialized)
    monkeypatch.setenv("DEPLOYMENT_METADATA_FILE", str(meta_file))

    meta = load_deployment_metadata()
    assert meta["commit_message"] == complex_msg
    assert meta["commit"] == "abcdef1"

    response = client.get("/")
    assert response.status_code == 200
    html = response.get_data(as_text=True)
    # Jinja2 auto-escapes HTML characters (&#34; or &quot;) safely
    assert "abcdef1" in html
    assert "sanitize" in html
    assert "\\path\\to\\file" in html


@pytest.mark.parametrize("case_name,commit_msg", [
    ("apostrophes", "fix: don't crash"),
    ("double_quotes", 'fix: "null" handling'),
    ("dollar_signs", "fix: cost $100"),
    ("backticks", "fix: handle `command`"),
    ("backslashes_windows", r"fix: C:\Users\path\to\file and \new\path"),
    ("newlines_tabs", "feat: title\n\nbody with\ttab"),
    ("unicode_emoji", "feat: add café ☕ & rocket 🚀 日本語"),
    ("empty_message", ""),
])
def test_all_special_character_commit_messages(
    case_name, commit_msg, client, monkeypatch, tmp_path
):
    """Verify all 8 special character classes encode, decode, and render cleanly."""
    meta_file = tmp_path / f"deployment_{case_name}.json"

    # 1. Base64 encode as done in orchestrate-phase4.sh
    b64_val = base64.b64encode(commit_msg.encode("utf-8")).decode("ascii")

    # 2. Strict Base64 decode as done in update-app-version.sh
    if not b64_val:
        decoded_msg = ""
    else:
        decoded_bytes = base64.b64decode(b64_val.encode("ascii"), validate=True)
        decoded_msg = decoded_bytes.decode("utf-8")
    assert decoded_msg == commit_msg

    # 3. JSON payload constructed and loaded
    data = {
        "deployment_status": "Successful",
        "deployment_message": f"Deployment verification for {case_name}.",
        "deployment_timestamp_utc": "2026-11-18T16:00:00Z",
        "deployment_commit": "1122334",
        "deployment_commit_message": decoded_msg,
        "deployment_image_tag": "sha-1122334",
        "deployment_workflow_run": "999",
    }
    meta_file.write_text(json.dumps(data))
    monkeypatch.setenv("DEPLOYMENT_METADATA_FILE", str(meta_file))

    meta = load_deployment_metadata()
    assert meta["commit_message"] == commit_msg
    assert meta["commit"] == "1122334"

    # 4. Render homepage
    response = client.get("/")
    assert response.status_code == 200
    html = response.get_data(as_text=True)
    assert "1122334" in html
    assert "Latest Deployment" in html


def test_invalid_base64_commit_message_decoding_rejected():
    """Verify invalid base64 input or non-UTF8 bytes are strictly rejected."""
    # Invalid characters in base64 string
    with pytest.raises((binascii.Error, ValueError)):
        base64.b64decode("invalid_base64_symbols!!!".encode("ascii"), validate=True)

    # Invalid UTF-8 bytes inside valid base64
    bad_bytes_b64 = base64.b64encode(b"\xff\xfe\xfd").decode("ascii")
    decoded_raw = base64.b64decode(bad_bytes_b64.encode("ascii"), validate=True)
    with pytest.raises(UnicodeDecodeError):
        decoded_raw.decode("utf-8")


def test_update_app_version_script_execution(tmp_path):
    """Execute update-app-version.sh in an isolated environment and verify Hiera updates."""
    scripts_dir = tmp_path / "scripts"
    data_dir = tmp_path / "data"
    scripts_dir.mkdir(parents=True)
    data_dir.mkdir(parents=True)

    yaml_file = data_dir / "common.yaml"
    yaml_file.write_text(
        "---\n"
        "lostandfound::image: 'ghcr.io/test/app:sha-old123'\n"
        "lostandfound::deployment_status: 'Successful'\n"
    )

    source_script = os.path.abspath("puppet/scripts/update-app-version.sh")
    with open(source_script, "r", encoding="utf-8") as f:
        script_content = f.read()
    test_script = scripts_dir / "update-app-version.sh"
    test_script.write_text(script_content)
    test_script.chmod(0o755)

    # 1. Update with complex base64 commit message
    complex_msg = r"fix: don't crash on \"null\" and $100 with `cmd` and C:\path"
    msg_b64 = base64.b64encode(complex_msg.encode("utf-8")).decode("ascii")

    res = subprocess.run([
        "bash", str(test_script),
        "ghcr.io/test/app:sha-new456",
        "sha-new456",
        msg_b64,
        "2026-11-18T17:00:00Z",
        "101",
        "Successful"
    ], cwd=str(tmp_path), capture_output=True, text=True)

    assert res.returncode == 0, f"Script failed: {res.stderr}"
    content = yaml_file.read_text()
    assert "lostandfound::image: 'ghcr.io/test/app:sha-new456'" in content
    # Extract deployment_json from single-quoted YAML scalar
    json_match = re.search(
        r"lostandfound::deployment_json:\s*'(.*?)'\s*(?:\n\w|\Z)",
        content,
        re.DOTALL
    )
    assert json_match is not None, "lostandfound::deployment_json not found in common.yaml"
    raw_json = json_match.group(1).replace("''", "'")
    meta = json.loads(raw_json)
    assert meta["deployment_commit_message"] == complex_msg

    # 2. Rollback call with 1 argument restores image and applies default metadata
    res_rollback = subprocess.run([
        "bash", str(test_script),
        "ghcr.io/test/app:sha-old123"
    ], cwd=str(tmp_path), capture_output=True, text=True)

    assert res_rollback.returncode == 0
    content_rb = yaml_file.read_text()
    assert "lostandfound::image: 'ghcr.io/test/app:sha-old123'" in content_rb

    # 3. Invalid base64 fails with non-zero exit
    res_bad = subprocess.run([
        "bash", str(test_script),
        "ghcr.io/test/app:sha-fail",
        "sha-fail",
        "invalid_base64_data!!!"
    ], cwd=str(tmp_path), capture_output=True, text=True)
    assert res_bad.returncode != 0
    assert "Failed to decode base64 commit message" in res_bad.stderr


def test_orchestration_mock_ssh_argument_handling_and_rollback(tmp_path):
    """Test orchestrate-phase4.sh argument handling and rollback transitions via mock SSH."""
    mock_ssh = tmp_path / "mock_ssh.sh"
    log_file = tmp_path / "mock_ssh.log"

    # Mock SSH script that simulates EC2 responses
    mock_script_content = f"""#!/usr/bin/env bash
echo "$@" >> {log_file}
if [[ "$*" == *"grep -E"* ]]; then
  echo "ghcr.io/test/app:sha-baseline"
  exit 0
fi
if [[ "$*" == *"curl -sf http://127.0.0.1:5001/health"* ]]; then
  if [ -f "{tmp_path}/simulate_health_fail" ]; then
    exit 1
  fi
  exit 0
fi
if [[ "$*" == *"puppet agent -t"* ]]; then
  exit 2
fi
exit 0
"""
    mock_ssh.write_text(mock_script_content)
    mock_ssh.chmod(0o755)

    script_path = os.path.abspath("puppet/scripts/orchestrate-phase4.sh")
    env = os.environ.copy()
    env["SKIP_SSH_PREFLIGHT"] = "1"
    env["MOCK_SSH_CMD"] = str(mock_ssh)

    # 1. Successful deployment run: verify base64 encoding and clean arguments
    commit_msg = r"fix: don't crash on \"null\" and $100 with `cmd`"
    res_ok = subprocess.run([
        "bash", script_path,
        "--ssh-deploy-app",
        "10.0.0.1",
        "10.0.0.2",
        "ghcr.io/test/app:sha-target",
        "/dev/null",
        "/dev/null",
        "target1",
        commit_msg,
        "2026-11-18T18:00:00Z",
        "run-1"
    ], capture_output=True, text=True, env=env)

    assert res_ok.returncode == 0, f"Deploy failed: {res_ok.stderr}"
    calls_ok = log_file.read_text()

    # Ensure no raw commit message entered the SSH command line
    assert "don't" not in calls_ok
    assert "$100" not in calls_ok
    assert "`cmd`" not in calls_ok
    # Ensure Base64 string was transmitted
    expected_b64 = base64.b64encode(commit_msg.encode("utf-8")).decode("ascii")
    assert expected_b64 in calls_ok
    # Ensure atomic promotion was executed
    assert "deployment.json.tmp && sudo mv" in calls_ok

    # 2. Failed deployment run: health check failure triggers rollback
    (tmp_path / "simulate_health_fail").write_text("1")
    log_file.write_text("")  # reset log

    res_fail = subprocess.run([
        "bash", script_path,
        "--ssh-deploy-app",
        "10.0.0.1",
        "10.0.0.2",
        "ghcr.io/test/app:sha-target",
        "/dev/null",
        "/dev/null",
        "target1",
        commit_msg,
        "2026-11-18T18:05:00Z",
        "run-2"
    ], capture_output=True, text=True, env=env)

    assert res_fail.returncode == 1, "Script must exit 1 on health check failure!"
    calls_fail = log_file.read_text()

    # Verify pending metadata was deleted
    assert "sudo rm -f /opt/lostandfound/data/deployment_pending.json" in calls_fail
    # Verify Hiera was restored to baseline image
    assert "update-app-version.sh 'ghcr.io/test/app:sha-baseline'" in calls_fail
    # Verify Agent catalog was re-applied
    assert "sudo /opt/puppetlabs/bin/puppet agent -t --detailed-exitcodes" in calls_fail
    # Verify metadata promotion was NEVER executed
    assert "deployment.json.tmp && sudo mv" not in calls_fail
