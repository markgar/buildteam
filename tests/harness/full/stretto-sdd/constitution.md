# Stretto — Constitution

This document defines the immutable cross-cutting rules that apply to **every feature spec** in this project. Feature specs inherit everything here — they should not repeat or contradict these rules.

## What is Stretto?

A multi-tenant management platform for arts organizations. Organizations manage members, projects, program years, auditions, events, and attendance. Runs as SaaS with per-organization data isolation.

## Multi-Tenancy

- Every entity carries an `OrganizationId` foreign key.
- All queries are automatically scoped to the current user's organization.
- Organizations are created via seed data (no SaaS admin UI yet).

## Roles

- **Admin** — full access to manage all entities within their organization.
- **Member** — view-only access to their assignments, projects, events, and materials.

## Authentication (Phase 1)

- Passwordless email-only login (no verification code yet — drop-in enhancement later).
- Member enters email → logged in immediately → persistent trusted-browser cookie set.
- Cookie: `HttpOnly`, `Secure`, `SameSite=Strict`, references a server-side session/token.
- Backend exposes a `/auth/validate` endpoint to check cookie on page load, returning user context (organization, role).
- Login verifies the email belongs to an existing member (or creates one in the audition sign-up flow).

> **Phase 2 note:** Phase 2 adds email verification codes — the login flow structure stays the same, only a verification step is inserted between email submission and session creation. Build Phase 1 structures to accommodate this (e.g., keep the login flow as discrete steps, not a single monolithic handler).

## Authorization

- Role checks enforced via ASP.NET Core policy-based authorization (`[Authorize(Policy = "AdminOnly")]`).
- Define policies in `Program.cs`: `AdminOnly` requires `Role == Admin`; `Authenticated` requires any valid session.
- Controllers apply `[Authorize(Policy = "Authenticated")]` at the class level. Actions that require Admin add `[Authorize(Policy = "AdminOnly")]`.
- Public endpoints (e.g., audition sign-up) use `[AllowAnonymous]` to bypass authentication entirely.
- Token-based endpoints (e.g., iCal calendar subscriptions) validate a per-entity token from the query string — these also use `[AllowAnonymous]` with custom token validation in the action.
- **Resource-level authorization**: Some endpoints restrict access to members assigned to a specific resource (e.g., only members assigned to a project can view its materials). These use a custom `IAuthorizationHandler` that checks the assignment table. Admins always bypass resource-level checks.
- Frontend hides UI controls based on role from the auth store — but the backend is always the enforcement boundary.

> **Auth column mapping in feature specs:** `Admin` = `AdminOnly` policy. `Admin, Member` = `Authenticated` policy. `Admin, Member (assigned)` = `Authenticated` + resource-level assignment check. `Public` = `[AllowAnonymous]`.

## Tech Stack

### Backend

- **.NET 10** with nullable reference types enabled.
- **ASP.NET Core Web API** exposing RESTful endpoints with **OpenAPI/Swagger** spec.
- **Entity Framework Core** with **in-memory database** (swappable to SQL Server/PostgreSQL later).
- **Fluent API** for all entity mappings — no data annotations, no convention-based configuration.
- Enforce formatting with `dotnet format` (config checked in).

### Frontend

- **React** with **TypeScript** (strict mode) and **Vite**.
- **React Router** for client-side routing.
- **shadcn/ui** as the component library (initialized via `npx shadcn@latest init`, components added as needed).
- **Tailwind CSS** for all styling — utility classes only, no separate CSS files, mobile-first responsive prefixes.
- **React Hook Form** + **Zod** for all forms (via shadcn `<Form>` / `<FormField>`).
- **Tanstack Query** for all API data fetching/mutations — no raw `useEffect` + `fetch`.
- **Tanstack Table** for all data tables and grids (via shadcn `<DataTable>`).
- **Zustand** for global state (auth context, current organization, current program year).
- **date-fns** for all date/time operations.
- **Lucide React** for all icons.
- Semantic HTML elements and `data-testid` attributes on all interactive elements.

### API Contract

- Backend OpenAPI spec is the source of truth.
- Auto-generated TypeScript client using `openapi-typescript-codegen` checked into the repo.
- Frontend imports from the generated client — no manual API wiring.

## API Conventions

- Success responses return the resource directly (no envelope).
- List endpoints return `{ "items": [...], "total": <int> }` with `?page=` and `?pageSize=` query params (default 25, max 100). **All list endpoints inherit this pagination pattern by default.** Feature specs that omit pagination params get the constitutional defaults. Specs may explicitly opt out for small, bounded data sets.
- Error responses: `{ "error": "<short_code>", "message": "<human-readable>" }`.
- Standard status codes: 200 (success), 201 (created), 400 (validation), 401 (no auth), 403 (wrong role/resource), 404 (not found), 409 (conflict), 413 (payload too large), 500 (unexpected).

## Error Handling

- Domain/Application layers throw typed exceptions: `NotFoundException`, `ConflictException`, `ValidationException`, `ForbiddenException`.
- API layer has global exception-handling middleware that maps each exception type to the standard error response and correct HTTP status code.
- Never return 500 for predictable business errors.
- Infrastructure errors (database, external services) are caught, logged, and returned as 500 with a generic message — never leak internals.

## Architecture

Clean architecture with four layers:

| Project | Layer | Depends On |
|---|---|---|
| `Stretto.Domain` | Domain — entities, value objects, business rules | Nothing |
| `Stretto.Application` | Application — use cases, interfaces, DTOs | Domain |
| `Stretto.Infrastructure` | Infrastructure — EF Core, external services | Application |
| `Stretto.Api` | API — thin controllers, OpenAPI | Application |
| `Stretto.Web` | Frontend — React/TypeScript SPA | Generated API client |

