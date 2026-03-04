# 004 — Projects

> **Depends on:** 001-scaffolding, 003-program-years

## Summary

Projects represent individual concerts or performances within a program year. Each project has a name, date range, and description. Projects are the container for events, materials, and member assignments.

## Data Model

### Project Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| ProgramYearId | Guid | FK → ProgramYear |
| Name | string | Required |
| Description | string? | Optional |
| StartDate | DateOnly | Required |
| EndDate | DateOnly | Required, must be ≥ StartDate |
| CreatedAt | DateTimeOffset | Set on creation |

### Fluent API Configuration

- `Project` → `projects` table.
- FK to ProgramYear with cascade delete.
- Index on `(OrganizationId, ProgramYearId)`.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/program-years/{pyId}/projects` | List projects for a program year | Admin, Member |
| GET | `/api/projects/{id}` | Get project by ID | Admin, Member |
| POST | `/api/program-years/{pyId}/projects` | Create a project within a program year | Admin |
| PUT | `/api/projects/{id}` | Update project details | Admin |
| DELETE | `/api/projects/{id}` | Delete a project (cascade deletes events, assignments, materials) | Admin |

## Frontend

### Pages

- **Project List** (`/program-years/:pyId/projects`) — card grid showing each project's name, date range, description excerpt. "Add Project" button for admins.
- **Project Detail** (`/projects/:id`) — project info card at top, then tabbed sections for Events, Members, and Materials (these tabs will be populated by later specs; show empty states for now).
- **Add/Edit Project** — form with Name, Description (textarea), StartDate, EndDate (date pickers).

### Navigation

- The project list is the primary view within a program year context.
- Clicking a project navigates to its detail page.

## Business Rules

- EndDate must be ≥ StartDate — API returns 400 if violated.
- Projects are scoped to a program year. Switching program year context changes the visible project list.
- Deleting a project cascades to all associated events, assignments, and materials.

## Acceptance Criteria

- Admin creates a project "Holiday Concert" with valid date range — appears in the project list.
- Admin edits the project description — change persists.
- Admin attempts to create a project with EndDate before StartDate — gets a validation error.
- Admin deletes a project — it no longer appears.
- Member can view projects but not create/edit/delete.
- Projects are filtered by the selected program year.
