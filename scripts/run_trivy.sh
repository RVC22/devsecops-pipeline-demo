#!/bin/bash
set -e
IMAGE=${1:-devsecops-labs-app:local}
mkdir -p trivy-reports
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --format json --output trivy-reports/trivy-report.json --severity HIGH,CRITICAL $IMAGE || true
echo "[*] Trivy report at trivy-reports/trivy-report.json"
