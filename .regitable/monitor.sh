#!/bin/bash

set -euo pipefail

SCRIPT="$(dirname "$(realpath "$0")")"

source "$SCRIPT/config"

print_verbose() {
  if [ "${REGITABLE_VERBOSE:-false}" = "true" ]; then
    echo "$@"
  fi
}

exec {TICKET_LOCK}> "$TICKET_LOCKFILE"

while read -r FILE
do
  uuid=""

  print_verbose "Processing: ${FILE}"

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

  print_verbose "Determined UUID: ${uuid}"

  # test uuid for correct format (excludes "trash" etc)
  test=$(echo "$uuid" | sed 's/^........-....-....-....-............$/OK/')

  if [[ "$uuid" == "trash" || "$test" == "OK" ]]; then
    print_verbose "Writing ticket: $TICKET/$uuid"

    flock -x $TICKET_LOCK
    date "+%s" > "$TICKET/$uuid"
    flock -u $TICKET_LOCK

    print_verbose "Executing push script"
    "$GBUP/acp.sh" &
  fi
done < <(inotifywait -m -q --format '%f' -e DELETE -e CLOSE_WRITE "$DATA")
