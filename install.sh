#!/usr/bin/env bash
# Applies the customizations in this repo to an Omarchy install.
#
# Run it inside a running Omarchy session. With no arguments it asks which
# features to install. Safe to run repeatedly: the chosen features are
# (re)installed and the ones left out are removed again.
#
# A feature is a folder in features/ holding any of:
#   description   one line shown in the chooser
#   hypr/*.lua    Hyprland config, loaded after Omarchy's defaults
#   bash/*.sh     aliases and functions for interactive terminals
#   plugins/<id>/ Omarchy shell plugins (replace the built-in they are cloned from)
#   install.sh    extra steps to run when the feature is installed (gets the
#                 repo path in $OMARCHY_SETUP; helpers are in lib/)
#   uninstall.sh  how to undo those steps
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPR="$HOME/.config/hypr"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-setup/features"

usage() {
  cat <<USAGE
Usage: install.sh [--all | --list | <feature>...]

  (no arguments)  choose features interactively
  --all           install every feature
  --list          list the available features
  <feature>...    install exactly these features

Features that are not chosen are removed if a previous run installed them.
USAGE
}

step() { printf '\n==> %s\n' "$*"; }
fail() { echo "install.sh: $*" >&2; exit 1; }

mapfile -t FEATURES < <(find "$REPO/features" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

describe() { cat "$REPO/features/$1/description" 2>/dev/null || echo "$1"; }

contains() {
  local wanted="$1" item
  shift
  for item in "$@"; do [[ $item == "$wanted" ]] && return 0; done
  return 1
}

# --- Choose features --------------------------------------------------------
selected=()
case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
--list)
  for feature in "${FEATURES[@]}"; do printf '%-20s %s\n' "$feature" "$(describe "$feature")"; done
  exit 0
  ;;
--all)
  selected=("${FEATURES[@]}")
  ;;
"")
  [[ -t 0 && -t 1 ]] || fail "not a terminal; pass --all or the features to install (see --list)"

  # Start from what the last run installed, or everything on a first run.
  if [[ -f $STATE ]]; then mapfile -t previous <"$STATE"; else previous=("${FEATURES[@]}"); fi

  labels=()
  preselected=()
  for feature in "${FEATURES[@]}"; do
    label="$(describe "$feature")"
    label="${label//,/;}" # gum splits --selected on commas
    labels+=("$label")
    contains "$feature" "${previous[@]}" && preselected+=("$label")
  done

  chosen="$(gum choose --no-limit --height=20 \
    --header="Features to install:" \
    --selected="$(IFS=,; echo "${preselected[*]}")" "${labels[@]}")" || fail "cancelled"

  for i in "${!FEATURES[@]}"; do
    grep -qxF -- "${labels[$i]}" <<<"$chosen" && selected+=("${FEATURES[$i]}")
  done
  ;;
-*)
  usage >&2
  exit 1
  ;;
*)
  for feature in "$@"; do
    contains "$feature" "${FEATURES[@]}" || fail "unknown feature '$feature' (see --list)"
    selected+=("$feature")
  done
  ;;
esac

is_selected() { contains "$1" "${selected[@]}"; }

# --- Hyprland overrides -----------------------------------------------------
# Lua overrides live in ~/.config/hypr/setup/ and are loaded by a single line
# appended to hyprland.lua, so Omarchy's stock user files stay untouched.
step "Installing Hyprland overrides"
mkdir -p "$HYPR/setup"
find "$HYPR/setup" -maxdepth 1 -type f -name '*.lua' -delete
cp "$REPO/lib/hypr/init.lua" "$HYPR/setup/"
for feature in "${selected[@]}"; do
  for file in "$REPO/features/$feature"/hypr/*.lua; do
    [[ -e $file ]] && cp "$file" "$HYPR/setup/"
  done
done

if ! grep -qF 'hypr/setup/init.lua' "$HYPR/hyprland.lua"; then
  cp "$HYPR/hyprland.lua" "$HYPR/hyprland.lua.bak.$(date +%s)"
  printf '\n%s\n' 'dofile(os.getenv("HOME") .. "/.config/hypr/setup/init.lua") -- Omarchy_Setup overrides' >>"$HYPR/hyprland.lua"
fi

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload >/dev/null
  errors="$(hyprctl configerrors)"
  if [[ -n "${errors//[[:space:]]/}" ]]; then
    echo "Hyprland reported config errors:" >&2
    echo "$errors" >&2
    exit 1
  fi
fi

# --- Terminal (bash) --------------------------------------------------------
# Snippets live in ~/.config/bash/setup/ and are sourced by one line appended
# to ~/.bashrc.
step "Installing terminal settings"
BASH_SETUP="$HOME/.config/bash/setup"
mkdir -p "$BASH_SETUP"
find "$BASH_SETUP" -maxdepth 1 -type f -name '*.sh' -delete
for feature in "${selected[@]}"; do
  for file in "$REPO/features/$feature"/bash/*.sh; do
    [[ -e $file ]] && cp "$file" "$BASH_SETUP/"
  done
done

if ! grep -qF '.config/bash/setup' "$HOME/.bashrc"; then
  cp "$HOME/.bashrc" "$HOME/.bashrc.bak.$(date +%s)"
  printf '\n%s\n' 'for f in ~/.config/bash/setup/*.sh; do [[ -r $f ]] && source "$f"; done; unset f # Omarchy_Setup' >>"$HOME/.bashrc"
fi

# --- Omarchy shell plugins --------------------------------------------------
step "Installing Omarchy shell plugins"
source "$REPO/lib/plugins.sh"
mkdir -p "$PLUGINS"
for feature in "${FEATURES[@]}"; do
  for plugin in "$REPO/features/$feature"/plugins/*/; do
    [[ -d $plugin ]] || continue
    id="$(basename "$plugin")"

    if is_selected "$feature"; then
      install_plugin "${plugin%/}" "$id"
    else
      remove_plugin "$id"
    fi
  done
done

# --- Feature scripts --------------------------------------------------------
if [[ -f $STATE ]]; then mapfile -t installed <"$STATE"; else installed=(); fi
for feature in "${FEATURES[@]}"; do
  dir="$REPO/features/$feature"
  if is_selected "$feature"; then
    if [[ -f $dir/install.sh ]]; then
      step "Installing $feature"
      OMARCHY_SETUP="$REPO" bash "$dir/install.sh"
    fi
  elif contains "$feature" "${installed[@]}" && [[ -f $dir/uninstall.sh ]]; then
    step "Removing $feature"
    OMARCHY_SETUP="$REPO" bash "$dir/uninstall.sh"
  fi
done

mkdir -p "$(dirname "$STATE")"
printf '%s\n' "${selected[@]}" >"$STATE"

step "Done. Installed: ${selected[*]:-nothing}"
