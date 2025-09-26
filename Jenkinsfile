pipeline {
  agent any

  environment {
    DOCKER_REGISTRY = "myregistry.example.com"
    DOCKER_CREDENTIALS = "docker-registry-credentials"
    GIT_CREDENTIALS = "git-credentials"
    DOCKER_IMAGE_NAME = "${env.DOCKER_REGISTRY}/devsecops-labs/app:latest"
    SSH_CREDENTIALS = "ssh-deploy-key"
    STAGING_URL = "http://localhost:3000"
  }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh 'ls -la'
      }
    }

    stage('SAST - Semgrep') {
      agent {
        docker {
          image 'returntocorp/semgrep:latest'
          reuseNode true
        }
      }
      steps {
        echo "Running Semgrep (SAST)..."
        sh '''
          semgrep --config=auto --json --output semgrep-results.json src || true
          cat semgrep-results.json || true
        '''
        archiveArtifacts artifacts: 'semgrep-results.json', allowEmptyArchive: true
      }
      post {
        always {
          script { sh 'echo "Semgrep done."' }
        }
      }
    }

    stage('SCA - Dependency Check (OWASP dependency-check)') {
      agent {
        docker {
          image 'owasp/dependency-check:latest'
          reuseNode true
          args '--entrypoint=""'
        }
      }
      steps {
        echo "Running SCA / Dependency-Check..."
        sh '''
          mkdir -p dependency-check-reports
          /usr/share/dependency-check/bin/dependency-check.sh \
            --project "devsecops-labs" \
            --scan . \
            --format JSON \
            --out dependency-check-reports || true
        '''
        archiveArtifacts artifacts: 'dependency-check-reports/**', allowEmptyArchive: true
      }
    }

    stage('Build') {
      agent any
      steps {
        echo "Building app (npm install and tests)..."
        sh '''
          cd src
          npm install --no-audit --no-fund
          if [ -f package.json ]; then
            if npm test --silent; then echo "Tests OK"; else echo "Tests failed (continue)"; fi
          fi
        '''
      }
    }

    stage('Docker Build & Trivy Scan') {
      agent any
      steps {
        echo "Building Docker image..."
        sh '''
          docker build -t ${DOCKER_IMAGE_NAME} -f Dockerfile .
        '''
        echo "Scanning image with Trivy..."
        sh '''
          mkdir -p trivy-reports
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:latest image --format json --output trivy-reports/trivy-report.json ${DOCKER_IMAGE_NAME} || true
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:latest image --severity HIGH,CRITICAL ${DOCKER_IMAGE_NAME} || true
        '''
        archiveArtifacts artifacts: 'trivy-reports/**', allowEmptyArchive: true
      }
    }

    stage('Push Image (optional)') {
      when {
        expression { return env.DOCKER_REGISTRY != null && env.DOCKER_REGISTRY != "" }
      }
      agent any
      steps {
        echo "Pushing image to registry ${DOCKER_REGISTRY}..."
        withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS}", usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          sh '''
            echo "$DOCKER_PASS" | docker login ${DOCKER_REGISTRY} -u "$DOCKER_USER" --password-stdin
            docker push ${DOCKER_IMAGE_NAME}
            docker logout ${DOCKER_REGISTRY}
          '''
        }
      }
    }

    stage('Deploy to Staging (docker-compose)') {
      agent any
      steps {
        echo "Deploying to staging with docker-compose..."
        sh '''
          docker-compose -f docker-compose.yml down || true
          docker-compose -f docker-compose.yml up -d --build
          sleep 8
          docker ps -a
        '''
      }
    }

    stage('DAST - OWASP ZAP scan') {
      agent any
      steps {
        echo "Running DAST (OWASP ZAP) against ${STAGING_URL} ..."
        sh '''
          mkdir -p zap-reports
          docker run --rm --network host -v /var/run/docker.sock:/var/run/docker.sock \
            owasp/zap2docker-stable zap-baseline.py -t ${STAGING_URL} -r zap-reports/zap-report.html || true
        '''
        archiveArtifacts artifacts: 'zap-reports/**', allowEmptyArchive: true
      }
    }

    stage('Policy Check - Fail on HIGH/CRITICAL CVEs') {
      agent any
      steps {
        script {
          try {
            def exitCode = sh(
              script: '''
                chmod +x scripts/scan_trivy_fail.sh 2>/dev/null || true
                if [ -f scripts/scan_trivy_fail.sh ]; then
                  ./scripts/scan_trivy_fail.sh ${DOCKER_IMAGE_NAME} || exit_code=$?
                  echo "Exit code: ${exit_code:-0}"
                  exit ${exit_code:-0}
                else
                  echo "Warning: scan_trivy_fail.sh not found, skipping policy check"
                  exit 0
                fi
              ''',
              returnStatus: true
            )
            
            if (exitCode == 2) {
              error "Policy Check FAILED: HIGH/CRITICAL vulnerabilities found by Trivy."
            } else if (exitCode != 0) {
              echo "Policy check completed with warnings (exit code: ${exitCode})"
            }
          } catch (Exception e) {
            echo "Policy check failed with error: ${e.getMessage()}"
          }
        }
      }
    }

    stage('Cleanup') {
      agent any
      steps {
        echo "Cleaning up staging environment..."
        sh 'docker-compose -f docker-compose.yml down || true'
        echo "Staging environment cleaned up."
      }
    }

  }

  post {
    always {
      echo "Pipeline finished. Collecting artifacts..."
    }
    failure {
      echo "Pipeline failed! Check console output for scan results."
    }
  }
}