# Oracle HR Schema — Automated Deployment with Liquibase

> **Demonstrator Project**: Automated database code deployment to Oracle Autonomous Database using [Liquibase Community Edition](https://www.liquibase.com/community) and GitHub Actions CI/CD.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Database User Setup — LIQUIBASE_DEPLOYER](#database-user-setup--liquibase_deployer)
- [GitHub Secrets Configuration](#github-secrets-configuration)
  - [1. ORACLE_WALLET_BASE64](#1-oracle_wallet_base64)
  - [2. DB_USERNAME](#2-db_username)
  - [3. DB_PASSWORD](#3-db_password)
  - [4. WALLET_PASSWORD](#4-wallet_password)
- [Updating the Oracle Wallet](#updating-the-oracle-wallet)
- [GitHub Actions CI/CD Pipeline](#github-actions-cicd-pipeline)
- [Liquibase Tracking Tables](#liquibase-tracking-tables)
- [How Changelogs Are Organized](#how-changelogs-are-organized)
- [Adding New Database Changes](#adding-new-database-changes)
- [Running Liquibase Locally](#running-liquibase-locally)
- [Troubleshooting](#troubleshooting)

---

## Overview

This repository contains the Oracle **HR (Human Resources)** sample schema — tables, views, procedures, functions, sequences, and triggers — managed as version-controlled SQL files and deployed automatically using **Liquibase Community Edition (OSS)**.

### What This Project Demonstrates

| Concept | Implementation |
|---|---|
| **Infrastructure as Code** | All database objects defined as SQL files in Git |
| **Automated Deployment** | Liquibase applies changes via GitHub Actions |
| **Secure Connectivity** | mTLS wallet authentication to Oracle Autonomous DB |
| **Secret Management** | Wallet, credentials stored as GitHub Secrets |
| **Cross-Schema Deployment** | `LIQUIBASE_DEPLOYER` user creates objects in `HR` schema |
| **Change Tracking** | Liquibase maintains a changelog in `LIQUIBASE_DEPLOYER` schema |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       GitHub Repository                      │
│  ┌───────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ SQL Files  │  │ Liquibase        │  │ GitHub Actions   │  │
│  │ (TABLES/,  │  │ Changelogs       │  │ Workflow         │  │
│  │  VIEWS/,   │  │ (db/changelog/)  │  │ (.github/        │  │
│  │  etc.)     │  │                  │  │  workflows/)     │  │
│  └─────┬──── ┘  └────────┬─────────┘  └────────┬─────────┘  │
│        │                 │                      │            │
└────────┼─────────────────┼──────────────────────┼────────────┘
         │                 │                      │
         │    ┌────────────▼────────────┐         │
         │    │  liquibase update       │◄────────┘
         │    │  (GitHub Actions Runner)│
         │    └────────────┬────────────┘
         │                 │
         │        ┌────────▼────────┐
         │        │  Oracle Wallet  │  ← Decoded from
         │        │  (mTLS / JKS)   │    ORACLE_WALLET_BASE64
         │        └────────┬────────┘
         │                 │ TLS 1.2 (port 1522)
         ▼                 ▼
┌─────────────────────────────────────────────────────────────┐
│            Oracle Autonomous Database (ADB)                  │
│            Region: ap-mumbai-1                               │
│  ┌─────────────────────┐    ┌────────────────────────────┐  │
│  │  LIQUIBASE_DEPLOYER │    │  HR Schema                 │  │
│  │  (Deployer User)    │───▶│  • Tables  • Procedures    │  │
│  │  ─────────────────  │    │  • Views   • Functions     │  │
│  │  DATABASECHANGELOG  │    │  • Sequences • Triggers    │  │
│  │  DATABASECHANGELOCK │    │                            │  │
│  └─────────────────────┘    └────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
databaserepo/
├── .github/
│   └── workflows/
│       └── liquibase-deploy.yml        # GitHub Actions CI/CD pipeline
├── .gitignore                          # Prevents wallet/credential commits
├── db/
│   └── changelog/
│       ├── db.changelog-master.xml     # Root changelog (entry point)
│       ├── 001-sequences.xml           # Sequence definitions
│       ├── 002-tables.xml              # Table definitions (dependency ordered)
│       ├── 003-deferred-constraints.xml# Circular FK constraints
│       ├── 004-views.xml               # View definitions
│       ├── 005-procedures.xml          # Stored procedures
│       ├── 006-functions.xml           # Functions
│       └── 007-triggers.xml            # Triggers
├── TABLES/
│   ├── REGIONS.sql
│   ├── COUNTRIES.sql
│   ├── LOCATIONS.sql
│   ├── JOBS.sql
│   ├── DEPARTMENTS.sql
│   ├── EMPLOYEES.sql
│   ├── JOB_HISTORY.sql
│   ├── NEW_TABLE_IN_PDB.sql
│   └── DEFERRED_FOREIGN_KEYS.sql       # Circular FK (DEPT_MGR_FK)
├── VIEWS/
│   └── EMP_DETAILS_VIEW.sql
├── PROCEDURES/
│   ├── ADD_JOB_HISTORY.sql
│   └── SECURE_DML.sql
├── FUNCTIONS/
│   └── SAMPLE_FUNCTION.sql
├── SEQUENCES/
│   ├── DEPARTMENTS_SEQ.sql
│   ├── EMPLOYEES_SEQ.sql
│   └── LOCATIONS_SEQ.sql
├── TRIGGERS/
│   ├── SECURE_EMPLOYEES.sql
│   └── UPDATE_JOB_HISTORY.sql
├── liquibase.properties                # Liquibase configuration
├── Jenkinsfile                         # Legacy Jenkins pipeline (reference)
└── README.md                           # This file
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Oracle Autonomous Database** | Any ADB instance (Transaction Processing, Data Warehouse, etc.) with mTLS enabled |
| **Oracle Wallet** | Downloaded from OCI Console → Autonomous Database → DB Connection → Download Wallet |
| **GitHub Repository** | This repo pushed to GitHub with Actions enabled |
| **LIQUIBASE_DEPLOYER user** | Database user with cross-schema deployment privileges (see below) |

> **Note**: You do **not** need to install Liquibase locally unless you want to test changes before pushing. The GitHub Actions workflow handles installation automatically.

---

## Database User Setup — LIQUIBASE_DEPLOYER

A dedicated deployment user `LIQUIBASE_DEPLOYER` is used to deploy objects into the `HR` schema. This user **does not own** the HR objects — it uses cross-schema privileges granted by a DBA.

### Required Grants

Connect to your Oracle Autonomous Database as `ADMIN` and run:

```sql
-- Create the deployer user (if not already created)
CREATE USER LIQUIBASE_DEPLOYER IDENTIFIED BY "<strong_password>";

-- Grant the developer role (includes CREATE SESSION, basic privileges)
GRANT DB_DEVELOPER_ROLE TO LIQUIBASE_DEPLOYER;

-- Comprehensive Cross-Schema Deployment Privileges (CREATE, ALTER, DROP)

-- Tables, Constraints & Comments
GRANT CREATE ANY TABLE        TO LIQUIBASE_DEPLOYER;
GRANT ALTER ANY TABLE         TO LIQUIBASE_DEPLOYER;
GRANT DROP ANY TABLE          TO LIQUIBASE_DEPLOYER;
GRANT COMMENT ANY TABLE       TO LIQUIBASE_DEPLOYER;

-- Indexes
GRANT CREATE ANY INDEX        TO LIQUIBASE_DEPLOYER;
GRANT ALTER ANY INDEX         TO LIQUIBASE_DEPLOYER;
GRANT DROP ANY INDEX          TO LIQUIBASE_DEPLOYER;

-- Views
GRANT CREATE ANY VIEW         TO LIQUIBASE_DEPLOYER;
GRANT DROP ANY VIEW           TO LIQUIBASE_DEPLOYER;

-- Procedures, Functions & Packages
GRANT CREATE ANY PROCEDURE    TO LIQUIBASE_DEPLOYER;
GRANT ALTER ANY PROCEDURE     TO LIQUIBASE_DEPLOYER;
GRANT DROP ANY PROCEDURE      TO LIQUIBASE_DEPLOYER;

-- Sequences
GRANT CREATE ANY SEQUENCE     TO LIQUIBASE_DEPLOYER;
GRANT ALTER ANY SEQUENCE      TO LIQUIBASE_DEPLOYER;
GRANT DROP ANY SEQUENCE       TO LIQUIBASE_DEPLOYER;

-- Triggers
GRANT CREATE ANY TRIGGER      TO LIQUIBASE_DEPLOYER;
GRANT ALTER ANY TRIGGER       TO LIQUIBASE_DEPLOYER;
GRANT DROP ANY TRIGGER        TO LIQUIBASE_DEPLOYER;

-- Synonyms
GRANT CREATE ANY SYNONYM      TO LIQUIBASE_DEPLOYER;
GRANT DROP ANY SYNONYM        TO LIQUIBASE_DEPLOYER;

-- Types
GRANT CREATE ANY TYPE         TO LIQUIBASE_DEPLOYER;
GRANT ALTER ANY TYPE          TO LIQUIBASE_DEPLOYER;
GRANT DROP ANY TYPE           TO LIQUIBASE_DEPLOYER;

-- Grant quota on default tablespace for Liquibase tracking tables
ALTER USER LIQUIBASE_DEPLOYER QUOTA UNLIMITED ON DATA;
```

### Updating the Password

If you need to change the `LIQUIBASE_DEPLOYER` password:

```sql
-- Connect as ADMIN
ALTER USER LIQUIBASE_DEPLOYER IDENTIFIED BY "<new_strong_password>";
```

After changing the password, **update the `DB_PASSWORD` GitHub Secret** immediately (see below).

---

## GitHub Secrets Configuration

Navigate to your GitHub repository:
**Settings → Secrets and variables → Actions → New repository secret**

You need to configure **4 secrets**:

### 1. ORACLE_WALLET_BASE64

The Oracle Wallet ZIP file, encoded as a base64 string. This allows the CI/CD runner to reconstruct the wallet at runtime without storing sensitive files in the repository.

**How to encode your wallet:**

```bash
# On Linux / macOS
base64 -w 0 /path/to/Wallet_OracleTransDB.zip > wallet_base64.txt

# On macOS (if -w is not supported)
base64 -i /path/to/Wallet_OracleTransDB.zip -o wallet_base64.txt
```

**Then create the secret:**

1. Open the `wallet_base64.txt` file
2. Copy the **entire** contents (it will be a single long line)
3. In GitHub → Settings → Secrets → Actions → **New repository secret**
   - **Name**: `ORACLE_WALLET_BASE64`
   - **Secret**: Paste the base64 string
4. Click **Add secret**

> ⚠️ **Security**: Delete the `wallet_base64.txt` file after creating the secret.

```bash
rm wallet_base64.txt
```

### 2. DB_USERNAME

The database username used for deployment.

| Field | Value |
|---|---|
| **Name** | `DB_USERNAME` |
| **Secret** | `LIQUIBASE_DEPLOYER` |

### 3. DB_PASSWORD

The password for the `LIQUIBASE_DEPLOYER` database user.

| Field | Value |
|---|---|
| **Name** | `DB_PASSWORD` |
| **Secret** | *(your LIQUIBASE_DEPLOYER password)* |

> ⚠️ This is the **database user password**, not the wallet password.

### 4. WALLET_PASSWORD

The password you specified when downloading the wallet from the OCI Console. This is used to configure JKS (Java KeyStore) authentication for the JDBC driver.

| Field | Value |
|---|---|
| **Name** | `WALLET_PASSWORD` |
| **Secret** | *(your wallet download password)* |

### Summary of Required Secrets

| Secret Name | Description | Example |
|---|---|---|
| `ORACLE_WALLET_BASE64` | Base64-encoded wallet ZIP | *(long base64 string)* |
| `DB_USERNAME` | Database deployment user | `LIQUIBASE_DEPLOYER` |
| `DB_PASSWORD` | Deployment user password | *(your password)* |
| `WALLET_PASSWORD` | Wallet download password | *(your wallet password)* |

---

## Updating the Oracle Wallet

Oracle Autonomous Database wallets may need to be updated when:
- The wallet expires (default rotation policy)
- The database is moved or reconfigured
- You rotate wallet credentials for security
- OCI networking changes affect the connection endpoints

### Steps to Update the Wallet

1. **Download a new wallet** from OCI Console:
   - Navigate to **Oracle Cloud Console → Autonomous Database → your database**
   - Click **DB Connection**
   - Click **Download Wallet**
   - Enter a password and click **Download**
   - Save the ZIP file locally

2. **Re-encode the wallet**:
   ```bash
   base64 -w 0 /path/to/new/Wallet_OracleTransDB.zip > wallet_base64.txt
   ```

3. **Update the GitHub Secret**:
   - Go to **Settings → Secrets and variables → Actions**
   - Find `ORACLE_WALLET_BASE64` and click **Update**
   - Paste the new base64 content
   - Click **Update secret**

4. **Update the wallet password** (if changed):
   - Find `WALLET_PASSWORD` and click **Update**
   - Enter the new wallet download password
   - Click **Update secret**

5. **Clean up**:
   ```bash
   rm wallet_base64.txt
   rm /path/to/new/Wallet_OracleTransDB.zip
   ```

6. **Trigger a deployment** to verify the new wallet works:
   - Push a commit to the `main` branch, or
   - Manually re-run the last workflow in the Actions tab

---

## GitHub Actions CI/CD Pipeline

The workflow file is located at `.github/workflows/liquibase-deploy.yml`.

### Trigger

The pipeline runs automatically on every **push to the `main` branch**.

### Pipeline Steps

| Step | Action | Description |
|---|---|---|
| 1 | **Checkout** | Clones the repository |
| 2 | **Decode Wallet** | Restores the Oracle Wallet from `ORACLE_WALLET_BASE64` secret |
| 3 | **Configure ojdbc.properties** | Switches from SSO to JKS authentication mode for JDBC compatibility |
| 4 | **Configure sqlnet.ora** | Points `WALLET_LOCATION` to the extracted wallet directory |
| 5 | **Setup Liquibase** | Installs Liquibase Community Edition via `liquibase/setup-liquibase@v2` |
| 6 | **Validate** | Runs `liquibase validate` to check changelog XML syntax |
| 7 | **Preview** | Runs `liquibase update-sql` to show what SQL will be executed (dry run) |
| 8 | **Deploy** | Runs `liquibase update` to apply pending changes to the database |
| 9 | **Summary** | Prints deployment confirmation |

### Viewing Pipeline Results

1. Go to your GitHub repository → **Actions** tab
2. Click on the latest workflow run
3. Expand each step to see detailed logs
4. The **Preview** step shows the exact SQL that was executed
5. The **Deploy** step confirms successful application

---

## Liquibase Tracking Tables

Liquibase creates two tracking tables to manage deployment state:

| Table | Purpose |
|---|---|
| `DATABASECHANGELOG` | Records every changeset that has been applied, including ID, author, filename, date, and checksum |
| `DATABASECHANGELOGLOCK` | Prevents concurrent deployments by locking during execution |

### Where Are They Stored?

These tables are created in the **`LIQUIBASE_DEPLOYER`** schema (not in `HR`). This keeps deployment metadata separate from the application schema.

This is configured via the `liquibaseSchemaName` property:

```properties
# In liquibase.properties
liquibaseSchemaName=LIQUIBASE_DEPLOYER
```

### Querying Deployment History

```sql
-- Connect as LIQUIBASE_DEPLOYER or ADMIN
SELECT id, author, filename, dateexecuted, exectype
FROM LIQUIBASE_DEPLOYER.DATABASECHANGELOG
ORDER BY orderexecuted;
```

---

## How Changelogs Are Organized

The master changelog (`db/changelog/db.changelog-master.xml`) includes sub-changelogs in **dependency order**:

```
db.changelog-master.xml
  ├── 001-sequences.xml          ← No dependencies
  ├── 002-tables.xml             ← Depends on sequences (for defaults)
  ├── 003-deferred-constraints.xml ← Circular FKs (DEPT ↔ EMP)
  ├── 004-views.xml              ← Depends on tables
  ├── 005-procedures.xml         ← Depends on tables
  ├── 006-functions.xml          ← Standalone
  └── 007-triggers.xml           ← Depends on procedures + tables
```

### Object Types and Changeset Strategy

| Object Type | `runOnChange` | `endDelimiter` | Rationale |
|---|---|---|---|
| **Sequences** | `false` | `;` (default) | Non-replaceable — use new changesets for modifications |
| **Tables** | `false` | `;` (default) | Non-replaceable — use ALTER TABLE in new changesets |
| **Views** | `true` | N/A | Replaceable via `CREATE OR REPLACE` |
| **Procedures** | `true` | `/` | Replaceable; PL/SQL uses `/` terminator |
| **Functions** | `true` | `/` | Replaceable; PL/SQL uses `/` terminator |
| **Triggers** | `true` | `/` | Replaceable; PL/SQL uses `/` terminator |

> **`runOnChange=true`**: Liquibase re-executes the changeset if the file content changes. This is ideal for replaceable objects like views and stored procedures where `CREATE OR REPLACE` is safe to re-run.

---

## Adding New Database Changes

### Adding a New Table

1. Create the SQL file:
   ```bash
   # Create TABLES/MY_NEW_TABLE.sql
   cat > TABLES/MY_NEW_TABLE.sql << 'EOF'
   CREATE TABLE "HR"."MY_NEW_TABLE"
   (
     "ID"          NUMBER       NOT NULL,
     "NAME"        VARCHAR2(100),
     "CREATED_AT"  TIMESTAMP    DEFAULT SYSTIMESTAMP,
     CONSTRAINT "MY_NEW_TABLE_PK" PRIMARY KEY ("ID")
   );
   EOF
   ```

2. Add a new changeset to `db/changelog/002-tables.xml`:
   ```xml
   <changeSet id="create-table-my-new-table" author="your-name">
       <comment>Create MY_NEW_TABLE</comment>
       <sqlFile path="TABLES/MY_NEW_TABLE.sql"
                relativeToChangelogFile="false"
                splitStatements="true"
                stripComments="false"/>
   </changeSet>
   ```

3. Commit and push to `main`:
   ```bash
   git add TABLES/MY_NEW_TABLE.sql db/changelog/002-tables.xml
   git commit -m "feat: add MY_NEW_TABLE"
   git push origin main
   ```

### Modifying an Existing Table

> ⚠️ **Never modify** a changeset that has already been deployed. Liquibase tracks checksums — modifying an applied changeset will cause a checksum mismatch error.

Instead, create a **new changeset**:

1. Create a new SQL file (e.g., `TABLES/ALTER_MY_NEW_TABLE_ADD_EMAIL.sql`):
   ```sql
   ALTER TABLE "HR"."MY_NEW_TABLE" ADD ("EMAIL" VARCHAR2(255));
   ```

2. Add a new changeset to `002-tables.xml` (at the end):
   ```xml
   <changeSet id="alter-my-new-table-add-email" author="your-name">
       <comment>Add EMAIL column to MY_NEW_TABLE</comment>
       <sqlFile path="TABLES/ALTER_MY_NEW_TABLE_ADD_EMAIL.sql"
                relativeToChangelogFile="false"
                splitStatements="true"
                stripComments="false"/>
   </changeSet>
   ```

### Modifying a View or Procedure

For **replaceable objects** (views, procedures, functions, triggers), simply edit the SQL file directly. Because the changeset uses `runOnChange="true"`, Liquibase will detect the file change and re-execute it.

```bash
# Edit the view
vim VIEWS/EMP_DETAILS_VIEW.sql

# Commit and push
git add VIEWS/EMP_DETAILS_VIEW.sql
git commit -m "feat: update EMP_DETAILS_VIEW with new column"
git push origin main
```

---

## Running Liquibase Locally

For local development and testing, you can run Liquibase directly on your machine.

### 1. Install Liquibase

```bash
# Using SDKMAN (recommended)
sdk install liquibase

# Or download from https://www.liquibase.com/download
# Extract and add to PATH
```

### 2. Set Up the Wallet Locally

```bash
# Create a local wallet directory
mkdir -p ./wallet

# Copy wallet files (from your downloaded wallet)
cp /path/to/Wallet_OracleTransDB/* ./wallet/

# Set TNS_ADMIN
export TNS_ADMIN=$(pwd)/wallet
```

### 3. Configure Local Properties

Create a file `liquibase.local.properties` (this is git-ignored):

```properties
changeLogFile=db/changelog/db.changelog-master.xml
url=jdbc:oracle:thin:@oracletransdb_low?TNS_ADMIN=./wallet
driver=oracle.jdbc.OracleDriver
username=LIQUIBASE_DEPLOYER
password=<your_password>
defaultSchemaName=HR
liquibaseSchemaName=LIQUIBASE_DEPLOYER
```

### 4. Run Liquibase Commands

```bash
# Validate changelog syntax
liquibase --defaults-file=liquibase.local.properties validate

# Preview changes without applying (dry run)
liquibase --defaults-file=liquibase.local.properties update-sql

# Apply changes
liquibase --defaults-file=liquibase.local.properties update

# Check deployment status
liquibase --defaults-file=liquibase.local.properties status

# Rollback last N changes (if rollback is configured)
liquibase --defaults-file=liquibase.local.properties rollback-count 1
```

---

## Troubleshooting

### 1. Wallet Errors

**Error**: `IO Error: could not resolve the connect identifier`

**Cause**: `TNS_ADMIN` is not set or points to the wrong directory.

**Fix**:
```bash
# Verify TNS_ADMIN
echo $TNS_ADMIN
ls -la $TNS_ADMIN/tnsnames.ora

# Ensure the TNS alias matches
grep "oracletransdb_low" $TNS_ADMIN/tnsnames.ora
```

---

### 2. JKS / SSL Errors

**Error**: `java.security.KeyStoreException` or `SSLHandshakeException`

**Cause**: `ojdbc.properties` is not configured for JKS mode, or the wallet password is incorrect.

**Fix**: Ensure `ojdbc.properties` has the JKS properties uncommented:
```properties
# Comment out SSO wallet:
# oracle.net.wallet_location=(SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY=${TNS_ADMIN})))

# Uncomment JKS:
javax.net.ssl.trustStore=${TNS_ADMIN}/truststore.jks
javax.net.ssl.trustStorePassword=<wallet_password>
javax.net.ssl.keyStore=${TNS_ADMIN}/keystore.jks
javax.net.ssl.keyStorePassword=<wallet_password>
```

---

### 3. Permission Denied

**Error**: `ORA-01031: insufficient privileges`

**Cause**: `LIQUIBASE_DEPLOYER` is missing required grants.

**Fix**: Run the grants listed in [Database User Setup](#database-user-setup--liquibase_deployer) as ADMIN.

---

### 4. Checksum Mismatch

**Error**: `Validation Failed: X changesets check sum`

**Cause**: A previously deployed changeset file was modified.

**Fix**:
```sql
-- Option 1: Clear the checksum (re-records it on next run)
-- Run via SQL as LIQUIBASE_DEPLOYER:
UPDATE LIQUIBASE_DEPLOYER.DATABASECHANGELOG
SET MD5SUM = NULL
WHERE ID = '<changeset-id>';
COMMIT;
```

Or run:
```bash
liquibase clear-checksums
```

---

### 5. GitHub Actions Wallet Decode Fails

**Error**: `base64: invalid input` in the workflow

**Cause**: The base64 secret was not encoded correctly (may contain line breaks).

**Fix**: Re-encode with `-w 0` (no line wrapping):
```bash
base64 -w 0 /path/to/Wallet_OracleTransDB.zip > wallet_base64.txt
```

---

### 6. Object Already Exists

**Error**: `ORA-00955: name is already used by an existing object`

**Cause**: Trying to create an object that already exists in the database.

**Fix**: This typically means the changeset was partially applied. You can:
1. Drop the object manually and re-run
2. Mark the changeset as already executed:
   ```bash
   liquibase changelog-sync-to-tag <tag>
   ```

---

## License

This project is provided as a demonstrator for automated Oracle database deployment using Liquibase Community Edition.
