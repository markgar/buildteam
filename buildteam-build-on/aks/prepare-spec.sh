#!/usr/bin/env bash
set -euo pipefail

# prepare-spec.sh — Upload a spec file to a project's blob container via AKS
#
# Usage:
#   ./buildteam-build-on/aks/prepare-spec.sh <project-name> <spec-file>
#
# Examples:
#   ./buildteam-build-on/aks/prepare-spec.sh log-viewer tests/harness/simple/sample_spec_log_viewer_api.md
#   ./buildteam-build-on/aks/prepare-spec.sh autodev tests/harness/full/sample_spec_autodev.md
#
# What it does:
#   1. Connects to AKS (gets credentials if needed)
#   2. Ensures the project's blob container exists (name = project-name)
#   3. Uploads the spec file as REQUIREMENTS.md in the container
#
# The container uses the project name directly. Logs are stored under
# a logs/ prefix within the same container.
#
# Why AKS: The storage account (stautodevqqq) has a firewall with defaultAction=Deny.
# Only private endpoints from the VNet are allowed, so we run az-cli inside a pod.

STORAGE_ACCOUNT="stautodevqqq"
AKS_CLUSTER="aks-autodev-qqq"
RESOURCE_GROUP="autodev-qqq"

JOB_NAME="prepare-spec"
CONFIGMAP_NAME="prepare-spec-file"

# ---------------------------------------------------------------------------
# Validate args
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <project-name> <spec-file>"
    echo "  project-name: Short name for the project (used as blob container name)"
    echo "  spec-file:    Path to the spec markdown file to upload"
    exit 1
fi

PROJECT_NAME="$1"
SPEC_FILE="$2"
CONTAINER_NAME="$PROJECT_NAME"

if [[ ! -f "$SPEC_FILE" ]]; then
    echo "Error: File not found: $SPEC_FILE"
    exit 1
fi

echo "==> Preparing spec for project: $PROJECT_NAME"
echo "    Spec file: $SPEC_FILE"
echo "    Storage:   $STORAGE_ACCOUNT/$CONTAINER_NAME/REQUIREMENTS.md"

# ---------------------------------------------------------------------------
# Connect to AKS
# ---------------------------------------------------------------------------
echo "==> Getting AKS credentials..."
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER" \
    --overwrite-existing 2>/dev/null

# ---------------------------------------------------------------------------
# Clean up any previous prepare-spec run
# ---------------------------------------------------------------------------
echo "==> Cleaning up previous prepare-spec resources..."
kubectl delete job "$JOB_NAME" --ignore-not-found 2>/dev/null || true
kubectl delete configmap "$CONFIGMAP_NAME" --ignore-not-found 2>/dev/null || true

# ---------------------------------------------------------------------------
# Create a ConfigMap from the spec file so the pod can access it
# ---------------------------------------------------------------------------
echo "==> Creating ConfigMap from spec file..."
kubectl create configmap "$CONFIGMAP_NAME" \
    --from-file="REQUIREMENTS.md=$SPEC_FILE"

# ---------------------------------------------------------------------------
# Run a one-shot Job that ensures the container exists and uploads the spec
# ---------------------------------------------------------------------------
echo "==> Running prepare-spec job..."
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB_NAME
  namespace: default
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: buildteam-sa
      restartPolicy: Never
      volumes:
        - name: spec-file
          configMap:
            name: $CONFIGMAP_NAME
      containers:
        - name: az-cli
          image: mcr.microsoft.com/azure-cli:latest
          volumeMounts:
            - name: spec-file
              mountPath: /mnt/spec
              readOnly: true
          command: ["/bin/bash", "-c"]
          args:
            - |
              set -euo pipefail

              echo "Logging in with workload identity..."
              az login --federated-token "\$(cat \$AZURE_FEDERATED_TOKEN_FILE)" \
                  --service-principal \
                  -u "\$AZURE_CLIENT_ID" \
                  -t "\$AZURE_TENANT_ID" \
                  --output none

              echo "Ensuring container '$CONTAINER_NAME' exists..."
              az storage container create \
                  --name "$CONTAINER_NAME" \
                  --account-name "$STORAGE_ACCOUNT" \
                  --auth-mode login \
                  --output none 2>/dev/null || true

              echo "Uploading REQUIREMENTS.md..."
              az storage blob upload \
                  --container-name "$CONTAINER_NAME" \
                  --account-name "$STORAGE_ACCOUNT" \
                  --file "/mnt/spec/REQUIREMENTS.md" \
                  --name "REQUIREMENTS.md" \
                  --auth-mode login \
                  --overwrite \
                  --output none

              echo "Done. Uploaded REQUIREMENTS.md to $STORAGE_ACCOUNT/$CONTAINER_NAME/"
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
EOF

# ---------------------------------------------------------------------------
# Wait for completion and show logs
# ---------------------------------------------------------------------------
echo "==> Waiting for job to complete..."
kubectl wait --for=condition=complete job/"$JOB_NAME" --timeout=120s

echo "==> Job logs:"
kubectl logs job/"$JOB_NAME"

# ---------------------------------------------------------------------------
# Clean up K8s resources
# ---------------------------------------------------------------------------
echo "==> Cleaning up..."
kubectl delete job "$JOB_NAME" --ignore-not-found 2>/dev/null || true
kubectl delete configmap "$CONFIGMAP_NAME" --ignore-not-found 2>/dev/null || true

# ---------------------------------------------------------------------------
# Print usage hint
# ---------------------------------------------------------------------------
echo ""
echo "==> Spec ready! Now launch the build:"
echo "    ./buildteam-build-on/aks/launch.sh $PROJECT_NAME"
echo ""
echo "  Or with options:"
echo "    ./buildteam-build-on/aks/launch.sh $PROJECT_NAME --model claude-opus-4.6 --builders 2"
