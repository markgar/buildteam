# Azure Cosmos DB Database Management API

A .NET 10 minimal API that manages databases and containers in an Azure Cosmos DB account.

## Overview

The API provides CRUD operations for databases and containers within an Azure Cosmos DB account (NoSQL API). The application connects via a connection string or account endpoint provided as an environment variable. It does not provision infrastructure — the Cosmos DB backend is external.

## Tech Stack

- .NET 10 minimal API (`dotnet new web`)
- `Microsoft.Azure.Cosmos` NuGet package
- `Azure.Identity` NuGet package (for `DefaultAzureCredential`)
- No authentication required on the API endpoints
- No relational database — Azure Cosmos DB is the only data store

## Infrastructure Dependencies

This application requires an Azure Cosmos DB-compatible service (NoSQL API).

### Environment Variables

| Variable | Description | When to use |
|---|---|---|
| `AZURE_COSMOS_ENDPOINT` | Cosmos DB account endpoint, e.g. `https://myaccount.documents.azure.com:443/` | Production (Managed Identity) |
| `AZURE_COSMOS_CONNECTION_STRING` | Connection string for the Cosmos DB account | Local dev / Emulator |

At least one must be set. If both are set, `AZURE_COSMOS_ENDPOINT` takes precedence.

### Cosmos Client Initialization

The app selects its authentication strategy at startup based on which environment variable is present:

- **`AZURE_COSMOS_ENDPOINT` is set** — use `new CosmosClient(endpoint, new DefaultAzureCredential())`. In Azure, this picks up Managed Identity automatically. Locally, it uses `az login` credentials.
- **`AZURE_COSMOS_CONNECTION_STRING` is set** — use `new CosmosClient(connectionString)`. This is the path used with the Cosmos DB Emulator.
- **Neither is set** — fail to start with a clear error message.

No environment detection logic — the deployer controls behavior through configuration.

### Local Development & Validation (Cosmos DB Emulator)

For development, testing, and CI validation, use the **Azure Cosmos DB Linux Emulator** as a drop-in Cosmos DB emulator. The Linux emulator supports the NoSQL API.

**Docker image:** `mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest`
**Default ports:** HTTPS `8081`, Direct mode `10250-10255`

**Well-known emulator connection string:**
```
AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==
```

Set `AZURE_COSMOS_CONNECTION_STRING` to this value when running against the emulator. Adjust the `AccountEndpoint` hostname if the emulator is running on a different host (e.g. a docker-compose service name like `https://cosmosdb:8081/`).

**Important emulator notes:**
- The emulator uses a self-signed SSL certificate. The application must set `CosmosClientOptions.HttpClientFactory` to use an `HttpClient` that ignores certificate errors when `AZURE_COSMOS_CONNECTION_STRING` contains `localhost` or the well-known emulator account key.
- Alternatively, set `CosmosClientOptions.ConnectionMode = ConnectionMode.Gateway` for emulator compatibility.

## Features

### Health

- `GET /health` — actively checks all external dependencies and returns per-check status
  - Response when all dependencies are reachable (HTTP 200):
    ```json
    { "status": "healthy", "checks": { "cosmosdb": "connected" } }
    ```
  - Response when any dependency is unreachable (HTTP 503):
    ```json
    { "status": "unhealthy", "checks": { "cosmosdb": "connection refused" } }
    ```
  - The `checks` object must include an entry for every configured external dependency. As new dependencies are added, they must appear here.
  - The health check should attempt a lightweight operation (e.g. `CosmosClient.ReadAccountAsync()`) — not just verify the connection string is non-empty.

### Database Management

- `POST /databases` — create a new database
- `GET /databases` — list all databases
- `GET /databases/{name}` — get details for a single database
- `DELETE /databases/{name}` — delete a database

### Container Management

- `POST /databases/{databaseName}/containers` — create a new container in a database
- `GET /databases/{databaseName}/containers` — list all containers in a database
- `GET /databases/{databaseName}/containers/{containerName}` — get details for a single container
- `DELETE /databases/{databaseName}/containers/{containerName}` — delete a container

## Endpoints

### POST /databases
Request body:
```json
{ "name": "my-database" }
```
Response (201 Created):
```json
{ "name": "my-database", "selfLink": "<self-link-from-sdk>" }
```
The `selfLink` value must come from the SDK (`DatabaseProperties.SelfLink`), not be constructed manually.
Errors:
- 400 if name is missing or empty
- 409 if a database with that name already exists

### GET /databases
Response (200 OK):
```json
[
  { "name": "my-database", "selfLink": "<self-link-from-sdk>" }
]
```
Returns an empty array if no databases exist.

### GET /databases/{name}
Response (200 OK):
```json
{ "name": "my-database", "selfLink": "<self-link-from-sdk>" }
```
Errors:
- 404 if the database does not exist

### DELETE /databases/{name}
Response (204 No Content)

Errors:
- 404 if the database does not exist

### POST /databases/{databaseName}/containers
Request body:
```json
{ "name": "my-container", "partitionKeyPath": "/id" }
```
Response (201 Created):
```json
{
  "name": "my-container",
  "partitionKeyPath": "/id",
  "selfLink": "<self-link-from-sdk>"
}
```
The `selfLink` value must come from the SDK (`ContainerProperties.SelfLink`), not be constructed manually.
Errors:
- 400 if name is missing or empty
- 400 if partitionKeyPath is missing, empty, or does not start with `/`
- 404 if the parent database does not exist
- 409 if a container with that name already exists in the database

### GET /databases/{databaseName}/containers
Response (200 OK):
```json
[
  {
    "name": "my-container",
    "partitionKeyPath": "/id",
    "selfLink": "<self-link-from-sdk>"
  }
]
```
Returns an empty array if no containers exist. Returns 404 if the parent database does not exist.

### GET /databases/{databaseName}/containers/{containerName}
Response (200 OK):
```json
{
  "name": "my-container",
  "partitionKeyPath": "/id",
  "selfLink": "<self-link-from-sdk>"
}
```
Errors:
- 404 if the database or container does not exist

### DELETE /databases/{databaseName}/containers/{containerName}
Response (204 No Content)

Errors:
- 404 if the database or container does not exist

## Validation Rules

Database and container names must follow Cosmos DB naming rules:
- 1 to 256 characters
- Cannot contain `\`, `/`, `#`, `?`, or trailing spaces

Partition key paths must:
- Start with `/`
- Contain only alphanumeric characters, underscores, and `/` separators
- Not be empty

The API must validate names and partition key paths before calling Azure and return 400 with a descriptive message if invalid.

## Error Response Shape

All error responses use a consistent envelope:
```json
{ "error": "Descriptive message here" }
```

## Constraints

- Database and container operations must propagate real Cosmos DB error details in the `error` field when the SDK throws
- The app must start and serve `/health` within 5 seconds
- No in-memory cache or state — every request reads from / writes to the Cosmos DB account directly
