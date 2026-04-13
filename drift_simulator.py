import subprocess
import json
import sys

def get_state():
    result = subprocess.run(
        ["terraform", "state", "pull"],
        cwd="environments/local",
        capture_output=True,
        text=True
    )
    return json.loads(result.stdout)

def simulate_drift():
    print("\n========================================")
    print("        DRIFT SIMULATOR")
    print("========================================")
    print("Simulating out-of-band infrastructure change...")
    print("Removing S3 bucket from Terraform state")
    print("(mimics someone manually deleting a resource)")
    
    result = subprocess.run(
        ["terraform", "state", "rm", "aws_s3_bucket.my_bucket"],
        cwd="environments/local",
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        print("\n✓ Drift simulated successfully!")
        print("  aws_s3_bucket.my_bucket removed from state")
        print("\nTerraform no longer knows this bucket exists.")
        print("Run drift_detector.py to catch it!")
        print("========================================\n")
    else:
        print(f"\n✗ Error: {result.stderr}")

def restore():
    print("\n========================================")
    print("        RESTORING STATE")
    print("========================================")
    result = subprocess.run(
        ["terraform", "import", "aws_s3_bucket.my_bucket", "my-terraform-bucket"],
        cwd="environments/local",
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        print("✓ State restored! Run drift_detector.py to confirm clean.")
    else:
        print(f"✗ Error: {result.stderr}")
    print("========================================\n")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "restore":
        restore()
    else:
        simulate_drift()