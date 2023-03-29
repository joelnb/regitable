#!/bin/bash

set -euo pipefail

SCRIPT="$(dirname "$(realpath "$0")")"

source "$SCRIPT/config"

exec {GIT_LOCK}> "$GIT_LOCKFILE"
exec {TICKET_LOCK}> "$TICKET_LOCKFILE"

function git_commit() {
  uuid="$1"

  git add -A

  message="regitable auto-commit of latest remarkable edits

Changes to documents included:"

  file_details="$(git status -s | grep -E '^(A|M).*\.metadata$' | sed -E 's/^(A|M)\s+//' | xargs -n1 jq -r '. | "- \(.visibleName)"')"

  staged="$(git diff --staged --name-only | wc -l)"

  if (( staged > 0 )); then
    echo -e "Creating commit with message:\n$message\n$file_details"
    git commit -q -m "$message
$file_details"
  fi
}

function git_push() {
  if (( $(git remote | wc -l) > 0 )); then
    committed=$(git log origin/master..master --name-only | wc -l)

    if (( committed > 0 )); then
      if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
        git push -q
      fi

      git lfs prune
    fi
  fi
}

# only allow one instance of this script
flock -n "$GIT_LOCK" || exit 0

count="40"
interval="2"

while (( count > 0 )); do
  flock -x "$TICKET_LOCK" || exit 1

  # get oldest ticket
  ticket="$(ls "$TICKET" -tr1 | head -n 1)"
  uuid="sleep"

  # no more tickets, then push and exit
  if [[ $ticket == "" ]]; then
    echo "No more tickets left to process - pushing current changes"
    git_push
    exit 0
  fi

  # get stamp from ticket
  stamp="$(cat "$TICKET/$ticket")"
  now="$(date "+%s")"
  diff="(( $now - $stamp ))"

  # debounce period over, then go
  if (( diff > 2 )); then
    echo "Processing ticket: ${ticket}"
    rm "$TICKET/$ticket"
    uuid="$ticket"
  fi

  flock -u "$TICKET_LOCK"

  if [[ "$uuid" == "sleep" ]]; then
    sleep "${interval}s"
  else
    git_commit "$uuid"
  fi

  count="(( $count - $interval ))"
done
