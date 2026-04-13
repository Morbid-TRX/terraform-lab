import subprocess
import json
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

if __name__ == "__main__":
    main()