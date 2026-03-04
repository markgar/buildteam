# Minimal .NET Cosmos DB API

A .NET 10 minimal API that connects to an existing Azure Cosmos DB account, database, and container to prove the connection works.

## Tech Stack

- .NET 10 minimal API (`dotnet new web`)
- `Microsoft.Azure.Cosmos` NuGet package
- `Azure.Identity` NuGet package (for `DefaultAzureCredential`)
- No authentication required on the API endpoints

## Infrastructure Dependencies

The Cosmos DB account, database, and container already exist. The application does not create or provision any infrastructure — it only reads from what is already there.

### Environment Variables

| Variable | Description | Example |
|---|---|---|
| `AZURE_COSMOS_ENDPOINT` | Cosmos DB account endpoint URL | `https://myaccount.documents.azure.com:443/` |
| `AZURE_COSMOS_DATABASE` | Name of the existing database | `mydb` |
| `AZURE_COSMOS_CONTAINER` | Name of the existing container | `mycontainer` |

All three are required. The app must fail to start with a clear error message if any is missing.

### Authentication

Use `DefaultAzureCredential` from `Azure.Identity` to authenticate to Cosmos DB. Do **not** use connection strings or account keys.

```csharp
new CosmosClient(endpoint, new DefaultAzureCredential())
```

This works transparently in both environments:
- **Local development** — picks up credentials from `az login`
- **AKS / Azure** — picks up Managed Identity or Workload Identity automatically

## Features

### Health

- `GET /health` — checks that the Cosmos DB connection is live by calling `CosmosClient.ReadAccountAsync()`
  - Healthy (HTTP 200):
    ```json
    { "status": "healthy", "checks": { "cosmosdb": "connected" } }
    ```
  - Unhealthy (HTTP 503):
    ```json
    { "status": "unhealthy", "checks": { "cosmosdb": "connection refused" } }
    ```

### Ping

- `GET /ping` — reads the container metadata via `Container.ReadContainerAsync()` to prove the full account → database → container path works. Does not require any documents to exist.
  - Success (HTTP 200):
    ```json
    { "database": "mydb", "container": "mycontainer", "partitionKeyPath": "/id" }
    ```
    The `partitionKeyPath` value comes from the `ContainerProperties` returned by the SDK.
  - Failure (HTTP 503):
    ```json
    { "error": "failed to read container: <exception message>" }
    ```
