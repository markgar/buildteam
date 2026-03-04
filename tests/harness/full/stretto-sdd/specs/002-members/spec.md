# 002 — Members

> **Depends on:** 001-scaffolding

## Summary

Admins can view, create, edit, and deactivate members within their organization. Members are the core people entity — everything else in the system references them.

## Data Model

### Member Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization, tenant isolation |
| FirstName | string | Required |
| LastName | string | Required |
| Email | string | Required, unique within organization |
| Role | Role enum | Admin or Member |
| IsActive | bool | Default true. Deactivated members are hidden from assignment but preserved |
| CreatedAt | DateTimeOffset | Set on creation |

### Fluent API Configuration

- `Member` → `members` table.
- Unique index on `(OrganizationId, Email)`.
- `OrganizationId` required FK with cascade delete.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/members` | List active members for current org. Supports `?search=` query param for name/email filtering. | Admin, Member |
| GET | `/api/members/{id}` | Get member by ID | Admin, Member |
| POST | `/api/members` | Create a new member | Admin |
| PUT | `/api/members/{id}` | Update member name, email, role | Admin |
| PATCH | `/api/members/{id}/deactivate` | Set IsActive = false | Admin |
| PATCH | `/api/members/{id}/reactivate` | Set IsActive = true | Admin |
| GET | `/api/members/me` | Get current member's own profile | Admin, Member |
| PUT | `/api/members/me` | Update own name and email (not role) | Admin, Member |

All endpoints scope to the current user's organization automatically.

## Frontend

### Pages

- **Member List** (`/members`) — data table with columns: Name, Email, Role, Status. Sortable, searchable, paginated. "Add Member" button for admins. Each row links to member detail.
- **Member Detail** (`/members/:id`) — card showing member info. Edit button (admins only) opens an edit form/modal. Deactivate/Reactivate button (admins only).
- **Add Member** (`/members/new`) — form with FirstName, LastName, Email, Role select. Validates email uniqueness on submit.

### Member Profile Page

- **Profile** (`/profile`) — the current member's own profile page. Shows their name, email, and role. Edit button opens a form to update name and email (role is not self-editable). This is in the member nav per the constitution's Navigation Structure.

### Role-Based UI

- Members see the member list (read-only, no add/edit/deactivate controls).
- Admins see full CRUD controls.

## Business Rules

- Email must be unique within the organization — return 409 Conflict if duplicate.
- Deactivated members are excluded from list queries by default. Admins can toggle a "Show inactive" filter.
- Deactivation is soft — the member record is preserved for historical data (attendance, auditions).
- Cannot deactivate yourself.

## Acceptance Criteria

- Admin can create a member and see them in the list.
- Admin can edit a member's name and role.
- Admin can deactivate a member — they disappear from the default list.
- Admin can reactivate a deactivated member.
- Member role users see the list but cannot add/edit/deactivate.
- Search filters by name and email.
- Duplicate email within the same org returns an error.
- Member can view their own profile at `/profile`.
- Member can update their own name and email from the profile page.
- Member cannot change their own role.
