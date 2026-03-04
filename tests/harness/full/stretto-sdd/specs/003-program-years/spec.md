# 003 — Program Years

> **Depends on:** 001-scaffolding

## Summary

Program years are organizational seasons (e.g., "2026–2027") that group projects together. Admins create, edit, archive, and designate one as the current year. The current program year is the default context when users log in.

## Data Model

### ProgramYear Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| Name | string | Required (e.g., "2026-2027") |
| IsCurrent | bool | At most one per organization |
| IsArchived | bool | Default false |
| CreatedAt | DateTimeOffset | Set on creation |

### Fluent API Configuration

- `ProgramYear` → `program_years` table.
- Unique index on `(OrganizationId, Name)`.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/program-years` | List all non-archived program years for current org. `?includeArchived=true` to include archived. | Admin, Member |
| GET | `/api/program-years/{id}` | Get program year by ID | Admin, Member |
| POST | `/api/program-years` | Create a new program year | Admin |
| PUT | `/api/program-years/{id}` | Update name | Admin |
| PATCH | `/api/program-years/{id}/set-current` | Mark as current (unmarks previous current) | Admin |
| PATCH | `/api/program-years/{id}/archive` | Archive the program year | Admin |
| PATCH | `/api/program-years/{id}/unarchive` | Unarchive | Admin |

## Frontend

### Pages

- **Program Year List** (`/program-years`) — card-based list showing each program year's name, current/archived badges. "Add Program Year" button for admins. Click to enter the program year context.
- **Add/Edit Program Year** — modal form with Name field.

### Global Context

- When a user logs in, the app loads the current program year into the Zustand store (`useAppStore.currentProgramYear`).
- A program year selector appears in the sidebar/top bar, allowing the user to switch context.
- All downstream pages (projects, auditions, utilization grid) filter by the selected program year.

## Business Rules

- Only one program year can be `IsCurrent` per organization. Setting a new current automatically unsets the previous one.
- Archived program years are hidden by default but accessible via filter. Archiving preserves all associated data.
- Cannot archive the current program year — unset current first.
- Name must be unique within the organization.

## Acceptance Criteria

- Admin creates a program year "2026-2027" and sees it in the list.
- Admin marks it as current — it appears as the default context on login.
- Admin creates a second program year and marks it current — the first is no longer current.
- Admin archives a program year — it disappears from the default list but shows with the filter.
- Program year selector in the sidebar switches the app-wide context.
