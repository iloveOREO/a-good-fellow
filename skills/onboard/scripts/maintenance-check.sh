#!/usr/bin/env bash
set -Eu

STATE_DIR="${GOOD_FELLOW_STATE_DIR:-$HOME/.good-fellow}"
BOOTSTRAP_REPO=${1:-}
INTERVAL_SECONDS="${GOOD_FELLOW_SYNC_INTERVAL_SECONDS:-172800}"
LAST_CHECK="$STATE_DIR/maintenance-last-check"
INSTRUCTION_CACHE="$STATE_DIR/instruction.md"
INSTRUCTION_BASELINE="$STATE_DIR/instruction.remote"
SOURCE_UPDATED="$STATE_DIR/maintenance-source-updated"
MANAGED_SOURCE="$STATE_DIR/source"

log() { printf 'maintenance: %s\n' "$*"; }
fail() { log "$*" >&2; exit 1; }
replace_from_remote() {
  replace_target=$1
  replace_tmp=$(mktemp "$STATE_DIR/.instruction-sync.XXXXXX") || return 1
  if install -m 600 "$remote_tmp" "$replace_tmp"; then
    mv -f "$replace_tmp" "$replace_target"
  else
    rm -f "$replace_tmp"
    return 1
  fi
}

case "$INTERVAL_SECONDS" in
  ''|0|0[0-9]*|*[!0-9]*) fail 'GOOD_FELLOW_SYNC_INTERVAL_SECONDS must be a positive integer' ;;
esac

mkdir -p "$STATE_DIR"
now=$(date +%s)
last=0
if [ -f "$LAST_CHECK" ]; then
  IFS= read -r last < "$LAST_CHECK" || last=0
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
fi

# A missing instruction cache is repaired immediately; otherwise stay entirely
# offline between due checks.
if [ -s "$INSTRUCTION_CACHE" ] && [ $((now - last)) -lt "$INTERVAL_SECONDS" ]; then
  log 'not due'
  exit 0
fi

remote_tmp=$(mktemp "${TMPDIR:-/tmp}/good-fellow-instruction.XXXXXX")
stamp_tmp=$(mktemp "$STATE_DIR/maintenance-last-check.XXXXXX")
cleanup() { rm -f "$remote_tmp" "$stamp_tmp"; }
trap cleanup EXIT HUP INT TERM

gist_ids=$(gh api /gists --paginate \
  --jq '.[] | select(.files["good-fellow-instruction.md"]) | .id') ||
  fail 'could not query the instruction gist; leaving the check due for retry'
GIST_ID=$(printf '%s\n' "$gist_ids" | sed -n '1p')

if [ -n "$GIST_ID" ]; then
  gh gist view "$GIST_ID" --filename good-fellow-instruction.md > "$remote_tmp" ||
    fail 'could not download the instruction gist; leaving the check due for retry'

  if [ ! -e "$INSTRUCTION_CACHE" ]; then
    replace_from_remote "$INSTRUCTION_CACHE"
    replace_from_remote "$INSTRUCTION_BASELINE"
    log 'restored missing instruction cache from gist'
  elif [ ! -e "$INSTRUCTION_BASELINE" ]; then
    if cmp -s "$INSTRUCTION_CACHE" "$remote_tmp"; then
      replace_from_remote "$INSTRUCTION_BASELINE"
      log 'initialized instruction sync baseline'
    else
      log 'instruction cache has no sync baseline and differs from gist; preserving local copy for manual /sync-instructions'
    fi
  elif cmp -s "$INSTRUCTION_CACHE" "$INSTRUCTION_BASELINE"; then
    if cmp -s "$remote_tmp" "$INSTRUCTION_BASELINE"; then
      log 'instruction gist unchanged'
    else
      replace_from_remote "$INSTRUCTION_CACHE"
      replace_from_remote "$INSTRUCTION_BASELINE"
      log 'instruction cache updated from gist'
    fi
  elif cmp -s "$remote_tmp" "$INSTRUCTION_BASELINE"; then
    log 'instruction cache has local-only edits; preserving it for manual /sync-instructions'
  else
    log 'instruction cache and gist both changed; preserving local copy for manual /sync-instructions'
  fi
