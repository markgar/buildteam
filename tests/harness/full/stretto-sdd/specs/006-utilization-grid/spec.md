# 006 — Utilization Grid

> **Depends on:** 005-member-assignment

## Summary

A matrix view showing all members vs. all projects in a program year, with filled cells indicating assignment. Sorted by utilization (most-assigned at top). Gives admins a bird's-eye view to balance workloads and spot gaps.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/program-years/{pyId}/utilization` | Returns utilization grid data: members with their assignment counts and a matrix of project assignments | Admin |

### Response Shape

```json
{
  "projects": [
    { "id": "...", "name": "Holiday Concert" },
    { "id": "...", "name": "Spring Gala" }
  ],
  "members": [
    {
      "id": "...",
      "name": "Jane Smith",
      "assignedCount": 2,
      "totalProjects": 3,
      "utilization": 0.67,
      "assignments": ["project-id-1", "project-id-2"]
    }
  ]
}
```

- Members sorted by `assignedCount` descending (highest utilization first).
- All computation is server-side — the frontend just renders.

## Frontend

### Desktop View (≥1024px)

- Full matrix: rows = members, columns = projects.
- Column headers: project names (truncated with tooltip if long).
- Row headers: member name + utilization count (e.g., "2/3 — 67%").
- Filled cells: accent color (indigo). Empty cells: light gray.
- High-utilization members (100%): subtle background highlight on the entire row.

### Mobile View (<768px)

- Switch to a **list view grouped by member**.
- Each member is a collapsible accordion section.
- Expanded: shows assigned project names as chips/badges.
- Utilization count displayed next to member name.

### Navigation

- Accessible from the program year context — sidebar link "Utilization" or a tab within the program year view.

## Business Rules

- Only active members are included.
- Only non-archived program years are selectable.
- Grid is read-only — assignments are managed via the project detail page (spec 005).

## Acceptance Criteria

- Grid shows all active members and all projects for the selected program year.
- Members are sorted by assignment count, highest first.
- Filled cells correspond to actual assignments.
- Utilization percentage is correct (assigned / total projects).
- Mobile view shows collapsible member list with project badges.
- Grid updates after an assignment change (navigating back to the grid reflects new data via Tanstack Query cache invalidation).
