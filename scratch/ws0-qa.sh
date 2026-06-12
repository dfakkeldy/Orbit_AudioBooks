#!/bin/bash
# WS0 Part-5 scripted QA: play -> heartbeats -> seek split -> force-kill -> relaunch,
# then assert playback_event rows + migration chain in the real app-group sqlite.
set -uo pipefail
WT="/Users/dfakkeldy/Developer/Echo/.claude/worktrees/testflight"
BUNDLE="com.echo.audiobooks"
GROUP_ID="group.com.echo.audiobooks"

UDID=$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone 17 \(' | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -z "$UDID" ] && { echo "FATAL: iPhone 17 simulator not found"; exit 1; }
echo "Device: $UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

APP_PATH=$(cd "$WT" && xcodebuild -scheme Echo -destination "platform=iOS Simulator,name=iPhone 17" -showBuildSettings build 2>/dev/null | awk -F ' = ' '/ BUILT_PRODUCTS_DIR/{bp=$2} / FULL_PRODUCT_NAME/{fp=$2} END{print bp "/" fp}')
[ ! -d "$APP_PATH" ] && { echo "FATAL: app not found at $APP_PATH"; exit 1; }
echo "App: $APP_PATH"

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl install "$UDID" "$APP_PATH" || { echo "FATAL: install failed"; exit 1; }

GROUP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" "$GROUP_ID")
echo "Group container: $GROUP"
rm -f "$GROUP/echo.sqlite" "$GROUP/echo.sqlite-wal" "$GROUP/echo.sqlite-shm"

echo "--- T0: launch (seeds BIFF.m4b, restores sample w/o autoplay)"
xcrun simctl launch "$UDID" "$BUNDLE" || { echo "FATAL: launch failed"; exit 1; }
sleep 10

echo "--- T1: deep link play"
xcrun simctl openurl "$UDID" "echoaudio://play"
sleep 75   # >2 heartbeat ticks extend the open row

echo "--- T2: deep link seek to 300s (closes segment at pre-seek pos, reopens at 300)"
xcrun simctl openurl "$UDID" "echoaudio://play?time=300"
sleep 25

echo "--- T3: force-kill with open segment"
xcrun simctl terminate "$UDID" "$BUNDLE"
sleep 3

echo "--- T4: relaunch (must boot clean against migrated DB)"
xcrun simctl launch "$UDID" "$BUNDLE" || { echo "FATAL: relaunch failed"; exit 1; }
sleep 10
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
sleep 2

DB="$GROUP/echo.sqlite"
echo "=== MIGRATIONS (expect ...v13_epub_toc_entries, v14_capture_and_context, each once) ==="
sqlite3 "$DB" "SELECT identifier FROM grdb_migrations ORDER BY rowid;"
echo "=== V14 OBJECTS ==="
sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name IN ('session_location','epub_toc_entry','idx_playback_event_started_at');"
sqlite3 "$DB" "SELECT 'bookmark_cols: ' || group_concat(name) FROM pragma_table_info('bookmark') WHERE name IN ('latitude','longitude','place_name');"
sqlite3 "$DB" "SELECT 'note_cols: ' || group_concat(name) FROM pragma_table_info('note') WHERE name IN ('is_global','voice_memo_path');"
echo "=== PLAYBACK SEGMENTS ==="
sqlite3 -header -column "$DB" "SELECT id, started_at, ended_at, round(start_position,1) AS sp, round(end_position,1) AS ep, speed, event_type, source FROM playback_event ORDER BY id;"
echo "=== ASSERTIONS ==="
sqlite3 "$DB" "
SELECT CASE WHEN (SELECT COUNT(*) FROM grdb_migrations WHERE identifier='v14_capture_and_context')=1 THEN 'PASS' ELSE 'FAIL' END || ': v14 applied exactly once';
SELECT CASE WHEN (SELECT COUNT(*) FROM grdb_migrations WHERE identifier='v13_epub_toc_entries')=1 THEN 'PASS' ELSE 'FAIL' END || ': v13 applied exactly once';
SELECT CASE WHEN (SELECT COUNT(*) FROM playback_event)=2 THEN 'PASS' ELSE 'FAIL ('||(SELECT COUNT(*) FROM playback_event)||' rows)' END || ': exactly 2 segments (seek split)';
SELECT CASE WHEN (SELECT end_position-start_position FROM playback_event ORDER BY id LIMIT 1) BETWEEN 60 AND 90 THEN 'PASS' ELSE 'FAIL' END || ': segment-1 duration ~75s (heartbeat extended, closed at pre-seek)';
SELECT CASE WHEN (SELECT start_position FROM playback_event ORDER BY id DESC LIMIT 1) BETWEEN 299 AND 301 THEN 'PASS' ELSE 'FAIL' END || ': segment-2 opens at seek target 300';
SELECT CASE WHEN (SELECT end_position FROM playback_event ORDER BY id DESC LIMIT 1) >= 300 AND (SELECT ended_at >= started_at FROM playback_event ORDER BY id DESC LIMIT 1) THEN 'PASS' ELSE 'FAIL' END || ': force-killed segment self-consistent (<=30s loss by design, no sweep needed)';
SELECT CASE WHEN (SELECT COUNT(*) FROM playback_event WHERE end_position < start_position OR ended_at < started_at)=0 THEN 'PASS' ELSE 'FAIL' END || ': no inverted segments';
"
echo "=== DONE ==="