else
  log 'instruction gist not found; preserving the current cache'
fi

rm -f "$SOURCE_UPDATED"
if [ -n "$BOOTSTRAP_REPO" ] && git -C "$BOOTSTRAP_REPO" rev-parse --git-dir >/dev/null 2>&1; then
  origin_url=$(git -C "$BOOTSTRAP_REPO" remote get-url origin 2>/dev/null || true)
  if [ -z "$origin_url" ]; then
    log 'bootstrap checkout has no origin; skipping repository sync'
  else
    if [ -e "$MANAGED_SOURCE" ] && [ ! -d "$MANAGED_SOURCE/.git" ]; then
      log 'managed source path exists but is not a Git checkout; preserving it'
    elif [ ! -d "$MANAGED_SOURCE/.git" ]; then
      source_tmp="$STATE_DIR/source.new.$$"
      if [ -e "$source_tmp" ]; then
        fail 'temporary managed source path already exists; leaving it for inspection'
      fi
      if ! GIT_TERMINAL_PROMPT=0 git clone --quiet "$origin_url" "$source_tmp"; then
        [ ! -e "$source_tmp" ] || find "$source_tmp" -depth -delete
        fail 'could not create the managed a-good-fellow source; leaving the check due for retry'
      fi
      mv "$source_tmp" "$MANAGED_SOURCE"
      log 'created managed a-good-fellow source'
    fi

    managed_origin=$(git -C "$MANAGED_SOURCE" remote get-url origin 2>/dev/null || true)
    if [ -z "$managed_origin" ]; then
      log 'managed source is unavailable; skipping repository sync'
    elif [ "$managed_origin" != "$origin_url" ]; then
      log 'managed source origin differs from bootstrap origin; preserving it'
    else
      upstream=$(git -C "$MANAGED_SOURCE" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
      if [ -z "$upstream" ]; then
        log 'managed source has no upstream; preserving it'
      elif ! GIT_TERMINAL_PROMPT=0 git -C "$MANAGED_SOURCE" fetch --quiet origin; then
        fail 'could not fetch the a-good-fellow repository; leaving the check due for retry'
      else
        local_head=$(git -C "$MANAGED_SOURCE" rev-parse HEAD)
        remote_head=$(git -C "$MANAGED_SOURCE" rev-parse "$upstream")
        if [ "$local_head" != "$remote_head" ]; then
          if [ -n "$(git -C "$MANAGED_SOURCE" status --porcelain --untracked-files=normal)" ]; then
            log 'managed a-good-fellow source is dirty; preserving it'
          elif git -C "$MANAGED_SOURCE" merge-base --is-ancestor "$local_head" "$remote_head"; then
            git -C "$MANAGED_SOURCE" merge --ff-only "$remote_head" >/dev/null ||
              fail 'managed source fast-forward failed; leaving the check due for retry'
            local_head=$remote_head
          else
            log 'managed a-good-fellow source and upstream diverged; preserving it'
          fi
        fi

        deployed_head=''
        if [ -f "$STATE_DIR/deployment-current" ] && [ ! -L "$STATE_DIR/deployment-current" ]; then
          IFS= read -r deployed_dir < "$STATE_DIR/deployment-current" || deployed_dir=''
          case "$deployed_dir" in
            "$STATE_DIR"/deploy-*)
              [ ! -f "$deployed_dir/runtime-version" ] ||
                IFS= read -r deployed_head < "$deployed_dir/runtime-version"
              ;;
          esac
        fi
        if [ -n "$deployed_head" ] && [ "$local_head" = "$deployed_head" ]; then
          log 'a-good-fellow source unchanged'
        else
          printf '%s\n' "$local_head" > "$SOURCE_UPDATED"
          chmod 600 "$SOURCE_UPDATED"
          log "source_updated=$local_head"
        fi
      fi
    fi
  fi
else
  log 'bootstrap checkout unavailable; skipping repository sync'
fi

printf '%s\n' "$now" > "$stamp_tmp"
chmod 600 "$stamp_tmp"
mv -f "$stamp_tmp" "$LAST_CHECK"
log 'check complete'
