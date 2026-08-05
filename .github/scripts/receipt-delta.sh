#!/usr/bin/env bash
#
# Render a Markdown package-change summary between two rootfs receipts.
#
# Usage: receipt-delta.sh <previous_receipt|""> <current_receipt>
#
# The previous receipt may be empty/missing (first build, or download failed),
# in which case every package is reported as newly present.
#
# Tolerates BOTH receipt formats so it keeps working across the format change:
#   - legacy `dpkg -l` table:                 "ii  <pkg>  <version>  <arch>  <desc>"
#   - new metadata + tab-separated table:     "<pkg>\t<version>\t<arch>"  (after a
#                                             metadata header and a blank line)
set -euo pipefail

prev_file="${1:-}"
curr_file="${2:-}"

if [[ -z "$curr_file" || ! -f "$curr_file" ]]; then
  echo "receipt-delta: current receipt not found: '$curr_file'" >&2
  exit 1
fi

# Emit sorted "package<TAB>version" lines from either receipt format.
extract() {
  local f="$1"
  [[ -n "$f" && -f "$f" ]] || return 0
  if grep -qE '^ii[[:space:]]' "$f" 2>/dev/null; then
    # legacy dpkg -l table
    awk '$1=="ii" {print $2"\t"$3}' "$f"
  else
    # new format: skip metadata header (up to first blank line) and the
    # "PACKAGE VERSION ARCHITECTURE" column header, then read tab columns.
    awk -F'\t' 'seen && $1!="PACKAGE" && NF>=2 {print $1"\t"$2} /^[[:space:]]*$/{seen=1}' "$f"
  fi | LC_ALL=C sort -u
}

prev_norm="$(mktemp)"
curr_norm="$(mktemp)"
trap 'rm -f "$prev_norm" "$curr_norm"' EXIT

extract "$prev_file" > "$prev_norm"
extract "$curr_file" > "$curr_norm"

delta="$(awk -F'\t' -v prevfile="$prev_norm" '
  FILENAME==prevfile { prev[$1]=$2; next }
  { curr[$1]=$2 }
  END {
    for (p in curr) if (!(p in prev))                    print "ADDED\t"    p "\t" curr[p]
    for (p in prev) if (!(p in curr))                    print "REMOVED\t"  p "\t" prev[p]
    for (p in curr) if ((p in prev) && prev[p]!=curr[p]) print "UPGRADED\t" p "\t" prev[p] " -> " curr[p]
  }' "$prev_norm" "$curr_norm" | LC_ALL=C sort)"

added="$(printf   '%s\n' "$delta" | awk -F'\t' '$1=="ADDED"    {print "- `"$2"` "$3}')"
removed="$(printf '%s\n' "$delta" | awk -F'\t' '$1=="REMOVED"  {print "- `"$2"` "$3}')"
upgraded="$(printf '%s\n' "$delta" | awk -F'\t' '$1=="UPGRADED"{print "- `"$2"`: "$3}')"

count() { [[ -z "$1" ]] && { echo 0; return; }; printf '%s\n' "$1" | grep -c . || true; }
n_added=$(count "$added")
n_removed=$(count "$removed")
n_upgraded=$(count "$upgraded")
n_total=$(grep -c . "$curr_norm" || echo 0)

section() {
  local title="$1" cnt="$2" body="$3"
  [[ "${cnt:-0}" -eq 0 ]] && return 0
  printf '<details><summary><strong>%s (%s)</strong></summary>\n\n%s\n\n</details>\n\n' \
    "$title" "$cnt" "$body"
}

printf '## Package changes\n\n'
if [[ -s "$prev_norm" ]]; then
  printf '%s upgraded &middot; %s added &middot; %s removed &middot; %s total packages in this build.\n\n' \
    "$n_upgraded" "$n_added" "$n_removed" "$n_total"
else
  printf 'No previous receipt available for comparison &mdash; %s package(s) in this build.\n\n' "$n_total"
fi
section "Upgraded" "$n_upgraded" "$upgraded"
section "Added"    "$n_added"    "$added"
section "Removed"  "$n_removed"  "$removed"
