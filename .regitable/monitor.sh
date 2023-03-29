#!/bin/bash

set -euo pipefail

SCRIPT="$(dirname "$(realpath "$0")")"

source "$SCRIPT/config"

exec {TICKET_LOCK}> "$TICKET_LOCKFILE"

while read -r FILE
do
  uuid=""

  echo "Processing: ${FILE}"

  if [[ $FILE == *".uploading" ]]; then
    uuid="${FILE%.uploading}"

    # remove trailing _xx where xx is a number
    uuid="$(echo "$uuid" | sed 's/_.*$//')"
  else
    for extension in lock content pagedata metadata; do
      if [[ $FILE == *".${extension}" ]]; then
        uuid="${FILE%."${extension}"}"
      fi
    done
  fi

  echo "Determined UUID: ${uuid}"

  # test uuid for correct format (excludes "trash" etc)
  test=$(echo "$uuid" | sed 's/^........-....-....-....-............$/OK/')

  if [[ "$uuid" == "trash" || "$test" == "OK" ]]; then
    echo "Writing ticket: $TICKET/$uuid"

    flock -x $TICKET_LOCK
    date "+%s" > "$TICKET/$uuid"
    flock -u $TICKET_LOCK

    echo "Executing push script"
    "$GBUP/acp.sh" &
  fi
done < <(inotifywait -m -q --format '%f' -e DELETE -e CLOSE_WRITE "$DATA")
