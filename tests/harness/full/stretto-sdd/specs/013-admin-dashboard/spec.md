# 013 — Admin Dashboard

> **Depends on:** 003-program-years, 004-projects, 005-member-assignment, 008-events-attendance

## Summary

Replace the placeholder dashboard from spec 001 with a real admin dashboard showing an overview of the current program year: upcoming events, recent activity, and quick stats. Members see their calendar (spec 012) as their landing page — this spec covers the admin view only.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/dashboard` | Returns dashboard data for the current program year: upcoming events, project summary stats, recent activity | Admin |

### Response Shape

```json
{
  "currentProgramYear": { "id": "...", "name": "2026-2027" },
  "stats": {
    "totalProjects": 4,
    "totalMembers": 32,
    "upcomingEventsThisWeek": 3
  },
  "upcomingEvents": [
    {
      "id": "...",
      "projectName": "Holiday Concert",
      "type": "Rehearsal",
      "date": "2026-03-05",
      "startTime": "19:00",
      "venueName": "First Lutheran Church"
    }
  ],
  "recentActivity": [
    {
      "description": "Jane Smith assigned to Holiday Concert",
      "timestamp": "2026-03-01T14:30:00Z"
    }
  ]
}
```

- `upcomingEvents`: next 5 events across all projects in the current program year, sorted by date.
- `recentActivity`: last 10 actions (member additions, assignments, event creations) — derived from `CreatedAt`/`AssignedAt` timestamps across entities.
- All data scoped to the current program year and current organization.

## Frontend

### Admin Dashboard (`/`)

- **Program year header** — current program year name with a link to switch (program year selector per constitution navigation).
- **Stats row** — three summary cards: Total Projects, Total Members, Upcoming Events This Week. Each card shows a number with a label, using the card component pattern from the constitution.
- **Upcoming Events** — card listing next 5 events: project name, event type badge, date, time, venue. Each event links to the event detail page. Empty state: "No upcoming events in {program year name}."
- **Recent Activity** — card listing last 10 actions as a timeline/feed. Each entry shows description and relative timestamp (e.g., "2 hours ago" via date-fns). Empty state: "No recent activity."

### Member Landing

- Members continue to see their calendar (spec 012) as `/`. The router checks role from the auth store and renders the appropriate component.

## Business Rules

- Dashboard data is read-only — no mutations from this page.
- If no current program year is set, the stats section shows zeros and the events/activity sections show empty states with a CTA: "Set a current program year to get started."
- Recent activity is best-effort — derived from entity timestamps, not a separate events table. No need for a dedicated activity log entity.

## Acceptance Criteria

- Admin logs in and sees the dashboard with stats, upcoming events, and recent activity.
- Stats reflect correct counts for the current program year.
- Upcoming events list shows the next 5 events sorted by date.
- Clicking an event navigates to the event detail page.
- Admin with no current program year sees empty states with a helpful CTA.
- Member logs in and sees their calendar, not the admin dashboard.
