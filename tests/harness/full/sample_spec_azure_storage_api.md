# Azure Blob Container Management API

A .NET 10 minimal API that manages blob containers in an Azure Storage account.

## Overview

The API provides CRUD operations for blob containers within an Azure Storage account. The application connects via a connection string provided as an environment variable. It does not provision infrastructure — the storage backend is external.

## Tech Stack

- .NET 10 minimal API (`dotnet new web`)
- `Azure.Storage.Blobs` NuGet package
- `Azure.Identity` NuGet package (for `DefaultAzureCredential`)
- No authentication required on the API endpoints
- No relational database — Azure Blob Storage is the only data store

## Infrastructure Dependencies

This application requires an Azure Blob Storage-compatible service.

### Environment Variables

| Variable | Description | When to use |
|---|---|---|
| `AZURE_STORAGE_ACCOUNT_URL` | Storage account URL, e.g. `https://myaccount.blob.core.windows.net` | Production (Managed Identity) |
| `AZURE_STORAGE_CONNECTION_STRING` | Connection string for the storage backend | Local dev / Azurite |

At least one must be set. If both are set, `AZURE_STORAGE_ACCOUNT_URL` takes precedence.

### Storage Client Initialization

The app selects its authentication strategy at startup based on which environment variable is present:

- **`AZURE_STORAGE_ACCOUNT_URL` is set** — use `new BlobServiceClient(new Uri(url), new DefaultAzureCredential())`. In Azure, this picks up Managed Identity automatically. Locally, it uses `az login` credentials.
- **`AZURE_STORAGE_CONNECTION_STRING` is set** — use `new BlobServiceClient(connectionString)`. This is the path used with Azurite.
- **Neither is set** — fail to start with a clear error message.

No environment detection logic — the deployer controls behavior through configuration.

### Local Development & Validation (Azurite)

For development, testing, and CI validation, use **Azurite** as a drop-in Azure Storage emulator. Azurite supports the full Blob, Queue, and Table Storage APIs.

**Docker image:** `mcr.microsoft.com/azure-storage/azurite`
**npm package:** `azurite` (can also be installed via `npm install -g azurite`)
**Default ports:** Blob `10000`, Queue `10001`, Table `10002`

**Well-known Azurite connection string:**
```
DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tiqnZwA==;BlobEndpoint=http://localhost:10000/devstoreaccount1;
```

Set `AZURE_STORAGE_CONNECTION_STRING` to this value when running against Azurite. Adjust the `BlobEndpoint` hostname if Azurite is running on a different host (e.g. a docker-compose service name).

## Features

### Health

- `GET /health` — actively checks all external dependencies and returns per-check status
  - Response when all dependencies are reachable (HTTP 200):
    ```json
    { "status": "healthy", "checks": { "storage": "connected" } }
    ```
  - Response when any dependency is unreachable (HTTP 503):
    ```json
    { "status": "unhealthy", "checks": { "storage": "connection refused" } }
    ```
  - The `checks` object must include an entry for every configured external dependency. As new dependencies are added (e.g. Cosmos DB, Redis), they must appear here.
  - The health check should attempt a lightweight operation (e.g. `BlobServiceClient.GetProperties()`) — not just verify the connection string is non-empty.

### Container Management

- `POST /containers` — create a new blob container
- `GET /containers` — list all blob containers
- `GET /containers/{name}` — get details for a single container
- `DELETE /containers/{name}` — delete a container

## Endpoints

### POST /containers
Request body:
```json
{ "name": "my-container" }
```
Response (201 Created):
```json
{ "name": "my-container", "url": "<container-uri-from-sdk>" }
```
The `url` value must come from the SDK (`BlobContainerClient.Uri`), not be constructed manually. It will vary by backend (e.g., `https://myaccount.blob.core.windows.net/my-container` on Azure, `http://azurite:10000/devstoreaccount1/my-container` on Azurite).
Errors:
- 400 if name is missing, empty, or fails Azure naming rules (lowercase letters, numbers, hyphens; 3–63 characters)
- 409 if a container with that name already exists

### GET /containers
Response (200 OK):
```json
[
  { "name": "my-container", "url": "<container-uri-from-sdk>" }
]
```
Returns an empty array if no containers exist.

### GET /containers/{name}
Response (200 OK):
```json
{ "name": "my-container", "url": "<container-uri-from-sdk>" }
```
Errors:
- 404 if the container does not exist

### DELETE /containers/{name}
Response (204 No Content)

Errors:
- 404 if the container does not exist

## Validation Rules

Container names must follow Azure Blob Storage naming rules:
- 3 to 63 characters
- Lowercase letters, numbers, and hyphens only
- Must start with a letter or number
- No consecutive hyphens

The API must validate names before calling Azure and return 400 with a descriptive message if invalid.

## Error Response Shape

All error responses use a consistent envelope:
```json
{ "error": "Descriptive message here" }
```

## Constraints

- Container operations must propagate real Azure error details in the `error` field when the SDK throws
- The app must start and serve `/health` within 5 seconds
- No in-memory cache or state — every request reads from / writes to the storage account directly
