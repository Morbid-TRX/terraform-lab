import subprocess
import json
import urllib.request
import os
from datetime import datetime, timezone, timedelta

MYT = timezone(timedelta(hours=8))

def now_myt():
    return datetime.now(MYT).strftime('%Y-%m-%d %H:%M:%S MYT')


def run_terraform_plan():
    print(f"[{datetime.now().strftime('%H:%M:%S')}] Running terraform plan...")

    result = subprocess.run(
        ["terraform", "plan", "-json", "-detailed-exitcode"],
        cwd="environments/local",
        capture_output=True,
        text=True
    )

    return result


def parse_plan_output(result):
    changes = []
    lines = result.stdout.strip().split("\n")

    for line in lines:
        try:
            data = json.loads(line)
            if data.get("type") == "resource_drift":
                resource = data.get("change", {}).get("resource", {})
                changes.append({
                    "type": "DRIFT",
                    "resource": resource.get("resource_type", "unknown"),
                    "name": resource.get("resource_name", "unknown")
                })
            elif data.get("type") == "planned_change":
                change = data.get("change", {})
                action = change.get("action", "unknown")
                resource = change.get("resource", {})
                if action != "no-op":
                    changes.append({
                        "type": action.upper(),
                        "resource": resource.get("resource_type", "unknown"),
                        "name": resource.get("resource_name", "unknown")
                    })
        except json.JSONDecodeError:
            continue

    return changes


def send_slack_alert(changes, exit_code):
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")
    if not webhook_url:
        print("[INFO] No SLACK_WEBHOOK_URL found, skipping Slack notification.")
        return

    if os.environ.get("GITHUB_ACTIONS") == "true":
        source = f"GitHub Actions — triggered by {os.environ.get('GITHUB_ACTOR', 'unknown')}"
        run_url = f"https://github.com/{os.environ.get('GITHUB_REPOSITORY')}/actions/runs/{os.environ.get('GITHUB_RUN_ID')}"
        source_value = f"<{run_url}|{source}>"
    else:
        source_value = "🖥️ Local Machine"

    if exit_code == 0:
        message = {
            "text": "✅ *Infrastructure Drift Check*",
            "attachments": [{
                "color": "good",
                "fields": [
                    {"name": "Status", "value": "CLEAN — No drift detected. Infrastructure matches Terraform state.", "inline": False},
                    {"name": "Scan Time", "value": datetime.now(timezone(timedelta(hours=8))).strftime('%Y-%m-%d %H:%M:%S MYT'), "inline": True},
                    {"name": "Source", "value": source_value, "inline": True}
                ]
            }]
        }
    elif exit_code == 2:
        changes_text = "\n".join([f"• [{c['type']}] {c['resource']}.{c['name']}" for c in changes])
        message = {
            "text": "🚨 *Infrastructure Drift Detected!*",
            "attachments": [{
                "color": "danger",
                "fields": [
                    {"name": "Status", "value": f"DRIFT DETECTED — {len(changes)} change(s) found", "inline": False},
                    {"name": "Changes", "value": changes_text, "inline": False},
                    {"name": "Scan Time", "value": datetime.now(timezone(timedelta(hours=8))).strftime('%Y-%m-%d %H:%M:%S MYT'), "inline": True},
                    {"name": "Source", "value": source_value, "inline": True},
                    {"name": "Action Required", "value": "Click below to approve remediation", "inline": False},
                    {"name": "Remediation Workflow", "value": "https://github.com/Morbid-TRX/terraform-lab/actions/workflows/remediate.yml", "inline": False}
                ]
            }]
        }
    else:
        return

    data = json.dumps(message).encode("utf-8")
    req = urllib.request.Request(webhook_url, data=data, headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req)
        print("[INFO] Slack alert sent successfully.")
    except Exception as e:
        print(f"[ERROR] Failed to send Slack alert: {e}")


def auto_remediate(exit_code):
    if exit_code != 2:
        return

    print("\n" + "="*50)
    print("       AUTO REMEDIATION")
    print("="*50)
    print("Drift detected — triggering auto-remediation...")

    result = subprocess.run(
        ["terraform", "apply", "-auto-approve"],
        cwd="environments/local",
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print("✓ Remediation successful! Infrastructure restored.")
        print(result.stdout)
    else:
        print("✗ Remediation failed!")
        print(result.stderr)

    print("="*50 + "\n")


def check_cost_threshold():
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")
    if not webhook_url:
        return

    print("[INFO] Checking Infracost report for cost threshold...")

    try:
        with open("infracost-report.txt", "r") as f:
            content = f.read()
    except FileNotFoundError:
        print("[INFO] No infracost report found, skipping cost check.")
        return

    threshold = 10.0
    total_cost = 0.0

    for line in content.split("\n"):
        if "OVERALL TOTAL" in line:
            parts = line.split("$")
            if len(parts) > 1:
                try:
                    total_cost = float(parts[-1].strip())
                except ValueError:
                    pass

    print(f"[INFO] Estimated monthly cost: ${total_cost:.2f}")

    if total_cost > threshold:
        message = {
            "text": "💸 *Cost Threshold Exceeded!*",
            "attachments": [{
                "color": "warning",
                "fields": [
                    {"name": "Estimated Monthly Cost", "value": f"${total_cost:.2f}", "inline": True},
                    {"name": "Threshold", "value": f"${threshold:.2f}", "inline": True},
                    {"name": "Action Required", "value": "Review your infrastructure for cost optimization.", "inline": False}
                ]
            }]
        }
        data = json.dumps(message).encode("utf-8")
        req = urllib.request.Request(webhook_url, data=data, headers={"Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req)
            print("[INFO] Cost threshold alert sent to Slack.")
        except Exception as e:
            print(f"[ERROR] Failed to send cost alert: {e}")
    else:
        print(f"[INFO] Cost is within threshold (${threshold:.2f}/month).")


def print_report(changes, exit_code):
    print("\n" + "="*50)
    print("       INFRASTRUCTURE DRIFT REPORT")
    print("="*50)
    print(f"Scan Time : {datetime.now(timezone(timedelta(hours=8))).strftime('%Y-%m-%d %H:%M:%S MYT')}")
    print(f"Exit Code : {exit_code}")
    print("-"*50)

    if exit_code == 0:
        print("STATUS    : CLEAN ✓")
        print("          No drift detected. Infrastructure")
        print("          matches your Terraform state.")
    elif exit_code == 2:
        print(f"STATUS    : DRIFT DETECTED ✗")
        print(f"          {len(changes)} change(s) found:\n")
        for c in changes:
            print(f"  [{c['type']}] {c['resource']}.{c['name']}")
    else:
        print("STATUS    : ERROR")
        print("          Could not complete drift check.")

    print("="*50 + "\n")


def main():
    result = run_terraform_plan()
    changes = parse_plan_output(result)
    print_report(changes, result.returncode)
    send_slack_alert(changes, result.returncode)
    check_cost_threshold()

if __name__ == "__main__":
    main()
