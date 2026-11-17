"""Run the university's eduroam installer without any questions.

Reads the password (pinentry-escaped) from stdin, so it is never part of a
command line.
"""

import os
import runpy
import sys
from urllib.parse import unquote

import dbus

script = os.environ["EDUROAM_SCRIPT"]
username = os.environ["EDUROAM_USERNAME"]
password = unquote(sys.stdin.readline().rstrip("\n"))

if not password:
    sys.exit("eduroam: empty password")

# --silent answers every question of the installer with yes and takes the
# credentials from its arguments.
sys.argv = [script, "--silent", "--username", username, "--password", password]
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as stop:
    if stop.code not in (None, 0):
        sys.exit("eduroam: the university installer failed")

# The installer leaves the password to a NetworkManager secret agent, which is
# not reliably running on Omarchy. Store it in the connection itself instead
# (readable by root only), so eduroam connects without asking.
bus = dbus.SystemBus()
settings = dbus.Interface(
    bus.get_object("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager/Settings"),
    "org.freedesktop.NetworkManager.Settings",
)

found = False
for path in settings.ListConnections():
    connection = dbus.Interface(
        bus.get_object("org.freedesktop.NetworkManager", path),
        "org.freedesktop.NetworkManager.Settings.Connection",
    )
    config = connection.GetSettings()
    if config["connection"]["id"] == "eduroam" and "802-1x" in config:
        config["802-1x"]["password"] = password
        config["802-1x"]["password-flags"] = dbus.UInt32(0)
        connection.Update(config)
        found = True

if not found:
    sys.exit("eduroam: the installer did not create the connection")
