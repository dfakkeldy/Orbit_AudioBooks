#!/bin/bash
set -euo pipefail

# =============================================================================
# generate_architecture.sh
# =============================================================================
# Scans the project's three Xcode targets and writes a directory tree into
# ARCHITECTURE.md. Build artifacts, asset catalogs, and media files are
# excluded so the output focuses on source code and configuration.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="$REPO_ROOT/ARCHITECTURE.md"

EXCLUDE_DIRS=(
    "-not" "-path" "*/.build/*"
    "-not" "-path" "*/DerivedData/*"
    "-not" "-path" "*/.swiftpm/*"
    "-not" "-path" "*/xcuserdata/*"
    "-not" "-path" "*/xcshareddata/*"
    "-not" "-path" "*/Preview Content/*"
    "-not" "-path" "*/Assets.xcassets/*"
    "-not" "-path" "*/*.xcassets/*"
)

EXCLUDE_NAMES=(
    "-not" "-name" ".DS_Store"
    "-not" "-name" "*.png"
    "-not" "-name" "*.jpg"
    "-not" "-name" "*.jpeg"
    "-not" "-name" "*.heic"
    "-not" "-name" "*.heif"
    "-not" "-name" "*.mp3"
    "-not" "-name" "*.m4a"
    "-not" "-name" "*.m4b"
    "-not" "-name" "*.wav"
    "-not" "-name" "*.gif"
    "-not" "-name" "*.webp"
    "-not" "-name" "*.ttf"
    "-not" "-name" "*.otf"
    "-not" "-name" "UserInterfaceState.xcuserstate"
    "-not" "-name" "IDEWorkspaceChecks.plist"
)

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# -----------------------------------------------------------------------------
# Header
# -----------------------------------------------------------------------------
cat > "$OUTPUT" << 'HEADER'
# Architecture Overview

<!-- ⚠️  AUTO-GENERATED — do not edit directly. -->
<!-- Regenerate with: `make architecture`                        -->

HEADER

printf "**Last generated:** %s\n\n" "$TIMESTAMP" >> "$OUTPUT"

cat >> "$OUTPUT" << 'INTRO'
This document maps the source-tree layout of the three Xcode targets in the
Orbit Audiobooks project. Folders are shown in the order returned by the
filesystem; only source, configuration, and metadata files are included
(build artifacts, asset catalogs, and media files are filtered out).

---

INTRO

# -----------------------------------------------------------------------------
# Per-target tree helper
# -----------------------------------------------------------------------------
generate_tree() {
    local label="$1"
    local path="$2"

    printf "## %s\n\n" "$label" >> "$OUTPUT"
    printf '```\n' >> "$OUTPUT"

    if [[ -d "$path" ]]; then
        (
            cd "$path"
            find . -type f \
                "${EXCLUDE_DIRS[@]}" \
                "${EXCLUDE_NAMES[@]}" \
                -print \
                | sort \
                | sed 's|^\./||'
        ) >> "$OUTPUT"
    else
        echo "(directory not found — skipped)" >> "$OUTPUT"
    fi

    printf '```\n\n' >> "$OUTPUT"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
generate_tree "OrbitAudioBooks (iOS)"       "$REPO_ROOT/OrbitAudioBooks"
generate_tree "Orbit Audiobooks macOS"       "$REPO_ROOT/Orbit Audiobooks macOS"
generate_tree "Orbit Audiobooks Watch App"   "$REPO_ROOT/Orbit Audiobooks Watch App"

echo "ARCHITECTURE.md generated at $OUTPUT"
