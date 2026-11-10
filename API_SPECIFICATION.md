# API Specification

## Base URL
- Development: `http://localhost:3000`
- Production: `https://api.clouddrive.example.com`

## Authentication
- **Type**: JWT Bearer Token (HS256)
- **Header**: `Authorization: Bearer <token>`
- **Expiry**: 24 hours
- **Claims**: `sub` (user UUID), `exp` (Unix timestamp)

## Endpoints

### Health Check
```
GET /health
```
- **Response**: `200 OK` with body `OK`

### Authentication

#### Register User
```
POST /auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword123"
}
```
- **Success**: `201 Created`
  ```json
  {
    "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."
  }
  ```
- **Error**: `400 Bad Request` - Email already exists
- **Validation**: Email format, password min 6 chars

#### Login
```
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword123"
}
```
- **Success**: `200 OK`
  ```json
  {
    "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."
  }
  ```
- **Error**: `401 Unauthorized` - Invalid credentials

#### Get Current User
```
GET /auth/me
Authorization: Bearer <token>
```
- **Success**: `200 OK`
  ```json
  {
    "id": "uuid-string",
    "email": "user@example.com"
  }
  ```
- **Error**: `401 Unauthorized` - Missing/invalid/expired token

### Items (Files & Folders)

#### List Items
```
GET /items
Authorization: Bearer <token>
```
- **Success**: `200 OK`
  ```json
  {
    "folders": [
      {
        "id": "uuid",
        "userId": "uuid",
        "parentId": "uuid|null",
        "name": "Folder Name",
        "createdAt": "2026-11-07T08:30:00Z",
        "updatedAt": "2026-11-07T08:30:00Z"
      }
    ],
    "files": [
      {
        "id": "uuid",
        "userId": "uuid",
        "folderId": "uuid|null",
        "name": "document.pdf",
        "mimeType": "application/pdf",
        "size": 1024000,
        "r2Key": "uploads/uuid/document.pdf",
        "createdAt": "2026-11-07T08:30:00Z",
        "updatedAt": "2026-11-07T08:30:00Z"
      }
    ]
  }
  ```
- **Error**: `401 Unauthorized`

#### Create Item
```
POST /items
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "New Folder",
  "item_type": "folder",  // or "file"
  "parent_id": "uuid|null"
}
```
- **Success**: `201 Created` (returns created item)
- **Error**: `400 Bad Request` - Invalid item_type
- **Note**: For files, `mime_type` defaults to `application/octet-stream`, `size` to `0`

#### Get Item
```
GET /items/:id
Authorization: Bearer <token>
```
- **Success**: `200 OK` (returns folder or file object)
- **Error**: `404 Not Found` - Item not found or not owned by user
- **Note**: Checks both folders and files tables

#### Update Item
```
PATCH /items/:id
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "Renamed Item"
}
```
- **Success**: `200 OK` (returns updated item)
- **Error**: `404 Not Found` - Item not found or not owned by user
- **Note**: Only `name` can be updated currently

#### Delete Item
```
DELETE /items/:id
Authorization: Bearer <token>
```
- **Success**: `204 No Content`
- **Error**: `404 Not Found` - Item not found or not owned by user
- **Note**: Cascades to children for folders (DB constraint)

## Error Responses

All errors return JSON:
```json
{
  "error": "Human-readable error message"
}
```

### HTTP Status Codes
| Code | Meaning |
|------|---------|
| 200 | OK |
| 201 | Created |
| 204 | No Content |
| 400 | Bad Request (validation) |
| 401 | Unauthorized (auth) |
| 404 | Not Found |
| 500 | Internal Server Error |

## Swift API Client Usage

```swift
let client = APIClient.shared

// Register
let token = try await client.register(email: "user@test.com", password: "password")

// Login
let token = try await client.login(email: "user@test.com", password: "password")

// Get current user
let user = try await client.fetchMe()

// List items
let items = try await client.fetchItems()
// items.folders: [FolderDTO]
// items.files: [FileDTO]

// Create folder
let folder = try await client.createItem(name: "MyFolder", type: "folder", parentId: nil)
```

## Backend Configuration (.env)

```bash
DATABASE_URL=postgres://user:password@localhost:5432/clouddrive
JWT_SECRET=your-super-secret-key-min-32-chars
PORT=3000
```

## Database Migrations

Run on backend startup via `sqlx::migrate!("./migrations")`:
1. `0001_create_users.sql` - Users table
2. `0002_create_folders.sql` - Folders table
3. `0003_create_files.sql` - Files table

## Testing Commands

```bash
# Health
curl http://localhost:3000/health

# Register
curl -X POST http://localhost:3000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"password123"}'

# Login
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"password123"}'

# Get user (with token)
curl -H "Authorization: Bearer <token>" http://localhost:3000/auth/me

# List items
curl -H "Authorization: Bearer <token>" http://localhost:3000/items

# Create folder
curl -X POST http://localhost:3000/items \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"TestFolder","item_type":"folder"}'
```
