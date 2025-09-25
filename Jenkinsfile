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
    // ✅ 1. Requiere el plugin AnsiColor instalado.
    ansiColor('xterm')
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh 'ls -la'
      }
    }

    stage('SAST - Semgrep') {
      // ✅ CORREGIDO: Se añadió 'agent' envolviendo a 'docker'.
      agent {
        docker { image 'returntocorp/semgrep:latest' }
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
      // ✅ CORREGIDO: Se añadió 'agent' envolviendo a 'docker'.
      agent {
        docker { image 'owasp/dependency-check:latest' }
      }
      steps {
        echo "Running SCA / Dependency-Check..."
        sh '''
          mkdir -p dependency-check-reports
          dependency-check --project "devsecops-labs" --scan . --format JSON --out dependency-check-reports || true
        '''
        archiveArtifacts artifacts: 'dependency-check-reports/**', allowEmptyArchive: true
      }
    }

    stage('Build') {
      agent { label 'docker' }
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
      agent { label 'docker' }
      steps {
        echo "Building Docker image..."
        sh '''
          docker build -t ${DOCKER_IMAGE_NAME} -f Dockerfile .
        '''
        echo "Scanning image with Trivy..."
        sh '''
          mkdir -p trivy-reports
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --format json --output trivy-reports/trivy-report.json ${DOCKER_IMAGE_NAME} || true
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL ${DOCKER_IMAGE_NAME} || true
        '''
        archiveArtifacts artifacts: 'trivy-reports/**', allowEmptyArchive: true
      }
    }

    stage('Push Image (optional)') {
      when {
        expression { return env.DOCKER_REGISTRY != null && env.DOCKER_REGISTRY != "" }
      }
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
      agent { label 'docker' }
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
      agent { label 'docker' }
      steps {
        echo "Running DAST (OWASP ZAP) against ${STAGING_URL} ..."
        sh '''
          mkdir -p zap-reports
          docker run --rm --network host owasp/zap2docker-stable zap-baseline.py -t ${STAGING_URL} -r zap-reports/zap-report.html || true
        '''
        archiveArtifacts artifacts: 'zap-reports/**', allowEmptyArchive: true
      }
    }

    stage('Policy Check - Fail on HIGH/CRITICAL CVEs') {
      agent { label 'docker' } // Se añadió 'agent' ya que probablemente necesite Docker o un agente específico.
      steps {
        sh '''
          chmod +x scripts/scan_trivy_fail.sh
          ./scripts/scan_trivy_fail.sh ${DOCKER_IMAGE_NAME} || exit_code=$?
          if [ "${exit_code:-0}" -eq 2 ]; then
            echo "Failing pipeline due to HIGH/CRITICAL vulnerabilities detected by Trivy."
            // Se usa 'error' de Groovy para forzar el fallo limpio en Jenkins.
            error "Policy Check FAILED: HIGH/CRITICAL vulnerabilities found by Trivy."
          fi
        '''
      }
    }

  } // stages

  post {
    always {
      echo "Pipeline finished. Collecting artifacts..."
      // Asegurar limpieza del entorno de staging
      stage('Cleanup') {
        steps {
          sh 'docker-compose -f docker-compose.yml down || true'
          echo "Staging environment cleaned up."
        }
      }
    }
    failure {
      echo "Pipeline failed! Check console output for scan results."
    }
  }
}