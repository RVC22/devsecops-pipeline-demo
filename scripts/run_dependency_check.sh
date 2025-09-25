#!/bin/bash
set -e
echo "[*] Running OWASP Dependency-Check..."
mkdir -p dependency-check-reports
docker run --rm -v "$(pwd)":/src owasp/dependency-check:latest --scan /src --format ALL -o /src/dependency-check-reports || true
echo "[*] Dependency check reports in dependency-check-reports/"
