# 008 — Events & Attendance

> **Depends on:** 004-projects, 005-member-assignment, 007-venues

## Summary

Events are scheduled rehearsals or performances within a project. Each event has a date, time, duration, type, and venue. Members check in via QR code at the venue, and admins track attendance.

## Data Model

### Event Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| ProjectId | Guid | FK → Project |
| VenueId | Guid | FK → Venue |
| Type | EventType enum | Rehearsal or Performance |
| Date | DateOnly | Required |
| StartTime | TimeOnly | Required |
| DurationMinutes | int | Required, > 0 |
| CreatedAt | DateTimeOffset | Set on creation |

### AttendanceRecord Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| EventId | Guid | FK → Event |
| MemberId | Guid | FK → Member |
| Status | AttendanceStatus enum | NoStatus, Present, Excused, Absent |
| CheckedInAt | DateTimeOffset? | Set when member checks in |

### Enums

- `EventType`: Rehearsal, Performance
- `AttendanceStatus`: NoStatus (default), Present, Excused, Absent

### Fluent API Configuration

- `Event` → `events` table. FK to Project (cascade delete) and Venue (restrict delete).
- `AttendanceRecord` → `attendance_records` table. Unique index on `(EventId, MemberId)`.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/projects/{id}/events` | List events for a project | Admin, Member |
| GET | `/api/events/{id}` | Get event by ID, including attendance records | Admin, Member |
| POST | `/api/projects/{id}/events` | Create an event | Admin |
| PUT | `/api/events/{id}` | Update event details | Admin |
| DELETE | `/api/events/{id}` | Delete an event | Admin |
| POST | `/api/events/{id}/checkin` | Check in the current member (set status = Present) | Member |
| PUT | `/api/events/{id}/attendance/{memberId}` | Admin sets attendance status for a member | Admin |
| PATCH | `/api/events/{id}/excuse` | Current member marks themselves excused for an upcoming event | Member |

## Frontend

### Project Detail — Events Tab

- Table of events: Type (tag), Date, Start Time, Duration, Venue name. Sortable by date.
- "Add Event" button (admin). Click event to view detail.

### Event Detail Page (`/events/:id`)

- Event info card: type badge, date, time, duration, venue (link to venue).
- **Attendance table** (admin view): all assigned members, status badges (color-coded per constitution), dropdown to change status.
- **Member view**: shows their own attendance status and the "Mark Excused" button for upcoming events.

### QR Check-In Page (`/checkin/:eventId`)

- Minimal, mobile-optimized page — no sidebar, no navigation chrome.
- Shows event name and venue.
- Large, full-width green "I'm Here" button (56px+ tall, checkmark icon on success).
- If already checked in, shows a green confirmation instead of the button.
- Each event has a unique URL for QR code generation (admins can copy/print the URL).

### Member Dashboard — Excuse Flow

- Members see upcoming events on their dashboard.
- "Mark Excused" button next to each upcoming event. Tapping it calls the excuse endpoint.

## Business Rules

- Event date must fall within the project's StartDate–EndDate range — API returns 400 if out of range.
- Check-in is only allowed for members assigned to the event's project — API returns 403 if not assigned.
- A member can only check in once per event (idempotent — second call returns 200, no change).
- "Mark Excused" is only available for future events (not past events).
- Admins can override any member's attendance status.

## Acceptance Criteria

- Admin creates a rehearsal event with a venue — appears in the project's events tab.
- Admin creates a performance event — type badge distinguishes it from rehearsals.
- Event with a date outside the project range is rejected.
- Member scans QR code (visits check-in URL), taps "I'm Here" — status changes to Present.
- Member not assigned to the project gets 403 when attempting check-in.
- Member marks themselves excused for an upcoming event — status changes to Excused.
- Admin views attendance for an event — sees all assigned members with status badges.
- Admin changes a member's status to Absent — change persists.
