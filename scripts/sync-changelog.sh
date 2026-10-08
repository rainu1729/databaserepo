#!/usr/bin/env bash
# ==============================================================================
# sync-changelog.sh
# 
# Automatically detects SQL files for database objects and registers missing
# changesets in the appropriate Liquibase XML changelogs.
#
# Usage:
#   ./scripts/sync-changelog.sh --staged   # Scan only staged new SQL files (default in pre-commit)
#   ./scripts/sync-changelog.sh --all      # Scan all SQL files in object directories
#   ./scripts/sync-changelog.sh --check    # Check for unmapped files without modifying (for CI)
# ==============================================================================

set -euo pipefail

# Ensure script runs from the repository root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

MODE="${1:---staged}"
AUTHOR="${LIQUIBASE_AUTHOR:-liquibase-deployer}"

declare -A CHANGELOG_MAP=(
  ["TABLES"]="db/changelog/002-tables.xml"
  ["VIEWS"]="db/changelog/004-views.xml"
  ["PROCEDURES"]="db/changelog/005-procedures.xml"
  ["FUNCTIONS"]="db/changelog/006-functions.xml"
  ["TRIGGERS"]="db/changelog/007-triggers.xml"
  ["SEQUENCES"]="db/changelog/001-sequences.xml"
  ["PACKAGES"]="db/changelog/008-packages.xml"
)

# Function to ensure a changelog XML exists (creates if missing, e.g., PACKAGES)
ensure_changelog_exists() {
  local dir="$1"
  local xml_path="${CHANGELOG_MAP[$dir]}"

  if [ ! -f "$xml_path" ]; then
    echo "Creating missing changelog: $xml_path"
    mkdir -p "$(dirname "$xml_path")"
    cat > "$xml_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-latest.xsd">

</databaseChangeLog>
EOF
    # If adding 008-packages.xml, also register in db.changelog-master.xml if not present
    local master_xml="db/changelog/db.changelog-master.xml"
    if [ -f "$master_xml" ] && ! grep -q "$xml_path" "$master_xml"; then
      awk -v inc="    <include file=\"$xml_path\"/>" '
        /<\/databaseChangeLog>/ { print inc; print ""; }
        { print }
      ' "$master_xml" > "${master_xml}.tmp" && mv "${master_xml}.tmp" "$master_xml"
      if [ "$MODE" = "--staged" ]; then
        git add "$master_xml"
      fi
    fi
  fi
}

# Generate changeset XML block according to object type
generate_changeset() {
  local dir="$1"
  local file="$2"
  local base
  base="$(basename "$file" .sql)"
  local slug
  slug="$(echo "$base" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"

  case "$dir" in
    TABLES)
      cat <<EOF
    <changeSet id="create-table-${slug}" author="${AUTHOR}">
        <comment>Create ${base} table</comment>
        <sqlFile path="${file}" relativeToChangelogFile="false" splitStatements="true" stripComments="true"/>
    </changeSet>
EOF
      ;;
    VIEWS)
      cat <<EOF
    <changeSet id="create-view-${slug}" author="${AUTHOR}" runOnChange="true">
        <comment>Create or replace ${base} (replaceable object)</comment>
        <sqlFile path="${file}" relativeToChangelogFile="false" splitStatements="false" stripComments="false"/>
    </changeSet>
EOF
      ;;
    PROCEDURES)
      cat <<EOF
    <changeSet id="create-procedure-${slug}" author="${AUTHOR}" runOnChange="true">
        <comment>Create or replace ${base} procedure</comment>
        <sqlFile path="${file}" relativeToChangelogFile="false" splitStatements="true" endDelimiter="/" stripComments="false"/>
    </changeSet>
EOF
      ;;
    FUNCTIONS)
      cat <<EOF
    <changeSet id="create-function-${slug}" author="${AUTHOR}" runOnChange="true">
        <comment>Create or replace ${base} function</comment>
        <sqlFile path="${file}" relativeToChangelogFile="false" splitStatements="true" endDelimiter="/" stripComments="false"/>
    </changeSet>
