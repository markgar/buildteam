# Azure Blob Container Management API

A .NET 10 minimal API that manages blob containers in an Azure Storage account.

## Overview

The API provides CRUD operations for blob containers within an Azure Storage account. The application connects via a connection string provided as an environment variable. It does not provision infrastructure — the storage backend is external.

## Tech Stack

- .NET 10 minimal API (`dotnet new web`)
- `Azure.Storage.Blobs` NuGet package
- No authentication required on the API endpoints
- No relational database — Azure Blob Storage is the only data store

## Infrastructure Dependencies

This application requires an Azure Blob Storage-compatible service.

### Environment Variables

| Variable | Description | Required |
|---|---|---|
| `AZURE_STORAGE_CONNECTION_STRING` | Connection string for the storage backend | Yes |

If `AZURE_STORAGE_CONNECTION_STRING` is not set, the application must fail to start with a clear error message.

### Local Development & Validation (Azurite)

For development, testing, and CI validation, use **Azurite** as a drop-in Azure Storage emulator. Azurite supports the full Blob, Queue, and Table Storage APIs.

**Docker image:** `mcr.microsoft.com/azure-storage/azurite`
**Ports:** Blob service on `10000`, Queue on `10001`, Table on `10002`

In docker-compose, add Azurite as a sidecar service:
```yaml
services:
  azurite:
    image: mcr.microsoft.com/azure-storage/azurite
    ports:
      - "10000:10000"
    command: "azurite-blob --blobHost 0.0.0.0"
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "10000"]
      interval: 2s
      timeout: 3s
      retries: 5
```

Pass the Azurite connection string to the app service:
```yaml
services:
  app:
    environment:
      AZURE_STORAGE_CONNECTION_STRING: "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tiqnZwA==;BlobEndpoint=http://azurite:10000/devstoreaccount1;"
    depends_on:
      azurite:
        condition: service_healthy
```

Note: the `BlobEndpoint` uses `azurite` (the docker-compose service name) as the hostname, not `localhost` or `127.0.0.1`.

## Features

### Health

- `GET /health` — returns `{ "status": "healthy" }` with HTTP 200

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
