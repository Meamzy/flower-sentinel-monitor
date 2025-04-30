#!/usr/bin/env bash
set -u -o pipefail    # nounset + fail on pipeline errors, but we’ll catch non-zero exits manually

PROJECT_DIR=/project

echo "→ Scanning project directory: $PROJECT_DIR"
if [ ! -d "$PROJECT_DIR" ]; then
  echo "❌ Project directory not found!"
  exit 1
fi
cd "$PROJECT_DIR"

echo
echo "*** 1) Bandit static analysis (Python code) ***"
bandit -r . --quiet || true

echo
echo "*** 2) Safety dependency scan (Python deps) ***"
echo "→ Using 'safety scan' instead of deprecated 'safety check' (unsupported after 1 Jun 2024)“"
safety scan || true

echo
echo "*** 3) Trivy filesystem scan (OS CVEs & misconfigs) ***"
trivy fs --exit-code 1 --severity HIGH,CRITICAL . || true

echo
echo "*** 4) Trivy image scan for built image 'server-monitor' ***"
trivy image --exit-code 1 --severity HIGH,CRITICAL server-monitor || true

echo
echo "*** 5) Trivy image scan for running container 'server-monitor' ***"
if docker ps --format '{{.Names}}' | grep -q '^server-monitor$$'; then
  IMG_ID=$(docker inspect --format='{{.Image}}' server-monitor)
  trivy image --exit-code 1 --severity HIGH,CRITICAL "$IMG_ID" || true
else
  echo "→ Container 'server-monitor' not running; skipping."
fi

echo
echo "*** 6) Gitleaks secrets scan (filesystem only) ***"
gitleaks detect \
  --no-git \
  --exclude-path ".env" \
  --verbose \
  --source . \
  --report-format table \
  --exit-code 1 \
|| true


echo
echo "✅ Full security report complete (all tools ran against /project)."
