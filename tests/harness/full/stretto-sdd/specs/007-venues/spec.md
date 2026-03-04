# 007 — Venues

> **Depends on:** 001-scaffolding

## Summary

Venues are managed locations where events take place. Admins maintain a venue directory with contact information, preserving institutional knowledge across admin transitions.

## Data Model

### Venue Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| Name | string | Required |
| Address | string? | Optional |
| ContactName | string? | Optional |
| ContactEmail | string? | Optional |
| ContactPhone | string? | Optional |
| CreatedAt | DateTimeOffset | Set on creation |

### Fluent API Configuration

- `Venue` → `venues` table.
- Unique index on `(OrganizationId, Name)`.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/venues` | List all venues for current org | Admin, Member |
| GET | `/api/venues/{id}` | Get venue by ID | Admin, Member |
| POST | `/api/venues` | Create a venue | Admin |
| PUT | `/api/venues/{id}` | Update venue details | Admin |
| DELETE | `/api/venues/{id}` | Delete a venue (only if no events reference it) | Admin |

## Frontend

### Pages

- **Venue List** (`/venues`) — table with columns: Name, Address, Contact Name, Contact Email. "Add Venue" button for admins. Click to edit.
- **Add/Edit Venue** — modal form with Name, Address, ContactName, ContactEmail, ContactPhone fields.

## Business Rules

- Venue name must be unique within the organization — return 409 if duplicate.
- Cannot delete a venue that is referenced by any event — return 409 with a message indicating which events use it.

## Acceptance Criteria

- Admin creates a venue "First Lutheran Church" with contact info — appears in the list.
- Admin edits the venue's contact email — change persists.
- Admin attempts to delete a venue used by an event — gets an error message.
- Admin deletes an unused venue — it disappears from the list.
- Member can view venues but not create/edit/delete.
