# Buildteam on AKS

Deploys buildteam as a Kubernetes Job with a Docker-in-Docker sidecar.

## Cluster setup (what was done)

The `autodev-dev` resource group already had these resources:
- **ACR:** `crautodevdev` (container registry for the buildteam image)
- **Key Vault:** `kv-autodev-dev` (stores `github-token` secret)
- **Managed Identity:** `id-autodev-dev` (client ID: `14d79474-03b9-43ea-aab0-6da97deb85f2`)
- **Storage Account:** `stautodevdev` (spec upload / log sync)

### 1. Registered the container service provider

```bash
az provider register --namespace Microsoft.ContainerService
```

### 2. Created the AKS cluster

```bash
az aks create \
  --resource-group autodev-dev \
  --name aks-autodev-dev \
  --node-count 1 \
  --node-vm-size Standard_D4s_v5 \
  --attach-acr crautodevdev \
  --enable-addons azure-keyvault-secrets-provider \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --generate-ssh-keys \
  --tier free
```

Key flags:
- `--attach-acr crautodevdev` — grants AcrPull so pods can pull images
- `--enable-addons azure-keyvault-secrets-provider` — CSI driver that syncs KV secrets into K8s secrets
- `--enable-oidc-issuer` + `--enable-workload-identity` — lets pods authenticate as a managed identity
- `--tier free` — no SLA, no control plane cost

### 3. Federated the managed identity to a K8s service account

```bash
OIDC_ISSUER=$(az aks show -g autodev-dev -n aks-autodev-dev --query "oidcIssuerProfile.issuerUrl" -o tsv)

az identity federated-credential create \
  --name buildteam-aks-federation \
  --identity-name id-autodev-dev \
  --resource-group autodev-dev \
  --issuer "$OIDC_ISSUER" \
  --subject "system:serviceaccount:default:buildteam-sa" \
  --audience api://AzureADTokenExchange
```

This allows pods running as the `buildteam-sa` service account to authenticate as `id-autodev-dev`.

### 4. Granted Key Vault access

```bash
KV_ID=$(az keyvault show --name kv-autodev-dev -g autodev-dev --query id -o tsv)

az role assignment create \
  --assignee "d7507c3a-7f31-4736-8936-9a85ce6d9479" \
  --role "Key Vault Secrets User" \
  --scope "$KV_ID"
```

The Key Vault uses RBAC authorization (not access policies).

### 5. Applied K8s manifests

```bash
az aks get-credentials --resource-group autodev-dev --name aks-autodev-dev
kubectl apply -f deploy/aks/namespace.yaml       # service account
kubectl apply -f deploy/aks/secret-provider.yaml  # KV → K8s secret sync
```

### Architecture decision: Docker-in-Docker sidecar

AKS nodes run containerd, not Docker — there's no Docker socket on the host. The buildteam validator agent needs Docker to build and run target project containers. The solution is a `docker:dind` sidecar in the pod that runs `dockerd` and shares its socket via an `emptyDir` volume. The buildteam container sees `/var/run/docker.sock` and works as if Docker were on the host. Only the DinD sidecar runs privileged.

## Prerequisites

- AKS cluster `aks-autodev-dev` in `autodev-dev` resource group
- ACR `crautodevdev` attached to the cluster (AcrPull)
- Key Vault `kv-autodev-dev` with `github-token` secret
- Managed identity `id-autodev-dev` with:
  - Federated credential for `system:serviceaccount:default:buildteam-sa`
  - `Key Vault Secrets User` role on the Key Vault

## Setup (one-time)

```bash
# Get kubectl credentials
az aks get-credentials --resource-group autodev-dev --name aks-autodev-dev

# Apply service account and secret provider
kubectl apply -f deploy/aks/namespace.yaml
kubectl apply -f deploy/aks/secret-provider.yaml
```

## Running a build

1. Edit `deploy/aks/job.yaml`:
   - Change the Job `name` to `buildteam-<your-project>`
   - Update `args` with your `--directory`, `--model`, and `--spec-file`/`--description`
2. If using blob storage for specs, upload your spec first:
   ```bash
   az storage blob upload --account-name stautodevdev --container-name specs \
     --name spec.md --file your-spec.md --auth-mode login
   ```
3. Apply the job:
   ```bash
   kubectl apply -f deploy/aks/job.yaml
   ```

## Monitoring

```bash
# Follow logs
kubectl logs -f job/buildteam-myproject -c buildteam

# Check DinD sidecar
kubectl logs job/buildteam-myproject -c dind

# Check pod status
kubectl get pods -l job-name=buildteam-myproject
```

## Stopping a build

```bash
kubectl delete job buildteam-myproject
```

## Cost management

```bash
# Stop the cluster when not in use (only pays for disk)
az aks stop --resource-group autodev-dev --name aks-autodev-dev

# Start it again
az aks start --resource-group autodev-dev --name aks-autodev-dev
```
