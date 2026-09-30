#!/usr/bin/env bash
# PR panel: a live list of your PRs in one GitHub organisation (plus every PR
# firstmate tracks in <firstmate home>/state/*.meta), grouped by repo, with the
# PR title as a clickable OSC 8 hyperlink. Meant for a terminal side pane.
#
# Open PRs show their review state. PRs merged into the default branch in the
# last 7 days stay listed with their production state, read from GitHub
# Deployments (environment "production", latest status "success", and the merge
# commit contained in the deployed sha); they drop off 24 hours after the first
# successful production deploy that contains them. A PR merged into another
# branch (a stack parent) drops off at once, since it is not deployed by itself.
# Settings come from ~/.config/firstmate/panels.conf (see panels.conf.example):
#   GH_ORG, GH_AUTHOR, FM_HOME.
# Usage: pr-panel.sh [refresh-seconds]
# Keys in the focused pane: r or Enter refreshes now; resizing the pane redraws.
set -u
# Local settings (organisation, accounts, services) live outside this repo.
panels_config=${FIRSTMATE_PANELS_CONFIG:-$HOME/.config/firstmate/panels.conf}
# shellcheck source=/dev/null
[ -r "$panels_config" ] && . "$panels_config"
home=${FM_HOME:-$HOME/firstmate}
interval=${1:-60}
org=${GH_ORG:?set GH_ORG in $panels_config}
author=${GH_AUTHOR:?set GH_AUTHOR in $panels_config}
keep_after_deploy=$((24 * 3600))
cache=${XDG_CACHE_HOME:-$HOME/.cache}/fm-pr-panel
mkdir -p "$cache"

link() { printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$1" "$2"; }
now() { date +%s; }
iso_epoch() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || echo 0; }
ago() {
  local s=$(( $(now) - $1 ))
  if [ "$s" -lt 3600 ]; then echo "$((s / 60))m ago"; else echo "$((s / 3600))h ago"; fi
}

# Successful production deployments of a repo, newest first: "<sha> <epoch>" per line.
# Deployment success is cached per deployment id (a finished deploy does not change).
prod_deploys() {
  local repo=$1 out="" id sha created st
  while IFS=$'\t' read -r id sha created; do
    [ -n "$id" ] || continue
    if [ -f "$cache/deploy-$id" ]; then
      st=$(cat "$cache/deploy-$id")
    else
      st=$(gh api "repos/$org/$repo/deployments/$id/statuses?per_page=1" --jq '.[0].state // "none"' 2>/dev/null) || st=""
      case "$st" in success|failure|error|inactive) printf '%s' "$st" >"$cache/deploy-$id" ;; esac
    fi
    [ "$st" = success ] || [ "$st" = inactive ] || continue
    out+="$sha $(iso_epoch "$created")"$'\n'
  done <<<"$(gh api "repos/$org/$repo/deployments?environment=production&per_page=100" \
               --jq '.[] | [(.id|tostring), .sha, .created_at] | @tsv' 2>/dev/null)"
  printf '%s' "$out"
}

# Does deployed sha $3 contain merge commit $2 in repo $1? Cached (commits are immutable).
contains() {
  local repo=$1 merge=$2 deployed=$3 key="$cache/cmp-$2-$3" st
  if [ -f "$key" ]; then cat "$key"; return; fi
  st=$(gh api "repos/$org/$repo/compare/$merge...$deployed" --jq '.status' 2>/dev/null) || { echo unknown; return; }
  case "$st" in ahead|identical) echo yes ;; *) echo no ;; esac | tee "$key"
}

# Epoch of the first successful production deploy containing the merge commit, or empty.
deployed_at() {
  local repo=$1 merge=$2 deploys=$3 key="$cache/deployed-$repo-$merge" first="" sha ts c reached_end=1
  if [ -f "$key" ]; then cat "$key"; return; fi
  while read -r sha ts; do
    [ -n "$sha" ] || continue
    c=$(contains "$repo" "$merge" "$sha")
    if [ "$c" = yes ]; then first=$ts; else reached_end=0; break; fi
  done <<<"$deploys"
  # Contained even in the oldest deploy we can see: the real first deploy is older.
  [ -n "$first" ] && [ "$reached_end" = 1 ] && first="old:$first"
  [ -n "$first" ] && printf '%s' "$first" >"$key"
  printf '%s' "$first"
}

