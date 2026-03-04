# 001 — Project Scaffolding & Auth

> **Depends on:** (none — this is the foundation)

## Summary

Set up the solution structure, both backend and frontend projects, seed data, constitutional infrastructure (authorization policies, error handling middleware, pagination helpers), and the Phase 1 passwordless authentication flow. After this spec, the app builds, starts, a user can log in, and all cross-cutting backend infrastructure is in place for subsequent feature specs.

## Backend

### Solution Structure

Create the .NET solution with five projects matching the clean architecture layers defined in the constitution:

- `Stretto.Domain` — Organization and Member entities, Role enum (Admin, Member).
- `Stretto.Application` — `IOrganizationRepository`, `IMemberRepository` interfaces. `AuthService` (find member by email, create session token). DTOs for auth responses. Shared `PagedResult<T>` class. Base exception types: `NotFoundException`, `ConflictException`, `ValidationException`, `ForbiddenException`.
- `Stretto.Infrastructure` — EF Core DbContext with in-memory provider. Fluent API entity configurations. Repository implementations. Seed data (see constitution).
- `Stretto.Api` — Program.cs with DI wiring, CORS for frontend, Swagger/OpenAPI, authorization policies, global exception-handling middleware. Auth controller.

### Constitutional Infrastructure

These cross-cutting pieces are established here so every subsequent feature spec inherits them:

- **Authorization policies** — Register `AdminOnly` and `Authenticated` policies in `Program.cs` per constitution. Wire up cookie-based authentication scheme that reads the session token.
- **Global exception-handling middleware** — Catches `NotFoundException` → 404, `ConflictException` → 409, `ValidationException` → 400, `ForbiddenException` → 403. Returns the constitutional error response format `{ "error": "<short_code>", "message": "<human-readable>" }`. Unhandled exceptions → 500 with generic message.
- **`PagedResult<T>`** — Shared class in Application layer: `{ Items: List<T>, Total: int }`. All list endpoints will use this as their return type.
- **Pagination query helpers** — `PageRequest` record with `Page` (default 1) and `PageSize` (default 25, max 100). Repository methods accept `PageRequest` and return `PagedResult<T>`.

### API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| POST | `/api/auth/login` | Accept `{ email }`, find or reject member, set auth cookie, return user context | Public |
| GET | `/api/auth/me` | Validate cookie, return current user (id, name, email, role, organizationId) | Authenticated |
| POST | `/api/auth/logout` | Clear auth cookie | Authenticated |

### Auth Cookie Implementation

- Session stored in-memory (dictionary keyed by token) — swappable to Redis/DB later.
- Cookie settings per constitution (HttpOnly, Secure, SameSite=Strict, references server-side session token).
- Login flow structured as discrete steps (find member → create session → set cookie) to accommodate Phase 2 verification code insertion.

## Frontend

### Project Setup

- Initialize React + TypeScript + Vite project as `Stretto.Web`.
- Install and configure: shadcn/ui, Tailwind CSS, React Router, Zustand, Tanstack Query, ESLint + Prettier.
- Set up the generated API client from the backend OpenAPI spec using `openapi-typescript-codegen`.
- Create the responsive layout shell per constitution: sidebar with nav links (desktop), collapsible sidebar (tablet), bottom tab bar (mobile). Wire the navigation structure from the constitution — admin sees full nav, member sees simplified nav.

### Pages

- **Login page** (`/login`) — email input, submit button. On success, redirect to dashboard.
- **Dashboard** (`/`) — placeholder page showing "Welcome, {name}" and the organization name. Protected route — redirects to `/login` if no auth cookie. (Full dashboard with upcoming events and stats will be built in spec 013.)

### Auth State

- Zustand store: `useAuthStore` with `user`, `login()`, `logout()`, `checkAuth()`.
- On app load, call `GET /api/auth/me`. If valid, populate store. If 401, redirect to login.
- Role is available in the store for conditional nav rendering.

## Acceptance Criteria

- `dotnet build` succeeds. `npm run build` succeeds.
- Visiting `/` without auth redirects to `/login`.
- Logging in with `admin@stretto-demo.example` shows the dashboard with "My Choir" and full admin navigation.
- Logging in with `member@stretto-demo.example` shows the dashboard with member navigation.
- Logging in with an unknown email shows an error in the constitutional error response format.
- `GET /api/auth/me` returns 401 without a cookie, 200 with a valid cookie.
- Error middleware returns `{ "error": "not_found", "message": "..." }` for 404s (test with `GET /api/nonexistent`).
- Swagger UI is accessible at `/swagger`.
