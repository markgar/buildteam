# 009 — Auditions

> **Depends on:** 002-members, 003-program-years

## Summary

Auditions are scheduled evaluation events tied to a program year. Admins define audition dates with time windows and block lengths, the system generates time slots, and members sign up for available slots. Signing up is the entry point for new members — an account is created automatically.

## Data Model

### AuditionDate Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| ProgramYearId | Guid | FK → ProgramYear |
| Date | DateOnly | Required |
| StartTime | TimeOnly | Required |
| EndTime | TimeOnly | Required, must be after StartTime |
| BlockLengthMinutes | int | Required (e.g., 10, 15) |
| CreatedAt | DateTimeOffset | Set on creation |

### AuditionSlot Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| AuditionDateId | Guid | FK → AuditionDate |
| StartTime | TimeOnly | Generated from parent date's time window |
| MemberId | Guid? | FK → Member, null if unclaimed |
| Status | AuditionStatus enum | Pending, Accepted, Rejected, Waitlisted |
| Notes | string? | Admin notes taken during audition |

### Enums

- `AuditionStatus`: Pending (default), Accepted, Rejected, Waitlisted

### Fluent API Configuration

- `AuditionDate` → `audition_dates` table. FK to ProgramYear (cascade).
- `AuditionSlot` → `audition_slots` table. FK to AuditionDate (cascade). Optional FK to Member. Index on `(AuditionDateId, StartTime)`.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/program-years/{pyId}/auditions` | List audition dates for a program year | Admin, Member |
| GET | `/api/auditions/{id}` | Get audition date with all slots | Admin, Member |
| POST | `/api/program-years/{pyId}/auditions` | Create audition date — auto-generates slots | Admin |
| PUT | `/api/auditions/{id}` | Update audition date (regenerates slots if time/block changes — only if no sign-ups exist) | Admin |
| DELETE | `/api/auditions/{id}` | Delete audition date and slots | Admin |
| POST | `/api/auditions/slots/{slotId}/signup` | Sign up for a slot. Body: `{ firstName, lastName, email }`. Creates member if new. Uses `[AllowAnonymous]` per constitution. | Public |
| PUT | `/api/auditions/slots/{slotId}/status` | Update slot status (Accepted/Rejected/Waitlisted) | Admin |
| PUT | `/api/auditions/slots/{slotId}/notes` | Update admin notes for a slot | Admin |

## Frontend

### Audition Management Page (`/program-years/:pyId/auditions`)

- List of audition dates as cards: date, time window, block length, slot fill rate (e.g., "5/12 slots filled").
- "Add Audition Date" button (admin).
- Click a date to see its slots.

### Audition Date Detail (`/auditions/:id`)

#### Admin View
- Table of all slots: Time, Member Name (or "Available"), Status badge (color-coded: Pending amber, Accepted green, Rejected red, Waitlisted blue), Notes.
- Click a slot to edit notes. Status dropdown to change status.
- Copy sign-up link button (for sharing with prospective members).

#### Member/Public Sign-Up View

- Available at a sharable URL (e.g., `/auditions/:id/signup`).
- Shows available (unclaimed) slots as a list of time buttons.
- Member clicks a time → form appears: First Name, Last Name, Email. Submit claims the slot.
- If the email already exists in the org, links to existing member. If new, creates the member.

### Add Audition Date Form

- Fields: Date (date picker), Start Time, End Time (time pickers), Block Length (select: 5, 10, 15, 20, 30 minutes).
- On submit, validates block length divides evenly into the time window. Shows inline error if not.

## Business Rules

- Block length must divide evenly into the time window `(EndTime - StartTime)`. API returns 400 with a clear message if not (e.g., "15-minute blocks don't divide evenly into a 70-minute window").
- Slots are auto-generated server-side when an audition date is created. If the date is updated and no sign-ups exist, slots are regenerated.
- A member cannot sign up for a slot that is already claimed — return 409.
- A member cannot sign up for more than one slot on the same audition date — return 409.
- Sign-up with a new email creates a Member record with Role = Member, IsActive = true.
- Sign-up with an existing email links to the existing member (no duplicate created).
- The sign-up endpoint is public (no auth required) — this is how new members enter the system.

## Acceptance Criteria

- Admin creates an audition date (10:00–12:00, 15-min blocks) — 8 slots are generated.
- Admin attempts 10-min blocks on a 70-min window — gets a validation error.
- New user signs up with email `new@example.com` — slot is claimed, member account is created.
- Existing member signs up — slot links to their existing account.
- Second person tries to claim the same slot — gets a 409 error.
- Admin updates a slot to "Accepted" — status badge turns green.
- Admin takes notes on a slot — notes persist.
- Admin can see the fill rate on the audition list.
