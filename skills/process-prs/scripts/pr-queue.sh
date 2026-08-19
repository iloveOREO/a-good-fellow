#!/usr/bin/env bash
# Rotate the complete PR inventory after the last completed item and persist the
# cursor atomically. A crash before advance retries the same item next tick.
set -Eeuo pipefail

QUEUE_LIB="$(CDPATH='' cd "$(dirname "$0")" && pwd -P)/lib.sh"
[ -f "$QUEUE_LIB" ] && [ ! -L "$QUEUE_LIB" ] || { printf 'pr-queue: lib.sh is missing or unsafe\n' >&2; exit 64; }
LIB_TOOL='pr-queue'
. "$QUEUE_LIB"

STATE_DIR="${GOOD_FELLOW_STATE_DIR:-$HOME/.good-fellow}"
CURSOR_FILE="$STATE_DIR/process-prs.cursor"
TAB=$(printf '\t')

usage() {
  printf 'usage: pr-queue.sh order INVENTORY_FILE [PRIORITY_REPO_URL PRIORITY_NUMBER] | advance REPOSITORY_API_URL NUMBER | show\n' >&2
  exit 64
}

# URL-grammar twin of notification-receipts.sh validate_key: both key files in
# the shared state dir and the sweeps reconcile against each other, so the
# accepted key space must match. Update the twin together.
validate_key() {
  local repo=$1 number=$2 rest owner name
  case "$repo" in https://api.github.com/repos/*/*) ;; *) printf 'pr-queue: invalid repository URL\n' >&2; return 64 ;; esac
  rest=${repo#https://api.github.com/repos/}
  owner=${rest%%/*}
  name=${rest#*/}
  case "$owner" in ''|*[!A-Za-z0-9_.-]*) printf 'pr-queue: invalid owner\n' >&2; return 64 ;; esac
  case "$name" in ''|*/*|*[!A-Za-z0-9_.-]*) printf 'pr-queue: invalid repository\n' >&2; return 64 ;; esac
  case "$number" in ''|0|*[!0-9]*) printf 'pr-queue: invalid PR number\n' >&2; return 64 ;; esac
}

mode=${1:-}
case "$mode" in
  order)
    [ "$#" -eq 2 ] || [ "$#" -eq 4 ] || usage
    inventory=$2
    [ -f "$inventory" ] && [ ! -L "$inventory" ] || { printf 'pr-queue: inventory must be a regular file\n' >&2; exit 64; }
    cursor_repo=''
    cursor_number=''
    priority_repo=''
    priority_number=''
    if [ "$#" -eq 4 ]; then
      validate_key "$3" "$4"
      priority_repo=$3
      priority_number=$4
    fi
    if [ -e "$CURSOR_FILE" ] || [ -L "$CURSOR_FILE" ]; then
      cursor_valid=true
      if [ -f "$CURSOR_FILE" ] && [ ! -L "$CURSOR_FILE" ]; then
        IFS=$'\t' read -r cursor_repo cursor_number extra < "$CURSOR_FILE" || true
        [ -z "${extra:-}" ] || cursor_valid=false
        if [ "$cursor_valid" = true ] && ! validate_key "$cursor_repo" "$cursor_number" >/dev/null 2>&1; then
          cursor_valid=false
        fi
      else
        cursor_valid=false
      fi
      if [ "$cursor_valid" != true ]; then
        printf 'pr-queue: ignoring malformed cursor; restarting deterministic order\n' >&2
        cursor_repo=''
        cursor_number=''
      fi
    fi
    LC_ALL=C sort -t "$TAB" -k1,1 -k2,2n "$inventory" | validate_dedupe_rows | awk -F "$TAB" -v cr="$cursor_repo" -v cn="$cursor_number" -v pr="$priority_repo" -v pn="$priority_number" '
      function key(repo, number) { return repo "\t" sprintf("%020d", number) }
      NF {
        rows[++count]=$0
        keys[count]=key($1,$2)
      }
      END {
        if (count == 0) exit 0
        if (pr != "") {
          priority=key(pr,pn)
          priority_index=0
          for (i=1; i<=count; i++) if (keys[i] == priority) { priority_index=i; break }
          if (priority_index == 0) {
            print "pr-queue: priority handoff is missing from inventory" > "/dev/stderr"
            exit 64
          }
          print rows[priority_index]
          for (offset=1; offset<count; offset++) {
            idx=((priority_index-1+offset) % count)+1
            print rows[idx]
          }
          exit 0
        }
        cursor=(cr == "" ? "" : key(cr,cn))
        start=1
        if (cursor != "") {
          exact=0
          for (i=1; i<=count; i++) if (keys[i] == cursor) { start=(i % count)+1; exact=1; break }
          if (!exact) {
            start=1
            for (i=1; i<=count; i++) if (keys[i] > cursor) { start=i; break }
          }
        }
        for (offset=0; offset<count; offset++) {
          idx=((start-1+offset) % count)+1
          print rows[idx]
        }
      }
    '
    ;;
  advance)
    [ "$#" -eq 3 ] || usage
    validate_key "$2" "$3"
    mkdir -p "$STATE_DIR"
    umask 077
    tmp=$(mktemp "$STATE_DIR/process-prs.cursor.XXXXXX")
    printf '%s\t%s\n' "$2" "$3" > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$CURSOR_FILE"
    ;;
  show)
    [ "$#" -eq 1 ] || usage
    [ -f "$CURSOR_FILE" ] && cat "$CURSOR_FILE" || true
    ;;
  *) usage ;;
esac
