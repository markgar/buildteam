#!/usr/bin/env bash
set -euo pipefail

# prepare-spec.sh — Reset the autodev blob container and upload a spec file via AKS
#
# Usage:
#   ./deploy/aks/prepare-spec.sh <spec-file>
#
# Examples:
#   ./deploy/aks/prepare-spec.sh tests/harness/full/sample_spec_autodev.md
#   ./deploy/aks/prepare-spec.sh ~/specs/my-project.md
#
# What it does:
#   1. Connects to AKS (gets credentials if needed)
#   2. Clears all blobs in the 'autodev' container (creates it if missing)
#   3. Uploads the spec file, preserving its original filename
#   4. Prints the env vars to use in job.yaml
#
# Why AKS: The storage account (stautodevqqq) has a firewall with defaultAction=Deny.
# Only private endpoints from the VNet are allowed, so we run az-cli inside a pod.

STORAGE_ACCOUNT="stautodevqqq"
CONTAINER_NAME="autodev"
AKS_CLUSTER="aks-autodev-qqq"
RESOURCE_GROUP="autodev-qqq"

JOB_NAME="prepare-spec"
CONFIGMAP_NAME="prepare-spec-file"

# ---------------------------------------------------------------------------
# Validate args
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <spec-file>"
    echo "  spec-file: Path to the spec markdown file to upload"
    exit 1
fi

SPEC_FILE="$1"
if [[ ! -f "$SPEC_FILE" ]]; then
    echo "Error: File not found: $SPEC_FILE"
    exit 1
fi

SPEC_FILENAME=$(basename "$SPEC_FILE")
echo "==> Preparing spec: $SPEC_FILENAME"

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
echo "==> Creating ConfigMap from $SPEC_FILENAME..."
kubectl create configmap "$CONFIGMAP_NAME" \
    --from-file="$SPEC_FILENAME=$SPEC_FILE"

# ---------------------------------------------------------------------------
# Run a one-shot Job that clears the container and uploads the spec
#
# Instead of delete-container + recreate (which has a ~30s propagation delay),
# we delete all blobs and ensure the container exists. Same end result, no wait.
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

              echo "Deleting all blobs in '$CONTAINER_NAME'..."
              az storage blob delete-batch \
                  --source "$CONTAINER_NAME" \
                  --account-name "$STORAGE_ACCOUNT" \
                  --auth-mode login \
                  --output none 2>/dev/null || true

              echo "Uploading $SPEC_FILENAME..."
              az storage blob upload \
                  --container-name "$CONTAINER_NAME" \
                  --account-name "$STORAGE_ACCOUNT" \
                  --file "/mnt/spec/$SPEC_FILENAME" \
                  --name "$SPEC_FILENAME" \
                  --auth-mode login \
                  --overwrite \
                  --output none

              echo "Done. Uploaded $SPEC_FILENAME to $STORAGE_ACCOUNT/$CONTAINER_NAME/"
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
echo "==> Spec ready! Update job.yaml env vars:"
echo "      BUILDTEAM_BLOB_CONTAINER: \"$CONTAINER_NAME\""
echo "      BUILDTEAM_BLOB_SPEC: \"$SPEC_FILENAME\""
