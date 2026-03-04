#!/usr/bin/env bash
set -euo pipefail

# launch.sh — Launch a buildteam job on AKS for any project
#
# Usage:
#   ./deploy/aks/launch.sh <project-name> [options]
#
# Options:
#   --model <model>       Copilot model (default: claude-sonnet-4.6)
#   --builders <N>        Number of builders (default: 2)
#
# Examples:
#   # Upload spec + launch in one go:
#   ./buildteam-build-on/aks/prepare-spec.sh log-viewer tests/harness/simple/sample_spec_log_viewer_api.md
#   ./buildteam-build-on/aks/launch.sh log-viewer
#
#   # With options:
#   ./buildteam-build-on/aks/launch.sh log-viewer --model claude-opus-4.6 --builders 3
#
#   # Full one-liner:
#   ./buildteam-build-on/aks/prepare-spec.sh log-viewer my-spec.md && ./buildteam-build-on/aks/launch.sh log-viewer
#
# Prerequisites:
#   - kubectl context pointing at the AKS cluster
#   - buildteam-build-on/aks/namespace.yaml and secret-provider.yaml already applied
#   - Spec uploaded via prepare-spec.sh
#
# To monitor:
#   kubectl logs -f job/buildteam-<project-name>
#
# To stop:
#   kubectl delete job buildteam-<project-name>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
MODEL="claude-sonnet-4.6"
BUILDERS="2"

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <project-name> [--model <model>] [--builders <N>]"
    exit 1
fi

PROJECT_NAME="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            MODEL="$2"
            shift 2
            ;;
        --builders)
            BUILDERS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 <project-name> [--model <model>] [--builders <N>]"
            exit 1
            ;;
    esac
done

JOB_NAME="buildteam-${PROJECT_NAME}"

echo "==> Launching buildteam job"
echo "    Project:  $PROJECT_NAME"
echo "    Model:    $MODEL"
echo "    Builders: $BUILDERS"
echo "    Job:      $JOB_NAME"
echo ""

# ---------------------------------------------------------------------------
# Ensure base resources exist
# ---------------------------------------------------------------------------
echo "==> Ensuring base resources (service account, secret provider)..."
kubectl apply -f "$SCRIPT_DIR/namespace.yaml" 2>/dev/null || true
kubectl apply -f "$SCRIPT_DIR/secret-provider.yaml" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Clean up any previous job with the same name
# ---------------------------------------------------------------------------
if kubectl get job "$JOB_NAME" &>/dev/null; then
    echo "==> Deleting previous job: $JOB_NAME"
    kubectl delete job "$JOB_NAME" --wait=true 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Generate job YAML from template and apply
# ---------------------------------------------------------------------------
echo "==> Applying job from template..."
sed \
    -e "s/__PROJECT_NAME__/${PROJECT_NAME}/g" \
    -e "s/__MODEL__/${MODEL}/g" \
    -e "s/__BUILDERS__/${BUILDERS}/g" \
    "$SCRIPT_DIR/job.yaml" \
    | kubectl apply -f -

# ---------------------------------------------------------------------------
# Wait for pod to start and show status
# ---------------------------------------------------------------------------
echo ""
echo "==> Waiting for pod to start..."
for i in $(seq 1 30); do
    POD=$(kubectl get pods -l "job-name=$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$POD" ]]; then
        STATUS=$(kubectl get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
        if [[ "$STATUS" == "Running" ]]; then
            echo "==> Pod running: $POD"
            break
        fi
        echo "    Pod $POD status: $STATUS"
    fi
    sleep 2
done

echo ""
echo "==> Build launched! Monitor with:"
echo "    kubectl logs -f job/$JOB_NAME"
echo ""
echo "    Stop with:"
echo "    kubectl delete job $JOB_NAME"
