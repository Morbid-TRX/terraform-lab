import subprocess
import json
import urllib.request
import os
from datetime import datetime

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

    if exit_code == 0:
        message = {
            "text": "✅ *Infrastructure Drift Check*",
            "attachments": [{
                "color": "good",
                "fields": [{
                    "title": "Status",
                    "value": "CLEAN — No drift detected. Infrastructure matches Terraform state.",
                    "short": False
                }, {
                    "title": "Scan Time",
                    "value": datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                    "short": True
                }]
            }]
        }
    elif exit_code == 2:
        changes_text = "\n".join([f"• [{c['type']}] {c['resource']}.{c['name']}" for c in changes])
        message = {
            "text": "🚨 *Infrastructure Drift Detected!*",
            "attachments": [{
                "color": "danger",
                "fields": [{
                    "title": "Status",
                    "value": f"DRIFT DETECTED — {len(changes)} change(s) found",
                    "short": False
                }, {
                    "title": "Changes",
                    "value": changes_text,
                    "short": False
                }, {
                    "title": "Scan Time",
                    "value": datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                    "short": True
                }]
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

def print_report(changes, exit_code):
    print("\n" + "="*50)
    print("       INFRASTRUCTURE DRIFT REPORT")
    print("="*50)
    print(f"Scan Time : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
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

if __name__ == "__main__":
    main()