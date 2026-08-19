#!/usr/bin/env bash
# Enumerate the complete open-PR inventory and fail if GitHub search is partial.
set -Eeuo pipefail

export GH_PROMPT_DISABLED=1
export NO_COLOR=1
export LC_ALL=C
TAB=$(printf '\t')

viewer=$(gh api user --jq .login)
case "$viewer" in ''|*[!A-Za-z0-9_.-]*) printf 'pr-inventory: invalid viewer login\n' >&2; exit 64 ;; esac

FILTER='
(["META",(.total_count|tostring),(.incomplete_results|tostring),(.items|length|tostring)] | @tsv),
(.items[] | ["ITEM",.repository_url,(.number|tostring),(.user.login // ""),.html_url,((.draft // false)|tostring)] | @tsv)'

search_once() {
  local query=$1 payload expected='' fetched=0 kind a b c d e items='' rendered unique_count
  payload=$(gh api -X GET search/issues -f q="$query" -f per_page=100 \
    -f sort=created -f order=asc \
    --paginate --jq "$FILTER") || return $?
  while IFS=$'\t' read -r kind a b c d e; do
    case "$kind" in
      META)
        case "$a" in ''|*[!0-9]*) printf 'pr-inventory: invalid total_count\n' >&2; return 1 ;; esac
        case "$c" in ''|*[!0-9]*) printf 'pr-inventory: invalid page count\n' >&2; return 1 ;; esac
        [ "$b" = false ] || { printf 'pr-inventory: GitHub reported incomplete search results\n' >&2; return 1; }
        [ "$a" -le 1000 ] || { printf 'pr-inventory: GitHub search exceeds the 1000-result API cap\n' >&2; return 1; }
        if [ -z "$expected" ]; then expected=$a; else [ "$expected" = "$a" ] || { printf 'pr-inventory: total_count changed during pagination\n' >&2; return 1; }; fi
        fetched=$((fetched + c))
        ;;
      ITEM)
        items="${items}${items:+
}${a}\t${b}\t${c}\t${d}\t${e}"
        ;;
      *) printf 'pr-inventory: malformed search page\n' >&2; return 1 ;;
    esac
  done <<EOF
$payload
EOF
  [ -n "$expected" ] || { printf 'pr-inventory: search returned no response page\n' >&2; return 1; }
  [ "$fetched" -eq "$expected" ] || { printf 'pr-inventory: fetched item count does not match total_count\n' >&2; return 1; }
  rendered=$(printf '%b\n' "$items" | sed '/^$/d' | sort -u)
  unique_count=$(printf '%s\n' "$rendered" | awk 'NF { count++ } END { print count+0 }')
  [ "$unique_count" -eq "$expected" ] || { printf 'pr-inventory: duplicate/missing items across search pages\n' >&2; return 1; }
  [ -z "$rendered" ] || printf '%s\n' "$rendered"
}

dedupe_rows() {
  sort | awk -F "$TAB" '
    NF {
      key=$1 FS $2
      if (key == previous_key) {
        if ($0 != previous_row) {
          print "pr-inventory: conflicting rows for " key > "/dev/stderr"
          exit 2
        }
        next
      }
      print
      previous_key=key
      previous_row=$0
    }
  '
}

inventory_round() {
  local involves requested authored
  involves=$(search_once "is:pr is:open involves:$viewer") || return $?
  requested=$(search_once "is:pr is:open review-requested:$viewer") || return $?
  authored=$(search_once "is:pr is:open author:$viewer") || return $?
  printf '%s\n%s\n%s\n' "$involves" "$requested" "$authored" \
    | sed '/^$/d' \
    | dedupe_rows
}

first_round=$(inventory_round)
second_round=$(inventory_round)
[ "$first_round" = "$second_round" ] || {
  printf 'pr-inventory: union membership changed between verification rounds\n' >&2
  exit 1
}
[ -z "$first_round" ] || printf '%s\n' "$first_round"
