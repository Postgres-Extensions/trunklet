# pg_tle Version Support Matrix

This file documents pg_tle version boundaries that affect pgxntool's pg_tle support code. Each boundary represents a backward-incompatible API change.

## Version Ranges (pgxntool notation)

### 1.0.0-1.4.0
- **pg_tle versions:** 1.0.0 through 1.3.x
- **PostgreSQL support:** 11-17
- **Features:** Basic extension management, custom data types, authentication hooks

### 1.4.0-1.5.0
- **pg_tle versions:** 1.4.0 through 1.4.x
- **PostgreSQL support:** 11-17
- **API:** Added alignment/storage parameters to `pgtle.create_base_type()`
- **Features:** Custom alignment/storage, enhanced warnings

### 1.5.0+
- **pg_tle versions:** 1.5.0 and later (tested through 1.5.2)
- **PostgreSQL support:** 12-18 (dropped PG 11)
- **API:** BREAKING CHANGE - `pgtle.install_extension()` now requires schema parameter
- **Features:** Schema parameter support in installation

## Key API Changes by Version

**1.4.0:** Added alignment/storage parameters to `pgtle.create_base_type()`

**1.5.0**
- Changed `pgtle.install_extension()` signature
- Added required `schema` parameter
- Dropped PostgreSQL 11 support

## Version Notation

- `X.Y.Z+` - Works on pg_tle >= X.Y.Z
- `X.Y.Z-A.B.C` - Works on pg_tle >= X.Y.Z and < A.B.C

**Boundary conditions:**
- `1.5.0+` means >= 1.5.0 (includes 1.5.0)
- `1.4.0-1.5.0` means >= 1.4.0 and < 1.5.0 (excludes 1.5.0)
- `1.0.0-1.4.0` means >= 1.0.0 and < 1.4.0 (excludes 1.4.0)

## For Complete Details

- `pgtle.sh` (comments at top)
- https://github.com/aws/pg_tle
