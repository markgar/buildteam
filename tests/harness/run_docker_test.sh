#!/bin/bash
#
# Run a buildteam end-to-end test inside the Docker container.
#
# Usage:
#   ./tests/harness/run_docker_test.sh --name cli-calculator --model claude-sonnet-4.6
#   ./tests/harness/run_docker_test.sh --name cli-calculator --model claude-sonnet-4.6 \
#       --spec-file tests/harness/full/sample_spec_stretto.md
#   ./tests/harness/run_docker_test.sh --name cli-calculator --model claude-sonnet-4.6 --builders 2
#
# Creates a timestamped run directory under tests/harness/runs/<timestamp>/
# with the spec and logs. Builds the Docker image first, then runs it.
#
# Prerequisites:
#   - Docker installed and running
#   - GITHUB_TOKEN set in environment
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS_DIR="$SCRIPT_DIR/runs"
IMAGE="buildteam:latest"
BUILDERS=2
SPEC_FILE=""
NAME=""
MODEL=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)       NAME="$2";      shift 2 ;;
        --model)      MODEL="$2";     shift 2 ;;
        --spec-file)  SPEC_FILE="$2"; shift 2 ;;
        --builders)   BUILDERS="$2";  shift 2 ;;
        --image)      IMAGE="$2";     shift 2 ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 --name <project> --model <model> [--spec-file <path>] [--builders N] [--image <image>]"
            exit 1
            ;;
    esac
done

if [[ -z "$NAME" || -z "$MODEL" ]]; then
    echo "Usage: $0 --name <project> --model <model> [--spec-file <path>] [--builders N]"
    exit 1
fi

if [[ "$BUILDERS" -lt 2 || "$BUILDERS" -gt 8 ]]; then
    echo "Error: --builders must be between 2 and 8 (got $BUILDERS)"
    exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    # Try to get token from gh CLI
    if command -v gh &>/dev/null; then
        export GITHUB_TOKEN="$(gh auth token 2>/dev/null)"
    fi
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "ERROR: GITHUB_TOKEN is not set and gh auth token failed"
        echo "  export GITHUB_TOKEN=\$(gh auth token)"
        exit 1
    fi
    echo "GITHUB_TOKEN set from gh auth token"
fi

# Default spec: search simple/ and full/ subdirectories for a matching spec
if [[ -z "$SPEC_FILE" ]]; then
    SPEC_NAME="sample_spec_${NAME//-/_}.md"
    for subdir in simple full; do
        if [[ -f "$SCRIPT_DIR/$subdir/$SPEC_NAME" ]]; then
            SPEC_FILE="$SCRIPT_DIR/$subdir/$SPEC_NAME"
            break
        fi
    done
    if [[ -z "$SPEC_FILE" ]]; then
        SPEC_FILE="$SCRIPT_DIR/simple/sample_spec_minimal_python_api.md"
    fi
fi

# Resolve to absolute path
SPEC_FILE="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"

if [[ ! -f "$SPEC_FILE" ]]; then
    echo "ERROR: Spec file not found: $SPEC_FILE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Create timestamped run directory
# ---------------------------------------------------------------------------
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$RUNS_DIR/$TIMESTAMP/$NAME-$TIMESTAMP"
mkdir -p "$RUN_DIR/logs"

# Copy spec into run directory
cp "$SPEC_FILE" "$RUN_DIR/spec.md"

REPO_NAME="${NAME}-${TIMESTAMP}"

# Write machine-readable run metadata into the logs dir so it is co-located
# with events.jsonl and agent logs on the mounted volume.
cat > "$RUN_DIR/logs/run-metadata.json" <<EOF
{
  "name": "$NAME",
  "repo_name": "$REPO_NAME",
  "model": "$MODEL",
  "builders": $BUILDERS,
  "spec_file": "$(basename "$SPEC_FILE")",
  "image": "$IMAGE",
  "timestamp": "$TIMESTAMP",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "============================================"
echo " Docker Test Run"
echo "============================================"
echo "  Name:       $NAME"
echo "  Repo:       $REPO_NAME"
echo "  Model:      $MODEL"
echo "  Builders:   $BUILDERS"
echo "  Spec:       $SPEC_FILE"
echo "  Run dir:    $RUN_DIR"
echo "  Image:      $IMAGE"
echo "  Timestamp:  $TIMESTAMP"
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# Build image
# ---------------------------------------------------------------------------
echo "Building Docker image..."
docker build -t "$IMAGE" "$PROJECT_ROOT" 2>&1 | tail -5
echo ""

# ---------------------------------------------------------------------------
# Run container
# ---------------------------------------------------------------------------
CONTAINER_NAME="buildteam-${NAME}-${TIMESTAMP}"
REPO_NAME="${NAME}-${TIMESTAMP}"

echo "Starting container: $CONTAINER_NAME"
echo "  Repo name:   $REPO_NAME"
echo "  Logs will be at: $RUN_DIR/logs/"
echo ""

# Run docker and capture output to log file while also displaying it.
# IMPORTANT: We avoid `docker run ... | tee` because if tee dies or the pipe
# breaks, docker receives SIGPIPE and kills the container — terminating all
# agents mid-work. Instead, write directly to the log file via process
# substitution and tee from there. This way docker's exit is never affected
# by downstream pipe issues.
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$RUN_DIR:/workspace/data" \
    -e GITHUB_TOKEN="$GITHUB_TOKEN" \
    -e BUILDTEAM_LOGS_DIR=/workspace/data/logs \
    --name "$CONTAINER_NAME" \
    "$IMAGE" \
    go --directory "/workspace/$REPO_NAME" --model "$MODEL" \
       --spec-file /workspace/data/spec.md --headless --builders "$BUILDERS" \
    > >(tee "$RUN_DIR/logs/docker-output.log") 2>&1

EXIT_CODE=$?

# Persist exit code and completion timestamp into logs/ for headless analysis
echo "$EXIT_CODE" > "$RUN_DIR/logs/exit-code"

# Append completed_at to run metadata (portable JSON update via temp file)
if command -v python3 &>/dev/null; then
    python3 -c "
import json, datetime, sys
path = '$RUN_DIR/logs/run-metadata.json'
with open(path) as f: d = json.load(f)
d['completed_at'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
d['exit_code'] = $EXIT_CODE
with open(path, 'w') as f: json.dump(d, f, indent=2)
" 2>/dev/null || true
fi

echo ""
echo "============================================"
echo " Run complete (exit code: $EXIT_CODE)"
echo "============================================"
echo "  Logs:         $RUN_DIR/logs/"
echo "  Docker log:   $RUN_DIR/logs/docker-output.log"
echo "  Events:       $RUN_DIR/logs/events.jsonl"
echo "  Metadata:     $RUN_DIR/logs/run-metadata.json"
echo "  Exit code:    $RUN_DIR/logs/exit-code"
echo "============================================"

exit $EXIT_CODE
