# Helpers for Omarchy shell plugins, sourced by install.sh and feature scripts.

PLUGINS="$HOME/.config/omarchy/plugins"

# Put a plugin folder in place as <id>. Left alone when it is already
# identical, since every change makes the shell reload the plugin.
install_plugin() {
  local source="$1" id="$2"

  mkdir -p "$PLUGINS"
  if ! diff -rq "$source" "$PLUGINS/$id" >/dev/null 2>&1; then
    rm -rf "${PLUGINS:?}/$id"
    cp -r "$source" "$PLUGINS/$id"
  fi
  enable_plugin "$id"
}

# Make the shell use an installed plugin, unless shell.json already names it.
enable_plugin() {
  local id="$1"

  omarchy plugin validate "$PLUGINS/$id" >/dev/null
  if jq -e --arg id "$id" '[.. | objects | select(.id? == $id)] | length > 0' \
    "$HOME/.config/omarchy/shell.json" >/dev/null; then
    return 0
  fi

  omarchy-shell shell rescanPlugins >/dev/null
  for _ in $(seq 40); do
    omarchy plugin list --json | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null && break
    sleep 0.1
  done
  omarchy plugin enable "$id"
}

# Remove a plugin; a built-in it was cloned from takes its place again.
remove_plugin() {
  local id="$1"

  [[ -d $PLUGINS/$id ]] || return 0
  omarchy plugin remove "$id" --yes
  rm -rf "${PLUGINS:?}/.$id".bak.* # the repo is the backup
}

# Start a patched copy of one of Omarchy's built-in panels: copies it fresh, so
# it keeps up with Omarchy updates, and prints the folder to patch. Finish with
# finish_clone.
#   begin_clone <built-in folder under shell/plugins> <new id> <display name> <built-in id>
begin_clone() {
  local source_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/$1" id="$2" name="$3" source_id="$4" build

  build="$(mktemp -d)"
  cp -rL "$source_dir/." "$build/"
  jq --arg id "$id" --arg name "$name" --arg source "$source_id" '
    .id = $id | .name = $name | .barWidget.displayName = $name |
    .omarchy = ((.omarchy // {}) + { clonedFrom: $source })
  ' "$source_dir/manifest.json" >"$build/manifest.json"

  echo "$build"
}

# Replace exact text in a file of the clone; fails when Omarchy's code changed
# and the text is no longer there exactly once.
#   patch_clone <file> <old text> <new text>
patch_clone() {
  OLD="$2" NEW="$3" python3 - "$1" <<'PY'
import os, sys

path = sys.argv[1]
old, new = os.environ["OLD"], os.environ["NEW"]
text = open(path).read()
if text.count(old) != 1:
    sys.exit(f"Omarchy's {os.path.basename(path)} changed; this patch no longer fits:\n{old}")
open(path, "w").write(text.replace(old, new))
PY
}

#   finish_clone <build folder> <new id>
finish_clone() {
  local build="$1" id="$2"

  install_plugin "$build" "$id"
  rm -rf "$build"
}
