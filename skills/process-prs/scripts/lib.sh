# shellcheck shell=bash
# lib.sh — shared helpers sourced by the process-prs scripts. Not executable.
# Callers set LIB_TOOL to their own name before sourcing so every message and
# die() carries the right prefix. These validators guard the same values across
# scripts that share persisted state (handoff files, snapshots, queue rows), so
# they must stay identical — never fork a local copy back into a script.

LIB_TAB=$(printf '\t')

die() {
  printf '%s: %s\n' "${LIB_TOOL:-good-fellow}" "$*" >&2
  exit 64
}

validate_target() {
  case "$1" in ''|*[!A-Za-z0-9_.-]*) die 'invalid owner' ;; esac
  case "$2" in ''|*[!A-Za-z0-9_.-]*) die 'invalid repository' ;; esac
  case "$3" in ''|0|*[!0-9]*) die 'invalid pull request number' ;; esac
}

validate_regular_file() {
  [ -f "$1" ] && [ ! -L "$1" ] || die "$2 must be a regular, non-symlink file"
}

validate_oid() {
  case "$1" in ''|*[!0-9a-f]*) die "$2 is not a 40-character SHA" ;; esac
  [ "${#1}" -eq 40 ] || die "$2 is not a 40-character SHA"
}

# Validate and dedupe the 5-field TSV inventory/queue row wire format
# (repo_api_url, number, author, html_url, draft). Sole owner of the contract:
# pr-inventory emits it, pr-handoff queue-rows emits it, pr-queue order consumes
# it. Exits 64 on a malformed row or two conflicting rows for one key. Input
# must arrive pre-sorted so duplicate keys are adjacent.
validate_dedupe_rows() {
  LC_ALL=C awk -F "$LIB_TAB" -v tool="${LIB_TOOL:-good-fellow}" '
    NF {
      if (NF != 5 || $2 !~ /^[1-9][0-9]*$/ || ($5 != "true" && $5 != "false")) {
        print tool ": malformed inventory row" > "/dev/stderr"
        exit 64
      }
      key=$1 FS $2
      if (key == previous_key) {
        if ($0 != previous_row) {
          print tool ": conflicting inventory rows for " key > "/dev/stderr"
          exit 64
        }
        next
      }
      print
      previous_key=key
      previous_row=$0
    }
  '
}