render() {
  local tracked open_urls merged_urls rows since
  since=$(date -v-7d +%Y-%m-%d)
  tracked=$(grep -h '^pr=https://github.com/' "$home"/state/*.meta 2>/dev/null | cut -d= -f2-)
  open_urls=$( { gh search prs --author "$author" --owner "$org" --state open --limit 50 \
                   --json url --jq '.[].url' 2>/dev/null; printf '%s\n' "$tracked"; } \
               | grep -E '^https://github.com/[^/]+/[^/]+/pull/[0-9]+$' | sort -u)
  merged_urls=$(gh search prs --author "$author" --owner "$org" --merged --merged-at ">=$since" --limit 50 \
                  --json url --jq '.[].url' 2>/dev/null | sort -u)
  rows=""
  local dcache; dcache=$(mktemp -d "${TMPDIR:-/tmp}/fm-pr-panel.XXXXXX")
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    local repo num info state
    repo=$(printf '%s' "$url" | cut -d/ -f5)
    num=${url##*/}
    # reviewDecision stays empty in repos without required reviews, so derive
    # the badge from each reviewer's latest review instead.
    info=$(gh pr view "$num" -R "$org/$repo" \
             --json state,isDraft,title,reviewDecision,latestReviews,mergedAt,mergeCommit,baseRefName \
             --jq '([.latestReviews[].state]) as $s
                   | (if ($s|index("CHANGES_REQUESTED")) then "CHANGES_REQUESTED"
                      elif ($s|index("APPROVED")) then "APPROVED"
                      else (.reviewDecision // "-") end) as $d
                   | [.state, (.isDraft|tostring), $d, (.mergeCommit.oid // "-"), .baseRefName, (.mergedAt // "-"), .title]
                   | join("\u001f")' 2>/dev/null) || continue
    [ -n "$info" ] || continue
    state=${info%%$'\x1f'*}
    local rest=${info#*$'\x1f'} draft decision merge base merged_at title status=""
    IFS=$'\x1f' read -r draft decision merge base merged_at title <<<"$rest"
    case "$state" in
      OPEN)
        [ "$draft" = true ] && status="draft"
        [ "$decision" = APPROVED ] && status="approved"
        [ "$decision" = CHANGES_REQUESTED ] && status="changes"
        ;;
      MERGED)
        [ "$base" = main ] || [ "$base" = master ] || continue
        [ -f "$dcache/$repo" ] || prod_deploys "$repo" >"$dcache/$repo"
        local at
        at=$(deployed_at "$repo" "$merge" "$(cat "$dcache/$repo")")
        if [ "${at#old:}" != "$at" ]; then
          # Deployed before the oldest visible deploy: drop it once it was merged over 24h ago.
          [ $(( $(now) - $(iso_epoch "$merged_at") )) -gt "$keep_after_deploy" ] && continue
          at=${at#old:}
        fi
        if [ -n "$at" ]; then
          [ $(( $(now) - at )) -gt "$keep_after_deploy" ] && continue
          status="prod:$at"
        else
          status="merged"
        fi
        ;;
      *) continue ;;
    esac
    rows+="$repo"$'\x1f'"$num"$'\x1f'"$url"$'\x1f'"$status"$'\x1f'"$title"$'\n'
  done <<<"$(printf '%s\n%s\n' "$open_urls" "$merged_urls" | sort -u)"
  rm -rf "$dcache"

  printf '\033[1mPRs\033[0m  \033[2m%s  (merged ones stay until 24h after production deploy)\033[0m\n\n' "$(date +%H:%M)"
  if [ -z "$rows" ]; then
    printf 'none\n'
    return
  fi
  local last=""
  while IFS=$'\x1f' read -r repo num url status title; do
    [ -n "$repo" ] || continue
    if [ "$repo" != "$last" ]; then
      [ -z "$last" ] || printf '\n'
      printf '\033[1;36m%s\033[0m\n' "$repo"
      last=$repo
    fi
    local tag=""
    case "$status" in
      draft) tag=" \033[2m(draft)\033[0m" ;;
      approved) tag=" \033[32m✓\033[0m" ;;
      changes) tag=" \033[31m✗\033[0m" ;;
      merged) tag=" \033[33m⧗ merged, not in production yet\033[0m" ;;
      prod:*) tag=" \033[32m● in production $(ago "${status#prod:}")\033[0m" ;;
    esac
    printf ' \033[2m#%s\033[0m ' "$num"
    link "$url" "$title"
    printf "%b\n" "$tag"
  done <<<"$(printf '%s' "$rows" | sort -t$'\x1f' -k1,1 -k2,2n)"
}

# Render into a buffer, then clear screen and scrollback and print it capped to the
# pane height, so a list taller than the pane never piles copies into scrollback.
draw_out() {
  local rows total
  rows=$(tput lines 2>/dev/null || echo 40)
  total=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  printf '\033[H\033[2J\033[3J'
  if [ "$total" -gt "$rows" ]; then
    printf '%s\n' "$out" | head -n $((rows - 1))
    printf '\033[2m… %d more lines (enlarge the pane to see all)\033[0m' $((total - rows + 1))
  else
    printf '%s' "$out"
  fi
}

# Wait for the next refresh. Resizing the pane redraws at the new size at once
# (no GitHub calls); pressing r (or Enter) in the focused pane refreshes now.
out=$(render); draw_out
while :; do
  resized=0; key=""
  trap 'resized=1' WINCH
  read -rsn1 -t "$interval" key </dev/tty 2>/dev/null || true
  trap - WINCH
  if [ "$resized" = 1 ]; then draw_out; continue; fi
  out=$(render); draw_out
done
