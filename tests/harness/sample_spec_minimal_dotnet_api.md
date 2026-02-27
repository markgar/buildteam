# Minimal .NET API

A .NET 10 minimal API with a single health endpoint.

## Tech Stack

- .NET 10 minimal API (`dotnet new web`)
- No database, no authentication

## Features

- `GET /health` returns `{ "status": "healthy" }` with a 200 status code
