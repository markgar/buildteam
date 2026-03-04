# 012 — Member Calendar & iCal Export

> **Depends on:** 008-events-attendance

## Summary

Members see a personal calendar of all their upcoming events across all assigned projects. They can subscribe to or download an iCal (.ics) feed to sync with Google Calendar, Apple Calendar, or Outlook.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/members/me/events` | List all upcoming events for the current member across all assigned projects. Supports `?from=` and `?to=` date range filters. | Member |
| GET | `/api/members/me/calendar.ics` | Generate an iCal feed of the member's events. Uses `[AllowAnonymous]` with per-member token validation per constitution. | Public (token-based) |
| POST | `/api/members/me/calendar-token` | Generate or regenerate the member's calendar subscription token | Member |

### iCal Token

- Each member has an optional `CalendarToken` (Guid, stored on the Member entity).
- The `.ics` URL includes the token: `/api/members/me/calendar.ics?token={calendarToken}`.
- This URL is what members paste into Google Calendar's "subscribe by URL" feature.
- Regenerating the token invalidates the old URL (for security — if shared accidentally).

## Data Model Changes

Add to Member entity:

| Field | Type | Notes |
|---|---|---|
| CalendarToken | Guid? | Optional. Generated on first calendar subscription request. |

## Frontend

### Member Dashboard — Calendar View

- A calendar component showing the current month.
- Events displayed as colored blocks on their dates: Rehearsal (indigo) and Performance (accent/darker).
- Clicking an event navigates to the event detail page.
- Previous/Next month navigation.
- Small event list below the calendar for the current/selected week showing: event name, project name, venue, date, time.

### Calendar Subscription Section

- Below the calendar, a section: "Subscribe to your calendar."
- "Generate Link" button creates the calendar token and shows the subscription URL.
- Copy-to-clipboard button next to the URL.
- Instructions: "Paste this URL in Google Calendar → Other calendars → From URL" (with similar instructions for Apple Calendar and Outlook).
- "Regenerate Link" button (with warning that it invalidates the old link).

## iCal Format

The `.ics` response should be a valid iCalendar document:

```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Stretto//Events//EN
X-WR-CALNAME:Stretto Events
BEGIN:VEVENT
UID:{eventId}@stretto
DTSTART:{date}T{startTime}
DTEND:{date}T{endTime}
SUMMARY:{eventType}: {projectName}
LOCATION:{venueName}, {venueAddress}
DESCRIPTION:Project: {projectName}
END:VEVENT
...
END:VCALENDAR
```

- Content-Type: `text/calendar; charset=utf-8`.
- Include all future events for the member's assigned projects.
- End time computed from start time + duration.

## Business Rules

- The calendar shows only events for projects the member is currently assigned to.
- Past events are included in the iCal feed (calendar apps handle past events gracefully).
- The dashboard calendar page only shows upcoming events (from today forward).
- Calendar token is unique per member. If null, the subscription section shows "Generate Link" instead of the URL.
- The `.ics` endpoint returns 401 if the token is invalid or missing.

## Acceptance Criteria

- Member views the calendar page — sees their upcoming rehearsals and performances across all projects.
- Calendar shows correct event dates, times, and types.
- Member generates a calendar subscription link — URL is displayed.
- Fetching the `.ics` URL returns a valid iCalendar document with correct events.
- Subscribing in Google Calendar shows Stretto events.
- Member regenerates the token — old URL stops working, new URL works.
- Member with no events sees an empty calendar with a friendly message.
