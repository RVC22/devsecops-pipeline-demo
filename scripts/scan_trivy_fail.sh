#!/bin/bash
# scan_trivy_fail.sh
# Usage:
#   ./scan_trivy_fail.sh <image-name>
#   or
#   ./scan_trivy_fail.sh -j reporte.json    # use existing trivy JSON report
#
# Exits with code 0 if no HIGH/CRITICAL vulnerabilities are found.
# Exits with code 2 if HIGH/CRITICAL vulnerabilities are present.
# Exits with code 1 on other errors.
#
# Requirements: jq (recommended) and docker (if running trivy via docker).
# If jq is not available, the script will attempt a grep-based fallback (less precise).
set -euo pipefail

print_help() {
  cat <<EOF
scan_trivy_fail.sh - scan image with Trivy or evaluate an existing report and fail on HIGH/CRITICAL CVEs.

Usage:
  ./scan_trivy_fail.sh <image-name>
  ./scan_trivy_fail.sh -j <trivy-report.json>

Examples:
  ./scan_trivy_fail.sh my-image:latest
  ./scan_trivy_fail.sh -j trivy-reports/trivy-report.json
EOF
}

if [ "$#" -lt 1 ]; then
  print_help
  exit 1
fi

MODE="scan"   # or "json"
IMAGE=""
JSON_REPORT=""

if [ "$1" = "-j" ]; then
  if [ "$#" -ne 2 ]; then
    echo "Error: -j requires a JSON filename"
    print_help
    exit 1
  fi
  MODE="json"
  JSON_REPORT="$2"
else
  IMAGE="$1"
fi

# Where to place report
OUT_DIR="trivy-reports"
mkdir -p "$OUT_DIR"
TRIVY_JSON="$OUT_DIR/trivy-report.json"

run_trivy_scan() {
  echo "[*] Running Trivy scan for image: $IMAGE (HIGH,CRITICAL only)"
  # Prefer trivy CLI if available
  if command -v trivy >/dev/null 2>&1; then
    trivy image --format json --output "$TRIVY_JSON" --severity HIGH,CRITICAL "$IMAGE" || true
  else
    # Fallback to docker image of trivy (requires docker)
    if command -v docker >/dev/null 2>&1; then
      docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --format json --output /tmp/trivy-report.json --severity HIGH,CRITICAL "$IMAGE" || true
      docker cp $(docker ps -alq):/tmp/trivy-report.json "$TRIVY_JSON" 2>/dev/null || true
      # If docker cp failed, try to write to mounted volume (alternate approach)
      if [ ! -s "$TRIVY_JSON" ]; then
        docker run --rm -v "$(pwd)/$OUT_DIR":/results aquasec/trivy:latest image --format json --output /results/trivy-report.json --severity HIGH,CRITICAL "$IMAGE" || true
      fi
    else
      echo "Error: neither trivy nor docker found in PATH."
      exit 1
    fi
  fi
}

# Copy provided JSON if mode=json
if [ "$MODE" = "json" ]; then
  if [ ! -f "$JSON_REPORT" ]; then
    echo "Error: JSON report '$JSON_REPORT' does not exist."
    exit 1
  fi
  cp "$JSON_REPORT" "$TRIVY_JSON"
else
  run_trivy_scan
fi

if [ ! -s "$TRIVY_JSON" ]; then
  echo "[!] Warning: Trivy report is empty or missing: $TRIVY_JSON"
  # Try quick grep fallback on human-readable output (if exists)
  exit 1
fi

echo "[*] Trivy JSON report saved at: $TRIVY_JSON"

# Function to check using jq if present
check_with_jq() {
  # Count HIGH/CRITICAL vulnerabilities
  COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL")] | length' "$TRIVY_JSON" 2>/dev/null || echo "0")
  if [ "$COUNT" -gt 0 ]; then
    echo "[!] Found $COUNT HIGH/CRITICAL vulnerabilities (via jq)"
    jq '[.Results[].Vulnerabilities[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL") | {VulnerabilityID, PkgName, InstalledVersion, FixedVersion, Severity, Title}]' "$TRIVY_JSON"
    return 2
  else
    echo "[*] No HIGH or CRITICAL vulnerabilities found (via jq)"
    return 0
  fi
}

# Fallback grep-based check (less precise)
check_with_grep() {
  echo "[*] Fallback: checking JSON with grep for HIGH/CRITICAL keywords."
  # This will search for lines containing "Severity": "HIGH" or "Severity": "CRITICAL"
  MATCHES=$(grep -E '"Severity":\s*"(HIGH|CRITICAL)"' -n "$TRIVY_JSON" || true)
  if [ -n "$MATCHES" ]; then
    echo "[!] Found HIGH/CRITICAL severity entries (grep fallback)"
    # Print a small context around matches for quick triage
    echo "$MATCHES"
    # Try to print the VulnerabilityID lines nearby
    echo "---- Contextual snippet (VulnerabilityID and Severity) ----"
    grep -nE '"VulnerabilityID"|"Severity"' "$TRIVY_JSON" | sed -n '1,200p'
    return 2
  else
    echo "[*] No HIGH/CRITICAL vulnerabilities found (grep fallback)"
    return 0
  fi
}

# Decide which checker to use
if command -v jq >/dev/null 2>&1; then
  check_with_jq
  EXIT_CODE=$?
else
  check_with_grep
  EXIT_CODE=$?
fi

# Final exit handling
if [ "$EXIT_CODE" -eq 2 ]; then
  echo "[ERROR] Security policy violation: HIGH/CRITICAL CVEs detected. Failing."
  exit 2
elif [ "$EXIT_CODE" -eq 0 ]; then
  echo "[OK] Image passed HIGH/CRITICAL policy."
  exit 0
else
  echo "[ERROR] Unexpected error during analysis. Exit code: $EXIT_CODE"
  exit 1
fi
