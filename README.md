# devsecops-pipeline-demo

Demo repository for a Jenkins CI/CD pipeline that performs SAST, SCA, image scanning, DAST and deploys to staging (docker-compose). This repo includes a deliberately vulnerable Node.js app to be used in labs.

## Contents
- `Jenkinsfile` - declarative pipeline
- `src/` - vulnerable Node.js app
- `Dockerfile` - builds app image
- `docker-compose.yml` - staging deployment
- `scripts/` - helper scripts to run Semgrep, Dependency-Check, Trivy, ZAP

## Prerequisites
- Jenkins server (with Docker-enabled agents) or machine with Docker.
- Docker installed and user allowed to run docker commands.

## Quick local run
1. Build and run app locally:
   ```bash
   docker-compose up --build -d
   ```
2. Visit http://localhost:3000
3. Run semgrep scan:
   ```bash
   ./scripts/run_semgrep.sh
   ```
4. Run dependency-check:
   ```bash
   ./scripts/run_dependency_check.sh
   ```
5. Build image and run trivy:
   ```bash
   docker build -t devsecops-labs-app:local .
   ./scripts/run_trivy.sh devsecops-labs-app:local
   ```
6. Run ZAP scan:
   ```bash
   ./scripts/run_zap.sh http://localhost:3000
   ```

## Notes
- This repository is intentionally insecure — **do not** run in production.
- To enforce gating policies, extend the Jenkinsfile to parse results and fail builds when thresholds are exceeded.
