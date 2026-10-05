#!/usr/bin/env bash
# Open questions panel: shows the numbered list of questions the first mate is
# waiting for you to answer. The first mate keeps the list in
# <firstmate home>/data/open-questions.md (one "- " item per question) and
# rewrites it whenever a question is asked, changes or gets answered.
# Redraws when the file changes; press r (or Enter) to redraw now.
# Settings come from ~/.config/firstmate/panels.conf (see panels.conf.example): FM_HOME.
# Usage: questions-panel.sh
set -u
# Local settings live outside this repo.
panels_config=${FIRSTMATE_PANELS_CONFIG:-$HOME/.config/firstmate/panels.conf}
# shellcheck source=/dev/null
[ -r "$panels_config" ] && . "$panels_config"
home=${FM_HOME:-$HOME/firstmate}
file="$home/data/open-questions.md"

trap 'exit 130' INT TERM
trap 'draw' WINCH

mtime() { stat -f %m "$file" 2>/dev/null || echo 0; }

# Wrap plain text to a width first, so colour codes never skew the line breaks.
# $1 first-line prefix (may hold colour codes), $2 its visible width, $3 text.
wrapped() {
  local first=$1 width=$2 text=$3 pad i=0 l
  pad=$(printf '%*s' "$width" '')
  while IFS= read -r l; do
    if [ "$i" -eq 0 ]; then printf '%b%s\n' "$first" "$l"; else printf '%s%s\n' "$pad" "$l"; fi
    i=$((i + 1))
  done < <(printf '%s\n' "$text" | wordwrap "$((cols - width))")
}

# Wrap at spaces only, never inside a word, so a long URL or path stays one
# unbroken line (the terminal soft-wraps it, and copying it gives no newlines).
# URLs become clickable OSC 8 links.
wordwrap() {
  awk -v w="$1" '{
    line = ""
    for (i = 1; i <= NF; i++) {
      word = $i
      if (word ~ /^https?:\/\//) word = "\033]8;;" word "\033\\" word "\033]8;;\033\\"
      vis = length($i)
      if (line == "") { line = word; len = vis }
      else if (len + 1 + vis <= w) { line = line " " word; len += 1 + vis }
      else { print line; line = word; len = vis }
    }
    print line
  }'
}

draw() {
  local rows n=0 line body=""
  read -r rows cols < <(stty size </dev/tty 2>/dev/null || echo "40 80")
  if [ -s "$file" ]; then
    while IFS= read -r line; do
      case "$line" in
        "- "*) n=$((n + 1)); body+=$(wrapped "\033[1;36m$(printf '%2d.' "$n")\033[0m " 4 "${line#- }")$'\n\n' ;;
        "  "*) body+=$(wrapped "    " 4 "${line#  }")$'\n' ;;
        "") ;;
        *) body+=$(wrapped "\033[1m" 0 "$line")$'\033[0m\n' ;;
      esac
    done <"$file"
  fi
  [ "$n" -gt 0 ] || body="none - nothing waiting on you"$'\n'$body
  printf '\033[H\033[2J\033[3J'
  { printf '\033[1mOpen questions\033[0m  \033[2m%s\033[0m\n\n' "$(date +%H:%M:%S)"; printf '%s' "$body"; } | head -n "$((rows - 1))"
}

# The pane may still be settling its size when this starts; let it.
sleep 0.5
last=""
while :; do
  cur=$(mtime)
  if [ "$cur" != "$last" ]; then draw; last=$cur; fi
  if read -rsn1 -t 2 key </dev/tty 2>/dev/null; then
    case "$key" in r|R|"") draw ;; esac
  fi
done
