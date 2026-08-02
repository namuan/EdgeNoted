#!/bin/bash
set -euo pipefail

# backup-notes.sh — back up every Apple Notes note into a timestamped folder
# under ~/Documents/EdgeNoted Backup, mirroring the folder structure. Each note
# is saved as its raw HTML body (the most faithful restore format) with a
# manifest.tsv (folder, name, id, relative path) for restore/reference.
#
# ⚠️  PRIVACY / LOCAL-ONLY
# This backup contains your COMPLETE Apple Notes content in plaintext HTML,
# including any sensitive, private, or confidential notes. Treat the output
# folder like the Notes app itself:
#   - It is strictly local. Never commit, upload, sync, or share it.
#   - Do not place it inside a git repository (the script refuses to run there).
#   - Delete old backup-* folders when they are no longer needed.
# The script is read-only on Apple Notes; it only writes under the backup folder.
#
# Usage:  bash Scripts/backup-notes.sh   [optional: /path/to/backup/root]

BACKUP_ROOT="${1:-$HOME/Documents/EdgeNoted Backup}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Canonicalize the repo and the would-be backup root, then refuse to write
# inside the repository so a plaintext backup can never be committed by
# accident. This runs BEFORE anything is created, and the canonical paths
# prevent symlink-based bypasses.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# Resolve the physical path of BACKUP_ROOT even when it does not exist yet:
# canonicalize the nearest existing ancestor and append the remainder.
PROBE="$BACKUP_ROOT"
while [ ! -e "$PROBE" ] && [ "$PROBE" != "/" ]; do
    PROBE="$(dirname "$PROBE")"
done
ANCESTOR_REAL="$(cd "$PROBE" && pwd -P)"
REST="${BACKUP_ROOT#"$PROBE"}"
RESOLVED_ROOT="$ANCESTOR_REAL$REST"

case "$RESOLVED_ROOT" in
    "$REPO_ROOT"|"$REPO_ROOT"/*)
        echo "ERROR: refusing to back up inside the EdgeNoted repository ($RESOLVED_ROOT)." >&2
        echo "       The backup contains full note content and must stay outside the repo." >&2
        exit 1
        ;;
esac

mkdir -p "$BACKUP_ROOT"
BACKUP_DIR="$BACKUP_ROOT/backup-$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo "Backing up Apple Notes to: $BACKUP_DIR" >&2
echo "NOTE: this backup contains ALL of your note content in plaintext and is" >&2
echo "      LOCAL ONLY - never commit, upload, or share it." >&2

RESULT=$(osascript - "$BACKUP_DIR" <<'OSASCRIPT'
on safeName(theName)
    set oldDelims to text item delimiters of AppleScript
    set text item delimiters of AppleScript to {"/", ":", "\\", "|", tab}
    set pieces to every text item of theName
    set text item delimiters of AppleScript to "-"
    set theResult to pieces as text
    set text item delimiters of AppleScript to oldDelims
    if theResult is "" then return "untitled"
    return theResult
end safeName

on writeFile(thePath, theContent)
    do shell script "touch " & quoted form of thePath
    set fileRef to open for access (POSIX file thePath) with write permission
    write theContent to fileRef
    close access fileRef
end writeFile

on uniquePath(folderPath, baseName)
    set candidate to folderPath & "/" & baseName & ".html"
    set counter to 2
    repeat
        if (do shell script "test -e " & quoted form of candidate & "; echo $?") is "1" then return candidate
        set candidate to folderPath & "/" & baseName & "-" & counter & ".html"
        set counter to counter + 1
    end repeat
end uniquePath

property covered : ""
property manifest : ""
property noteCount : 0
property errorList : ""
property backupRoot : ""

on saveNote(n, folderPath)
    tell application "Notes"
        set noteID to id of n
        set noteName to name of n
        set noteBody to body of n
    end tell
    -- A note reported by both a parent folder and a nested folder must only
    -- be backed up once.
    if (offset of (noteID & linefeed) in covered) is not 0 then return
    set covered to covered & noteID & linefeed
    set candidate to uniquePath(folderPath, safeName(noteName))
    try
        writeFile(candidate, noteBody)
        set manifest to manifest & folderPath & tab & noteName & tab & noteID & tab & candidate & linefeed
        set noteCount to noteCount + 1
    on error errMsg
        set errorList to errorList & noteName & " (" & noteID & "): " & errMsg & linefeed
    end try
end saveNote

on walk(f, pathPrefix)
    tell application "Notes"
        set folderName to name of f
        set theNotes to notes of f
        set subfolders to folders of f
    end tell
    set safeFolder to safeName(folderName)
    set folderPath to pathPrefix & "/" & safeFolder
    do shell script "mkdir -p " & quoted form of folderPath
    repeat with n in theNotes
        my saveNote(n, folderPath)
    end repeat
    repeat with sub in subfolders
        my walk(sub, folderPath)
    end repeat
end walk

on run argv
    set backupRoot to item 1 of argv
    tell application "Notes"
        repeat with f in (folders)
            my walk(f, backupRoot)
        end repeat
        -- Notes not reachable through any folder (e.g. at the account root).
        set noFolderPath to backupRoot & "/No Folder"
        repeat with n in (notes)
            set noteID to id of n
            if (offset of (noteID & linefeed) in covered) is 0 then
                do shell script "mkdir -p " & quoted form of noFolderPath
                my saveNote(n, noFolderPath)
            end if
        end repeat
    end tell

    writeFile(backupRoot & "/manifest.tsv", "folder" & tab & "name" & tab & "id" & tab & "file" & linefeed & manifest)
    writeFile(backupRoot & "/backup-errors.txt", errorList)
    set errCount to (count of paragraphs of errorList)
    if errCount is 1 then set errCount to 0
    return "notes=" & (noteCount as text) & " errors=" & (errCount as text)
end run
OSASCRIPT
)

echo "Result: $RESULT"
echo "Backup complete."
