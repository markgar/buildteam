# Log Viewer API

A REST API that provides read access to build agent logs stored in Azure Blob Storage. Each **project** maps to a blob container, and each **run** of that project is a timestamp-prefixed folder within the container. Inside each run folder are the log files produced by the various agents (orchestrator, planner, builders, reviewers, tester, validator) — the number of which varies per run (e.g. a run may have 1 builder or 3).

Designed to run on AKS with workload identity — authenticates to the storage account using `DefaultAzureCredential`, so no connection strings or storage keys are needed.

## Storage Account

- **Account URL:** Configured via the `STORAGE_ACCOUNT_URL` environment variable (e.g. `https://stautodevqqq.blob.core.windows.net`)
- The API connects using `DefaultAzureCredential` from the `Azure.Identity` NuGet package. On AKS this resolves to the pod's workload identity. Locally it falls back to Azure CLI credentials.

## Domain Model → Blob Mapping

| Domain concept | Blob storage equivalent | Example |
|---|---|---|
| **Project** | Blob container | `autodev-opus-logs` |
| **Run** | Top-level virtual folder (timestamp prefix) | `20260302-211501/` |
| **Log** | Blob within a run prefix | `20260302-211501/builder-1.log` |
| **Prompt** | Blob in the `prompts/` sub-prefix of a run | `20260302-211501/prompts/planner-20260302-211620.txt` |
| **Artifact** | Other blobs in a run (validation results, analysis, events, metadata) | `20260302-211501/events.jsonl` |

A typical run folder looks like:

```
20260302-211501/
  orchestrator.log
  planner.log
  builder-1.log              # number of builders varies
  builder-1-spawn.log
  builder-2.log
  builder-2-spawn.log
  builder-3.log
  builder-3-spawn.log
  reviewer-1.log             # number of reviewers varies
  reviewer-2.log
  milestone-reviewer.log
  tester.log
  validator.log
  events.jsonl
  milestones.log
  run-metadata.json
  builder-1.done
  builder-2.done
  builder-3.done
  prompts/
    bootstrap-20260302-211504.txt
    builder-1-20260302-212929.txt
    planner-20260302-211620.txt
    reviewer-1-20260302-213017.txt
    ...
  validation-<milestone-name>.txt
  analysis-<milestone-name>.txt
```

The number of builder, reviewer, and spawn logs is dynamic — the API must discover them from the blobs, not assume a fixed set.

## Tech Stack

- **Language:** C# / .NET 9
- **Framework:** ASP.NET Core Minimal API
- **Authentication to Azure:** `Azure.Identity` (`DefaultAzureCredential`)
- **Storage SDK:** `Azure.Storage.Blobs`
- **Container image:** Multi-stage Dockerfile using `mcr.microsoft.com/dotnet/sdk:9.0` for build and `mcr.microsoft.com/dotnet/aspnet:9.0` for runtime

## API Endpoints

### `GET /health`
Returns `{"status": "ok"}`. Used for Kubernetes liveness/readiness probes.

---

### `GET /projects`
Lists all projects. Each blob container is a project.

Response:
```json
{
  "projects": [
    {
      "id": "autodev-opus-logs",
      "last_modified": "2026-03-02T21:15:03Z"
    },
    {
      "id": "autodev-logs",
      "last_modified": "2026-03-02T18:02:49Z"
    }
  ]
}
```

---

### `GET /projects/{projectId}/runs`
Lists all runs for a project. Discovered by listing top-level virtual folder prefixes (using `/` delimiter) in the container.

Response:
```json
{
  "project_id": "autodev-opus-logs",
  "runs": [
    {
      "id": "20260302-211501",
      "last_modified": "2026-03-03T00:03:34Z"
    }
  ]
}
```

---

### `GET /projects/{projectId}/runs/{runId}/logs`
Lists all log files in a run. Returns every blob directly under the run prefix (not in sub-folders), categorized by type. The API classifies blobs by filename pattern:

- **agent logs** — `*.log` files (e.g. `orchestrator.log`, `builder-1.log`, `tester.log`)
- **prompts** — files under the `prompts/` sub-prefix
- **artifacts** — everything else (`events.jsonl`, `run-metadata.json`, `validation-*.txt`, `analysis-*.txt`, `*.done`, etc.)

Response:
```json
{
  "project_id": "autodev-opus-logs",
  "run_id": "20260302-211501",
  "logs": [
    {
      "name": "orchestrator.log",
      "size": 18615,
      "last_modified": "2026-03-03T00:03:33Z"
    },
    {
      "name": "builder-1.log",
      "size": 137869,
      "last_modified": "2026-03-03T00:03:33Z"
    },
    {
      "name": "builder-1-spawn.log",
      "size": 190109,
      "last_modified": "2026-03-03T00:03:33Z"
    },
    {
      "name": "builder-2.log",
      "size": 108877,
      "last_modified": "2026-03-03T00:03:33Z"
    }
  ],
  "prompts": [
    {
      "name": "bootstrap-20260302-211504.txt",
      "size": 22526,
      "last_modified": "2026-03-03T00:03:33Z"
    },
    {
      "name": "builder-1-20260302-212929.txt",
      "size": 6928,
      "last_modified": "2026-03-03T00:03:33Z"
    }
  ],
  "artifacts": [
    {
      "name": "events.jsonl",
      "size": 92567,
      "last_modified": "2026-03-03T00:03:33Z"
    },
    {
      "name": "run-metadata.json",
      "size": 206,
      "last_modified": "2026-03-03T00:03:33Z"
    },
    {
      "name": "validation-project-scaffolding.txt",
      "size": 1256,
      "last_modified": "2026-03-03T00:03:33Z"
    }
  ]
}
```

