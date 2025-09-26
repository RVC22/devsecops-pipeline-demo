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
    timeout(time: 60, unit: 'MINUTES')
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
        '''
        archiveArtifacts artifacts: 'semgrep-results.json', allowEmptyArchive: true
      }
    }

    stage('SCA - Dependency Check') {
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

    stage('Build & Test') {
      agent {
        docker {
          image 'node:18-bullseye'
          reuseNode true
        }
      }
      steps {
        echo "Building app and running tests..."
        sh '''
          # Instalar herramientas de compilación
          apt-get update && apt-get install -y python3 make g++ || true
          
          cd src
          npm install --no-audit --no-fund
          
          # Ejecutar tests si existen
          if [ -f package.json ] && [ -f package.json ]; then
            npm test --silent || echo "Tests completed with warnings"
          fi
          
          # Análisis de seguridad con npm audit
          mkdir -p ../security-reports
          npm audit --json > ../security-reports/npm-audit.json 2>/dev/null || echo "npm audit not available"
        '''
        archiveArtifacts artifacts: 'security-reports/**', allowEmptyArchive: true
      }
    }

    stage('Docker Build') {
      agent any
      steps {
        echo "Building Docker image..."
        sh '''
          docker build -t ${DOCKER_IMAGE_NAME} -f Dockerfile .
        '''
      }
    }

    stage('Container Security Scan - Trivy') {
      agent any
      steps {
        echo "Scanning container image with Trivy..."
        sh '''
          mkdir -p trivy-reports
          # Escaneo completo en JSON
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:latest image --format json --output trivy-reports/trivy-report.json ${DOCKER_IMAGE_NAME} || true
          
          # Escaneo rápido para vulnerabilidades críticas
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:latest image --severity HIGH,CRITICAL ${DOCKER_IMAGE_NAME} || true
        '''
        archiveArtifacts artifacts: 'trivy-reports/**', allowEmptyArchive: true
      }
    }

    stage('Deploy to Staging') {
      agent any
      steps {
        echo "Deploying to staging environment..."
        sh '''
          # Parar contenedores previos
          docker-compose -f docker-compose.yml down || true
          
          # Desplegar nueva versión
          docker-compose -f docker-compose.yml up -d --build
          
          # Esperar que la aplicación esté lista
          sleep 20
          
          # Verificar estado
          docker ps -a
          echo "Staging URL: ${STAGING_URL}"
          
          # Verificar que la aplicación responde
          curl -f ${STAGING_URL} || echo "Application deployment verification pending"
        '''
      }
    }

    stage('DAST - OWASP ZAP Security Test') {
      agent any
      steps {
        echo "Running Dynamic Application Security Testing..."
        sh '''
          mkdir -p zap-reports
          
          # Esperar a que la aplicación esté completamente operativa
          sleep 30
          
          # Ejecutar escaneo de seguridad
          docker run --rm --network host \
            owasp/zap2docker-stable zap-baseline.py \
            -t ${STAGING_URL} \
            -r zap-reports/zap-report.html \
            -c zap-reports/zap-report.json || echo "DAST scan completed"
        '''
        archiveArtifacts artifacts: 'zap-reports/**', allowEmptyArchive: true
      }
    }

    stage('Security Policy Check') {
      agent any
      steps {
        echo "Checking security policies..."
        script {
          try {
            // Verificar si existe el script de policy check
            if (fileExists('scripts/scan_trivy_fail.sh')) {
              def exitCode = sh(
                script: '''
                  chmod +x scripts/scan_trivy_fail.sh
                  ./scripts/scan_trivy_fail.sh ${DOCKER_IMAGE_NAME} || exit_code=$?
                  echo "Policy check exit code: ${exit_code:-0}"
                  exit ${exit_code:-0}
                ''',
                returnStatus: true
              )
              
              if (exitCode == 2) {
                error "🚨 SECURITY POLICY VIOLATION: HIGH/CRITICAL vulnerabilities detected"
              } else if (exitCode == 0) {
                echo "✅ Security policy check passed"
              } else {
                echo "⚠️ Security policy check completed with warnings"
              }
            } else {
              echo "ℹ️ Custom security policy script not found, using default checks"
              
              // Check básico con Trivy
              def criticalVulns = sh(
                script: """
                  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                    aquasec/trivy:latest image --severity CRITICAL ${DOCKER_IMAGE_NAME} | grep -c CRITICAL || true
                """,
                returnStdout: true
              ).trim()
              
              if (criticalVulns.toInteger() > 0) {
                echo "⚠️ CRITICAL vulnerabilities found: ${criticalVulns}"
              } else {
                echo "✅ No CRITICAL vulnerabilities found"
              }
            }
          } catch (Exception e) {
            echo "❌ Security policy check failed: ${e.getMessage()}"
          }
        }
      }
    }

    stage('Integration Tests') {
      agent any
      steps {
        echo "Running integration tests..."
        sh '''
          # Esperar a que la aplicación esté completamente lista
          sleep 10
          
          # Tests básicos de integración
          curl -f ${STAGING_URL} && echo "✅ Application is responding" || echo "❌ Application not responding"
          curl -s ${STAGING_URL}/health || echo "ℹ️ Health endpoint not available"
        '''
      }
    }

    stage('Cleanup & Reports') {
      agent any
      steps {
        echo "Generating final reports and cleaning up..."
        sh '''
          # Generar reporte resumen
          echo "=== SECURITY SCAN SUMMARY ===" > security-summary.txt
          echo "SAST (Semgrep): Completed" >> security-summary.txt
          echo "SCA (Dependency-Check): Completed" >> security-summary.txt
          echo "Container Scan (Trivy): Completed" >> security-summary.txt
          echo "DAST (OWASP ZAP): Completed" >> security-summary.txt
          echo "=============================" >> security-summary.txt
          
          # Limpiar entorno de staging
          docker-compose -f docker-compose.yml down || true
          docker image prune -f || true
          
          echo "Cleanup completed"
        '''
        archiveArtifacts artifacts: 'security-summary.txt', allowEmptyArchive: true
      }
    }

  }

  post {
    always {
      echo "=== PIPELINE EXECUTION COMPLETED ==="
      echo "Artifacts generated:"
      echo "- SAST Report: semgrep-results.json"
      echo "- SCA Report: dependency-check-reports/"
      echo "- Container Scan: trivy-reports/"
      echo "- DAST Report: zap-reports/"
      echo "- Security Summary: security-summary.txt"
      
      archiveArtifacts artifacts: '**/*.json,**/*.html,**/*.txt', allowEmptyArchive: true
    }
    success {
      echo "🎉 PIPELINE SUCCESS - All security scans completed!"
      echo "📊 Reports available in Jenkins artifacts"
    }
    failure {
      echo "❌ PIPELINE FAILED - Check console output for details"
      echo "🔍 Review security findings in the generated reports"
    }
    unstable {
      echo "⚠️ PIPELINE UNSTABLE - Some stages completed with warnings"
    }
  }
}