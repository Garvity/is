# Product Specification

## Functional Requirements
- **Native Finder Integration**: Cloud files appear as local files with metadata.
- **On-Demand Hydration**: Files are downloaded only when accessed.
- **Resumable Uploads**: Robust upload pipeline with resumeKey support.
- **Client-Side Encryption**: Zero-knowledge encryption.
- **Multi-Device Sync**: Metadata and content synchronization.
- **Conflict Resolution**: Native Finder conflict handling.

## Non-Functional Requirements
- **Performance**: Efficient memory usage (no large files in memory).
- **Resilience**: Handle network interruptions, retries, and background operations gracefully.
- **Security**: Secure key management, zero-knowledge storage, authenticated API calls.
