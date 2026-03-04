# 005 — Member Assignment

> **Depends on:** 002-members, 004-projects

## Summary

Admins assign and unassign members to projects. The assignment UI lets admins browse or search the full member list and toggle assignments per project. Members can see which projects they're assigned to.

## Data Model

### ProjectAssignment Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| ProjectId | Guid | FK → Project |
| MemberId | Guid | FK → Member |
| AssignedAt | DateTimeOffset | Set on assignment |

### Fluent API Configuration

- `ProjectAssignment` → `project_assignments` table.
- Unique index on `(ProjectId, MemberId)` — no duplicate assignments.
- FK to Project and Member, both cascade delete.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/projects/{id}/members` | List members assigned to a project | Admin, Member |
| GET | `/api/members/{id}/projects` | List projects a member is assigned to | Admin, Member |
| PUT | `/api/projects/{id}/members` | Bulk update assignments — accept `{ memberIds: [] }`, set exactly these members. Returns the updated list of assigned members. | Admin |
| POST | `/api/projects/{id}/members/{memberId}` | Assign a single member | Admin |
| DELETE | `/api/projects/{id}/members/{memberId}` | Unassign a single member | Admin |

## Frontend

### Assignment Modal

- On the project detail page, admins click "Manage Members" to open an assignment modal.
- Modal shows a searchable, scrollable list of all active members.
- Each member row has a checkbox — checked = assigned, unchecked = not assigned.
- Search filters by name/email in real-time.
- "Save" commits the changes via the bulk PUT endpoint.

### Project Detail — Members Tab

- Show a table of assigned members (Name, Email, Role).
- Members see this as read-only. Admins see the "Manage Members" button.

### Member Detail — Projects Section

- On the member detail page, show a list of projects the member is assigned to (linking to each project).

## Business Rules

- Only active members can be assigned. Deactivated members are excluded from the assignment list.
- Assigning a member who is already assigned is idempotent (no error, no duplicate).
- Unassigning a member who isn't assigned returns 204 (idempotent).
- When a member is deactivated (spec 002), existing assignments are preserved (for historical records) but the member won't appear in future assignment UIs.

## Acceptance Criteria

- Admin assigns 3 members to a project — all 3 appear in the project's member list.
- Admin unassigns 1 member — only 2 remain.
- Member views their assigned projects on their profile.
- Search in the assignment modal filters the member list.
- Deactivated members don't appear in the assignment modal.
