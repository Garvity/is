# Research Audit

## 1. Verified Findings
- **Helumi uses NSFileProviderReplicatedExtension**: Confirmed. OrbitFS.appex implements the required callbacks for Finder integration.
- **Helumi Architecture**: Uses OrbitCore shared framework for API, sync, encryption, and local storage.
- **MountHelper**: The research identified a MountHelper XPC service, but our design decision to use native File Provider APIs makes this **unnecessary**. The research was correct about its existence, but the decision to include it in our implementation is **rejected**.
- **Local Endpoints**: String constants like localhost:8787 were found. While their exact usage is not fully mapped, the presence strongly indicates local API communication or streaming.

## 2. Incorrect/Unsupported Assumptions
- **Requirement of MountHelper**: The research assumed Helumi's implementation is the *required* way to achieve cloud drive functionality. Our verification shows standard File Provider APIs are sufficient.

## 3. Confidence Levels
- **File Provider implementation**: High.
- **Backend API structure**: Medium (inferred from string constants/mangled names).
- **Encryption scheme**: Medium (inferred from WireSecrets and BlobSource models).

## 4. Unknowns
- **Conflict resolution UI**: Exact handling of version mismatch. (Need to spike this).
- **JSON Serialization**: Full schemas for envelopes.
