#!/bin/bash
set -e
echo "[*] Running semgrep scan..."
docker run --rm -v "$(pwd)":/src returntocorp/semgrep semgrep --config=auto --json --output /src/semgrep-results.json /src/src || true
echo "[*] Semgrep results: semgrep-results.json"
