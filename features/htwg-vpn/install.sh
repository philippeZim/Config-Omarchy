#!/usr/bin/env bash
# HTWG Konstanz VPN with a switch in the network menu.
#
# - imports the .ovpn profile next to this file into NetworkManager as "HTWG-VPN"
#   (the profile holds a private key, so it is not part of the repo: download
#   it from the university and put it here; it changes every semester, then
#   replace the file and run again)
# - stores the password and the OTP secret in the login keyring, asking for
#   them in a window when they are not there yet
# - installs ~/.local/bin/htwg-vpn, which connects with password + fresh OTP
# - adds the switch to a copy of Omarchy's network panel
#
#   HTWG_USER=<name>   account name (without @htwg-konstanz.de), from local.env
#   HTWG_VPN_FORCE=1   ask for the password and OTP secret again
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The account name is kept out of the repo: local.env (see local.env.example).
ROOT="${OMARCHY_SETUP:-$HERE/../..}"
[[ -f $ROOT/local.env ]] && source "$ROOT/local.env"
USERNAME="${HTWG_USER:-}"
[[ -n $USERNAME ]] || { echo "htwg-vpn: set HTWG_USER in $ROOT/local.env (see local.env.example)" >&2; exit 1; }
CONNECTION="HTWG-VPN"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-setup"
PLUGIN="setup.network"

omarchy pkg add networkmanager-openvpn oath-toolkit libsecret zbar

# --- NetworkManager connection ----------------------------------------------
profiles=("$HERE"/*.ovpn)
[[ -f ${profiles[0]} && ${#profiles[@]} -eq 1 ]] || { echo "htwg-vpn: expected exactly one .ovpn file in $HERE (download the VPN profile from the university; it is not part of the repo)" >&2; exit 1; }
checksum="$(sha256sum <"${profiles[0]}")"

exists() { nmcli -t -f NAME connection show | grep -qxF "$CONNECTION"; }

if ! exists || [[ $(cat "$STATE/htwg-vpn.profile" 2>/dev/null) != "$checksum" ]]; then
  exists && nmcli connection delete id "$CONNECTION" >/dev/null

  # The connection takes its name from the file name.
  staging="$(mktemp -d)"
  trap 'rm -rf "$staging"' EXIT
  cp "${profiles[0]}" "$staging/$CONNECTION.ovpn"
  nmcli connection import type openvpn file "$staging/$CONNECTION.ovpn" >/dev/null

  # The password ends in a one-time code, so it is never saved here.
  nmcli connection modify id "$CONNECTION" \
    connection.autoconnect no \
    +vpn.data "username=$USERNAME" \
    +vpn.data "password-flags=2"

  mkdir -p "$STATE"
  echo "$checksum" >"$STATE/htwg-vpn.profile"
  echo "Imported $(basename "${profiles[0]}") as $CONNECTION"
fi

# --- Password and OTP secret ------------------------------------------------
have() { [[ -z ${HTWG_VPN_FORCE:-} ]] && secret-tool lookup service htwg-vpn kind "$1" >/dev/null 2>&1; }

store() { secret-tool store --label="HTWG-VPN $1" service htwg-vpn kind "$1"; }

# Ask for a secret in a window; prints nothing when cancelled.
ask() {
  local pinentry
  pinentry="$(command -v pinentry-qt || command -v pinentry-gnome3 || command -v pinentry-gtk)"
  printf '%s\n' "SETTITLE HTWG-VPN" "SETDESC $1" "SETPROMPT $2" "GETPIN" | "$pinentry" 2>/dev/null |
    sed -n 's/^D //p' | python3 -c 'import sys, urllib.parse; sys.stdout.write(urllib.parse.unquote(sys.stdin.readline().rstrip("\n")))'
}

if ! have password; then
  # The VPN uses the same account password as eduroam.
  password="$(nmcli -s -g 802-1x.password connection show eduroam 2>/dev/null || true)"
  if [[ -n $password ]]; then
    echo "Using the password saved for eduroam"
  else
    password="$(ask "Password for $USERNAME (without the one-time code)" "Password:")"
  fi

  if [[ -n $password ]]; then
    printf '%s' "$password" | store password
  else
    echo "htwg-vpn: no password entered; run the installer again to set it" >&2
  fi
fi

if ! have totp; then
  # HTWG_OTP skips the window: "cam", a secret key, a link or a picture's path.
  answer="${HTWG_OTP:-}"
  if [[ -z $answer ]]; then
    answer="$(ask "OTP secret for $USERNAME. Enter one of: cam (scan the QR code with the webcam) / the secret key / the otpauth link / the path to a picture of the QR code" "OTP secret:")"
  fi

  if [[ -n $answer ]]; then
    answer="${answer/#\~/$HOME}"
    if [[ ${answer,,} == cam ]]; then
      # Shows the camera picture and closes at the first QR code it sees.
      echo "Hold the QR code up to the webcam..."
      answer="$(timeout 120 zbarcam --raw -1 -Sdisable -Sqrcode.enable 2>/dev/null | head -n1 || true)"
      [[ -n $answer ]] || { echo "htwg-vpn: no QR code seen by the webcam" >&2; exit 1; }
    elif [[ -f $answer ]]; then
      answer="$(zbarimg -q --raw "$answer" | head -n1)"
    fi

    # Prints "<algorithm> <base32 secret>".
    parsed="$(OTP_INPUT="$answer" python3 "$HERE/otp-secret.py")"
    algorithm="${parsed%% *}"
    seed="${parsed#* }"
    oathtool --totp="$algorithm" -b - <<<"$seed" >/dev/null

    printf '%s' "$seed" | store totp
    printf '%s' "$algorithm" | store totp-algo
    echo "Saved the OTP secret"
  else
    echo "htwg-vpn: no OTP secret entered; run the installer again to set it" >&2
  fi
fi

# --- Command ----------------------------------------------------------------
install -Dm755 "$HERE/bin/htwg-vpn" "$HOME/.local/bin/htwg-vpn"

# --- Network panel with the switch ------------------------------------------
# A copy of Omarchy's own panel with one line added that places the switch
# below the header.
source "${OMARCHY_SETUP:-$HERE/../..}/lib/plugins.sh"

build="$(begin_clone panels/network "$PLUGIN" "Network with HTWG-VPN" omarchy.network)"
cp "$HERE/VpnSwitch.qml" "$build/"
anchor='      // Connection details: transfer metrics first, then IP/Gateway.'
patch_clone "$build/Panel.qml" "$anchor" "      VpnSwitch { width: parent.width; bar: root.bar }

$anchor"
finish_clone "$build" "$PLUGIN"

echo "HTWG-VPN is set up for $USERNAME"
