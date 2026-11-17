#!/usr/bin/env bash
# Sets up eduroam for HTWG Konstanz in NetworkManager, using the university's
# own installer from https://cat.eduroam.org/?idp=5066 (bundled next to this
# file), and asks for the password in a window.
#
#   HTWG_USER=<name>     account name without the @htwg-konstanz.de part
#                        (from local.env; EDUROAM_USER overrides it)
#   EDUROAM_FORCE=1      set up again even if eduroam is already configured
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The account name is kept out of the repo: local.env (see local.env.example).
ROOT="${OMARCHY_SETUP:-$HERE/../..}"
[[ -f $ROOT/local.env ]] && source "$ROOT/local.env"
ACCOUNT="${EDUROAM_USER:-${HTWG_USER:-}}"
[[ -n $ACCOUNT ]] || { echo "eduroam: set HTWG_USER in $ROOT/local.env (see local.env.example)" >&2; exit 1; }
USERNAME="$ACCOUNT@htwg-konstanz.de"
CA="${XDG_CONFIG_HOME:-$HOME/.config}/cat_installer/ca.pem"

if [[ -z ${EDUROAM_FORCE:-} && -f $CA ]] && nmcli -t -f NAME connection show | grep -qx eduroam; then
  echo "eduroam is already set up (EDUROAM_FORCE=1 to redo it)"
  exit 0
fi

pinentry="$(command -v pinentry-qt || command -v pinentry-gnome3 || command -v pinentry-gtk || true)"
[[ -n $pinentry ]] || { echo "eduroam: no graphical pinentry found" >&2; exit 1; }

# Pinentry answers "D <password>" with %XX escapes, or an error when cancelled.
answer="$(printf '%s\n' \
  "SETTITLE eduroam" \
  "SETDESC Password for $USERNAME" \
  "SETPROMPT Password:" \
  "GETPIN" | "$pinentry" 2>/dev/null | sed -n 's/^D //p')"

if [[ -z $answer ]]; then
  echo "eduroam: no password entered, skipping (run the installer again to set it up)" >&2
  exit 0
fi

# The password goes in on stdin so it never shows up in a process list.
EDUROAM_SCRIPT="$HERE/eduroam-linux-htwg-konstanz.py" EDUROAM_USERNAME="$USERNAME" \
  python3 "$HERE/configure.py" <<<"$answer"

echo "eduroam is set up for $USERNAME"
