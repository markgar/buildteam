# 011 — Notifications

> **Depends on:** 002-members, 005-member-assignment, 009-auditions

## Summary

Admins can send assignment announcements and audition sign-up notifications to members. Members can opt out of notifications. The delivery mechanism uses a provider abstraction — stubbed for now, swappable to SendGrid/SMTP later.

## Data Model

### NotificationPreference (on Member Entity)

Add to the existing Member entity:

| Field | Type | Notes |
|---|---|---|
| NotificationsEnabled | bool | Default true. When false, member is excluded from all notification sends. |

### NotificationLog Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| Type | NotificationType enum | AssignmentAnnouncement, AuditionAnnouncement |
| SentBy | Guid | FK → Member (admin who triggered it) |
| RecipientCount | int | Number of members notified |
| SentAt | DateTimeOffset | Timestamp |

### Enums

- `NotificationType`: AssignmentAnnouncement, AuditionAnnouncement

## Notification Provider Abstraction

- `INotificationService` interface in Application layer:
  - `Task SendAssignmentAnnouncementAsync(Guid programYearId, Guid sentByMemberId)` — sends each member their project assignments for the program year.
  - `Task SendAuditionAnnouncementAsync(Guid programYearId, string signUpUrl, Guid sentByMemberId)` — sends notification that audition sign-ups are open.
- `StubNotificationService` implementation in Infrastructure:
  - Logs the send to console/application log (no actual email sent).
  - Creates a `NotificationLog` record.
  - Returns success.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| POST | `/api/program-years/{pyId}/notifications/assignments` | Send assignment announcements to all members with assignments in this program year | Admin |
| POST | `/api/program-years/{pyId}/notifications/auditions` | Send audition sign-up open notification to all org members | Admin |
| GET | `/api/notifications/log` | List recent notification sends for the org | Admin |
| PATCH | `/api/members/me/notifications` | Toggle notification preference for current member | Member |

## Frontend

### Admin — Notification Actions

- On the program year detail or project list page, two action buttons:
  - "Send Assignment Announcements" — confirmation dialog: "This will notify {N} members of their {program year} project assignments. Continue?" On confirm, calls the endpoint. Shows toast on success.
  - "Send Audition Announcements" — confirmation dialog: "This will notify {N} members that audition sign-ups are open. Continue?" Includes the sign-up URL in the notification.
- **Notification History** (`/notifications`) — table of recent sends: Type, Date, Sent By, Recipient Count.

### Member — Notification Preferences

- On the member's profile/settings page, a toggle: "Receive email notifications" (on/off).
- Turning off excludes them from all future notification sends.

## Business Rules

- Only members with `NotificationsEnabled = true` receive notifications.
- Assignment announcements only go to members who have at least one assignment in the program year.
- Audition announcements go to all active members in the organization (regardless of assignment).
- Each notification send is logged for audit purposes.
- The stub implementation logs sends but doesn't deliver anything — frontend can show "Notification sent (delivery stubbed)" in the toast.

## Acceptance Criteria

- Admin sends assignment announcements — notification log shows the send with correct recipient count.
- Admin sends audition announcements — notification log records it.
- Member disables notifications — they are excluded from the next send.
- Member re-enables notifications — they receive future sends.
- Notification history page shows recent sends with type, date, and count.
- Stub implementation logs to console without errors.