EOF
      ;;
    TRIGGERS)
      cat <<EOF
    <changeSet id="create-trigger-${slug}" author="${AUTHOR}" runOnChange="true">
        <comment>Create or replace ${base} trigger</comment>
        <sqlFile path="${file}" relativeToChangelogFile="false" splitStatements="true" endDelimiter="/" stripComments="false"/>
    </changeSet>
EOF
      ;;
    PACKAGES)
      cat <<EOF
    <changeSet id="create-package-${slug}" author="${AUTHOR}" runOnChange="true">
        <comment>Create or replace ${base} package</comment>
        <sqlFile path="${file}" relativeToChangelogFile="false" splitStatements="true" endDelimiter="/" stripComments="false"/>
    </changeSet>
EOF
      ;;
    SEQUENCES)
      cat <<EOF
    <changeSet id="create-${slug}" author="${AUTHOR}">
        <comment>Create ${base} sequence</comment>
        <sqlFile path="${file}" relativeToChangelogFile="false" stripComments="true"/>
    </changeSet>
EOF
      ;;
    *)
      return 1
      ;;
  esac
}

# Collect files to check
FILES_TO_CHECK=()

if [ "$MODE" = "--staged" ]; then
  # Only newly added files staged in git
  while IFS= read -r f; do
    [ -n "$f" ] && FILES_TO_CHECK+=("$f")
  done < <(git diff --cached --name-only --diff-filter=A | grep -E '\.sql$' || true)
elif [ "$MODE" = "--all" ] || [ "$MODE" = "--check" ]; then
  # Scan all known directories for sql files
  for d in "${!CHANGELOG_MAP[@]}"; do
    if [ -d "$d" ]; then
      while IFS= read -r f; do
        [ -n "$f" ] && FILES_TO_CHECK+=("$f")
      done < <(find "$d" -maxdepth 1 -type f -name "*.sql" | sort)
    fi
  done
else
  echo "Unknown mode: $MODE"
  echo "Usage: $0 [--staged|--all|--check]"
  exit 1
fi

if [ ${#FILES_TO_CHECK[@]} -eq 0 ]; then
  exit 0
fi

CHANGES_MADE=0
MISSING_COUNT=0

for file in "${FILES_TO_CHECK[@]}"; do
  dir="$(dirname "$file")"
  target_xml="${CHANGELOG_MAP[$dir]:-}"

  # Ignore files not in mapped directories or special files like DEFERRED_FOREIGN_KEYS
  if [ -z "$target_xml" ]; then
    continue
  fi
  if [[ "$(basename "$file")" == "DEFERRED_FOREIGN_KEYS.sql" ]]; then
    continue
  fi

  # Check if changelog already contains reference to this file
  if [ -f "$target_xml" ] && grep -Fq "path=\"$file\"" "$target_xml"; then
    continue
  fi

  if [ "$MODE" = "--check" ]; then
    echo "❌ Unregistered SQL file: $file (missing from $target_xml)"
    MISSING_COUNT=$((MISSING_COUNT + 1))
    continue
  fi

  ensure_changelog_exists "$dir"

  changeset_xml="$(generate_changeset "$dir" "$file")"

  echo "⚡ Auto-registering $file into $target_xml..."

  # Insert right before </databaseChangeLog>
  awk -v cs="$changeset_xml" '
    /<\/databaseChangeLog>/ {
      print cs;
      print "";
    }
    { print }
  ' "$target_xml" > "${target_xml}.tmp" && mv "${target_xml}.tmp" "$target_xml"

  CHANGES_MADE=1

  if [ "$MODE" = "--staged" ]; then
    git add "$target_xml"
  fi
done

if [ "$MODE" = "--check" ]; then
  if [ "$MISSING_COUNT" -gt 0 ]; then
    echo "Total unregistered files: $MISSING_COUNT"
    exit 1
  else
    echo "✔ All database object SQL files are registered in changelog XMLs."
    exit 0
  fi
fi

if [ "$CHANGES_MADE" -eq 1 ]; then
  echo "✔ Changelogs updated successfully."
fi

exit 0
