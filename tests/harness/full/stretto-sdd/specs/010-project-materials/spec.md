# 010 — Project Materials

> **Depends on:** 004-projects, 005-member-assignment

## Summary

Each project has a materials section where admins share links and upload documents with assigned members. Members can browse and download materials for their assigned projects.

## Data Model

### ProjectLink Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| ProjectId | Guid | FK → Project |
| Title | string | Required |
| Url | string | Required, valid URL |
| CreatedAt | DateTimeOffset | Set on creation |

### ProjectDocument Entity (Domain)

| Field | Type | Notes |
|---|---|---|
| Id | Guid | PK |
| OrganizationId | Guid | FK → Organization |
| ProjectId | Guid | FK → Project |
| FileName | string | Original uploaded filename |
| ContentType | string | MIME type |
| StoragePath | string | Path in storage provider |
| FileSizeBytes | long | File size |
| UploadedAt | DateTimeOffset | Set on upload |

### Fluent API Configuration

- `ProjectLink` → `project_links` table. FK to Project (cascade).
- `ProjectDocument` → `project_documents` table. FK to Project (cascade).

## Storage Abstraction

- `IFileStorageService` interface in Application layer:
  - `Task<string> UploadAsync(Stream file, string fileName, string contentType, Guid organizationId, Guid projectId)`
  - `Task<Stream> DownloadAsync(string storagePath)`
  - `Task DeleteAsync(string storagePath)`
- `LocalFileStorageService` implementation in Infrastructure:
  - Stores files at `uploads/{organizationId}/{projectId}/{guid}-{fileName}`.
  - Swappable to Azure Blob Storage later.

## API Endpoints

| Method | Path | Description | Auth |
|---|---|---|---|
| GET | `/api/projects/{id}/links` | List links for a project. Uses resource-level authorization per constitution. | Admin, Member (assigned) |
| POST | `/api/projects/{id}/links` | Add a link | Admin |
| DELETE | `/api/projects/{id}/links/{linkId}` | Remove a link | Admin |
| GET | `/api/projects/{id}/documents` | List documents for a project (metadata only). Uses resource-level authorization per constitution. | Admin, Member (assigned) |
| POST | `/api/projects/{id}/documents` | Upload a document (multipart form) | Admin |
| GET | `/api/projects/{id}/documents/{docId}/download` | Download a document (returns file stream). Uses resource-level authorization per constitution. | Admin, Member (assigned) |
| DELETE | `/api/projects/{id}/documents/{docId}` | Delete a document (removes file + record) | Admin |

## Frontend

### Project Detail — Materials Tab

- Two sections: **Links** and **Documents**.
- **Links section**: list of link cards (title + URL as clickable external link). "Add Link" button (admin) opens a modal with Title + URL fields.
- **Documents section**: list of document cards (filename, size, upload date). Download button on each. "Upload Document" button (admin) opens a file picker. Delete button (admin) with confirmation dialog.

### Member View

- Members assigned to the project see the Materials tab as read-only (no add/upload/delete controls).
- Members not assigned to the project cannot see its materials (API returns 403).

## Business Rules

- Only members assigned to a project can view its materials — API enforces this (except admins, who can always access).
- Document upload should validate reasonable file size limits (e.g., 50MB max) — return 413 if exceeded.
- Deleting a document removes both the database record and the stored file.
- Link URL should be validated as a well-formed URL.

## Acceptance Criteria

- Admin adds a link "Sheet Music Store" with a URL — appears in the materials tab.
- Admin uploads a PDF document — appears in the documents list with filename and size.
- Member assigned to the project can view links and download documents.
- Member not assigned to the project gets 403 when accessing materials.
- Admin deletes a document — file and record are removed.
- Uploading a file > 50MB is rejected.