---

### `GET /projects/{projectId}/runs/{runId}/logs/{fileName}`
Retrieves the content of a specific log file (or prompt or artifact) within a run. The `fileName` is the blob name relative to the run prefix — e.g. `builder-1.log` or `prompts/planner-20260302-211620.txt`.

Query parameters:
- `raw` (boolean, default false) — when true, returns the raw file content with its original content type. When false (default), returns a JSON envelope.
- `offset` (long, default 0) — byte offset to start reading from. When provided, only content from that byte position onward is returned. This enables a **follow** pattern: read the log, note the returned `offset`, then poll again with that offset to get only new content appended since the last read. The API uses Azure Blob Storage range reads, so only the new bytes are fetched — no need to re-download the entire blob.

Response (raw=false, default, no offset):
```json
{
  "project_id": "autodev-opus-logs",
  "run_id": "20260302-211501",
  "name": "orchestrator.log",
  "size": 18615,
  "offset": 18615,
  "last_modified": "2026-03-03T00:03:33Z",
  "content": "Migrated builder/ to builder-1/\nMigrated reviewer/ to reviewer-1/\n..."
}
```

Response (with offset — e.g. `?offset=18615` when nothing new has been appended):
```json
{
  "project_id": "autodev-opus-logs",
  "run_id": "20260302-211501",
  "name": "orchestrator.log",
  "size": 18615,
  "offset": 18615,
  "last_modified": "2026-03-03T00:03:33Z",
  "content": ""
}
```

The `offset` in the response is always the byte position immediately after the last byte returned — i.e. the value the caller should pass on the next request. When `offset` equals `size`, there is no new content. When the blob has grown (e.g. a log still being written to), `offset` will be greater than the input offset and `content` will contain only the new bytes.

Response (raw=true):
Returns the file content directly with appropriate `Content-Type` header. When `offset` is provided, returns only bytes from that position onward and sets `Content-Range` header (e.g. `bytes 18615-25000/25001`).

---

### `GET /projects/{projectId}/runs/{runId}/logs/{fileName}/tail`
Returns the last N lines of a log file. Useful for tailing large spawn logs without downloading the entire blob.

Query parameters:
- `lines` (int, default 100) — number of lines to return from the end

Response:
```json
{
  "project_id": "autodev-opus-logs",
  "run_id": "20260302-211501",
  "name": "builder-1-spawn.log",
  "total_size": 190109,
  "lines_returned": 100,
  "content": "... last 100 lines ..."
}
```

## OpenAPI / Swagger

- Expose an OpenAPI 3.0 document at `GET /openapi/v1.json`
- Serve Swagger UI at `GET /swagger` (redirects to `/swagger/index.html`)
- Use .NET 9's built-in `Microsoft.AspNetCore.OpenApi` support (`AddOpenApi()` / `MapOpenApi()`) — no Swashbuckle needed
- All endpoints, parameters, and response schemas must be represented in the generated OpenAPI document

## Error Handling

- 404 with `{"error": "Project not found"}` when the container doesn't exist
- 404 with `{"error": "Run not found"}` when no blobs exist with the given run prefix
- 404 with `{"error": "Log not found"}` when the blob doesn't exist
- 500 with `{"error": "Storage account unavailable: <detail>"}` when Azure SDK calls fail
- All errors use a consistent `{"error": "<message>"}` JSON envelope

## Configuration

All configuration via environment variables:

| Variable | Required | Default | Description |
|---|---|---|---|
| `STORAGE_ACCOUNT_URL` | Yes | — | Full URL to the storage account (e.g. `https://stautodevqqq.blob.core.windows.net`) |
| `ASPNETCORE_URLS` | No | `http://+:8080` | URL(s) the server listens on |
| `Logging__LogLevel__Default` | No | `Information` | .NET log level |

## Deployment

- Runs as a Kubernetes Deployment with a Service on port 80 targeting the container's port 8080
- Uses the `buildteam-sa` service account (which has workload identity annotation for `DefaultAzureCredential`)
- Pod label `azure.workload.identity/use: "true"` must be set
- Liveness and readiness probes point at `/health`
- Single replica is sufficient — this is a read-only stateless API

## Non-Goals

- No authentication/authorization on the API itself (it runs cluster-internal only)
- No write operations — this API is strictly read-only
- No log parsing, search, or aggregation — it serves raw blob content
- No caching — blobs are fetched directly from storage on each request
- No UI — this is a pure REST API (a separate frontend can be built later)