## UI & Design System

### Color & Theme

- Neutral base (white/light gray backgrounds, dark gray text).
- Brand accent: indigo (`indigo-600`) for primary actions, active nav, links.
- Semantic status colors: green = success/active/present, amber = warning/pending, red = error/absent/rejected, gray = archived/inactive.
- Status badges use subtle tints (e.g., `bg-green-100 text-green-800`), not solid blocks.

### Layout

- **Desktop (≥1024px)**: Fixed left sidebar (240px) + content area. Sidebar: org name top, nav middle, user/role bottom. Content max-width `max-w-7xl` centered.
- **Tablet (768–1023px)**: Collapsible sidebar — icons by default, expands on hover/tap.
- **Mobile (<768px)**: No sidebar. Bottom tab bar (4–5 tabs). Top bar with page title and org name.

### Component Patterns

- **Cards** as primary content containers (white, subtle border/shadow, rounded).
- **Tables**: striped, hover highlight, pagination. Mobile: card-per-row layout.
- **Forms**: labels above inputs, full-width, inline validation (red), grouped related fields.
- **Buttons**: primary (accent, solid), secondary (outlined), destructive (red). 44×44px min tap target on mobile.
- **Modals**: one task per modal, no scrolling if avoidable.
- **Empty states**: icon + message + CTA button on every list view.
- **Loading states**: skeleton loaders (pulsing placeholders), never blank pages.
- **Error states**: inline error banner with retry button, not full-page errors.
- **Toast notifications**: bottom-right desktop, top mobile. Brief action confirmations.

### Typography & Spacing

- Tailwind default font stack (system fonts). No custom web fonts.
- Page titles: `text-2xl font-bold`. Section headings: `text-lg font-semibold`. Card titles: `text-base font-medium`.
- Consistent spacing: `p-4`/`p-6` card padding, `gap-4`/`gap-6` grid gaps, `space-y-4` stacks.

## Seed Data

Every environment starts with:

- Organization: **"My Choir"**
- Admin: `admin@stretto-demo.example` (belongs to "My Choir")
- Member: `member@stretto-demo.example` (belongs to "My Choir")

## Testing Strategy

- Domain and Application layers: unit tested independently of Infrastructure.
- API: integration tests with test database.
- Frontend pages: Playwright tests using `data-testid` selectors.
- Frontend components: React Testing Library unit tests.
- All tests runnable from CLI: `dotnet test`, `npm test`, `npx playwright test`.

## Feature Folder Structure

### Backend (per feature)

- `Stretto.Domain/Entities/{Feature}.cs` — entity and related value objects.
- `Stretto.Application/Features/{Feature}/I{Feature}Repository.cs` — repository interface.
- `Stretto.Application/Features/{Feature}/{Feature}Dto.cs` — DTOs and mapping.
- `Stretto.Application/Features/{Feature}/{Feature}Exceptions.cs` — typed exceptions (if feature-specific).
- `Stretto.Infrastructure/Repositories/{Feature}Repository.cs` — EF Core implementation.
- `Stretto.Api/Controllers/{Feature}Controller.cs` — thin controller.

### Frontend (per feature)

- `src/features/{feature}/pages/` — page components (one per route).
- `src/features/{feature}/components/` — feature-specific UI components.
- `src/features/{feature}/hooks/` — Tanstack Query hooks (`useMembers`, `useCreateMember`, etc.).
- `src/features/{feature}/types.ts` — feature-specific TypeScript types.

### Shared

- `src/components/` — shared layout and UI components (sidebar, data table, form fields).
- `src/lib/` — API client, auth store, utility functions.

## Navigation Structure

### Admin Navigation

- **Dashboard** (`/`) — Overview of the current program year: upcoming events, recent activity, quick stats.
- **Program Years** (`/program-years`) — List/create/archive program years; drill into a year to see its projects.
- **Projects** (`/program-years/:pyId/projects`) — List/create projects within a program year; drill into a project for events, materials, and member assignments.
- **Utilization Grid** (`/program-years/:pyId/utilization`) — The matrix view for the selected program year.
- **Members** (`/members`) — Browse/search all members; view profiles and assignments; manually add, edit, or deactivate members.
- **Auditions** (`/program-years/:pyId/auditions`) — Set up audition dates and slots for a program year; view sign-ups; take notes and set statuses.
- **Venues** (`/venues`) — Manage the list of venues and their contact information.
- **Notifications** (`/notifications`) — View notification history; send announcements.

### Member Navigation

- **My Calendar** (`/`) — Personal calendar of all upcoming rehearsals and performances, with iCal export. This is the member's default landing page.
- **My Projects** (`/my-projects`) — List of projects the member is assigned to; drill in to see events and materials.
- **Auditions** (`/auditions/:id/signup`) — Browse open audition slots and sign up (also serves as the registration entry point for new members).
- **Profile** (`/profile`) — View/edit name, email; manage notification preferences.

### Shared

- The sidebar/top bar shows the organization name and the user's role.
- Admin sees the full admin nav; Member sees the simplified member nav.
- Each event has a unique URL to support QR-code-based check-in (`/checkin/:eventId`).

## AI Agent Maintainability

- Follow the feature folder structure above for every feature — no exceptions.
- Files under ~200 lines. One component/class/module per file.
- TypeScript strict mode (no `any`). C# nullable reference types.
- Explicit registration, imports, and configuration — no auto-discovery or magic strings.
- ESLint + Prettier (frontend), `dotnet format` (backend) — configs checked in.
- Self-documenting names. Comments only where intent is non-obvious.
- Simple build/run/test commands documented in README.
