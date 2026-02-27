#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# One-time setup: OIDC workload identity federation for GitHub Actions → ACR
#
# This creates an Entra ID App Registration + Federated Credential so the
# GitHub Actions workflow can authenticate to Azure without storing secrets.
#
# Prerequisites:
#   - az CLI logged in with sufficient permissions (Contributor + User Access Admin)
#   - gh CLI logged in
#
# Usage:
#   export AZURE_SUBSCRIPTION_ID="<your-sub-id>"
#   export AZURE_TENANT_ID="<your-tenant-id>"
#   bash scripts/setup-acr-oidc.sh
# ---------------------------------------------------------------------------
set -euo pipefail

: "${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID}"
: "${AZURE_TENANT_ID:?Set AZURE_TENANT_ID}"

REPO="markgar/buildteam"
APP_NAME="github-actions-buildteam"
ACR_NAME="crautodevdev"

echo "==> Creating Entra ID App Registration: ${APP_NAME}"
APP_ID=$(az ad app create --display-name "${APP_NAME}" --query appId -o tsv)
echo "    App (client) ID: ${APP_ID}"

echo "==> Creating Service Principal"
az ad sp create --id "${APP_ID}" --query id -o tsv

echo "==> Adding federated credential for repo: ${REPO} (branch: main)"
# A single credential covers both push and workflow_dispatch from main —
# both produce the same OIDC subject (ref:refs/heads/main).
az ad app federated-credential create --id "${APP_ID}" --parameters '{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:'"${REPO}"':ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "GitHub Actions push to main and workflow_dispatch"
}'

SP_OBJECT_ID=$(az ad sp show --id "${APP_ID}" --query id -o tsv)

echo "==> Granting Reader on subscription (required for az login to discover the sub)"
az role assignment create \
  --assignee-object-id "${SP_OBJECT_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role Reader \
  --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}"

echo "==> Granting AcrPush role on ACR: ${ACR_NAME}"
ACR_ID=$(az acr show --name "${ACR_NAME}" --query id -o tsv)
az role assignment create \
  --assignee-object-id "${SP_OBJECT_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPush \
  --scope "${ACR_ID}"

echo "==> Setting GitHub repo secrets"
gh secret set AZURE_CLIENT_ID     --repo "${REPO}" --body "${APP_ID}"
gh secret set AZURE_TENANT_ID     --repo "${REPO}" --body "${AZURE_TENANT_ID}"
gh secret set AZURE_SUBSCRIPTION_ID --repo "${REPO}" --body "${AZURE_SUBSCRIPTION_ID}"

echo ""
echo "Done. Three secrets set on ${REPO}:"
echo "  AZURE_CLIENT_ID       = ${APP_ID}"
echo "  AZURE_TENANT_ID       = ${AZURE_TENANT_ID}"
echo "  AZURE_SUBSCRIPTION_ID = ${AZURE_SUBSCRIPTION_ID}"
echo ""
echo "The workflow at .github/workflows/build-push-acr.yml is ready to use."
