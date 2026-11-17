"""Turn what the user entered into "<algorithm> <base32 secret>".

Input in $OTP_INPUT: a base32 secret key, an otpauth://totp/ link, or the
otpauth-migration:// link behind a Google Authenticator export QR code.
"""

import base64
import os
import re
import sys
from urllib.parse import parse_qs, urlparse

ALGORITHMS = {0: "SHA1", 1: "SHA1", 2: "SHA256", 3: "SHA512"}


def fail(message):
    sys.exit("htwg-vpn: " + message)


def fields(data):
    """Yield (field number, value) for one protobuf message."""
    position = 0

    def varint():
        nonlocal position
        result = shift = 0
        while True:
            byte = data[position]
            position += 1
            result |= (byte & 0x7F) << shift
            shift += 7
            if not byte & 0x80:
                return result

    while position < len(data):
        key = varint()
        number, kind = key >> 3, key & 7
        if kind == 0:
            yield number, varint()
        elif kind == 2:
            length = varint()
            yield number, data[position:position + length]
            position += length
        else:
            fail("could not read the Google Authenticator export")


def from_migration(link):
    """The HTWG entry of a Google Authenticator export."""
    payload = parse_qs(urlparse(link).query).get("data", [""])[0]
    try:
        payload = base64.b64decode(payload.replace(" ", "+") + "=" * (-len(payload) % 4))
        entries = []
        for number, value in fields(payload):
            if number == 1:
                entry = dict(fields(value))
                entries.append({
                    "secret": entry.get(1, b""),
                    "name": (entry.get(3, b"") + b" " + entry.get(2, b"")).decode("utf8", "replace").strip(),
                    "algorithm": entry.get(4, 1),
                    "digits": entry.get(5, 1),
                    "type": entry.get(6, 2),
                })
    except (ValueError, IndexError):
        fail("could not read the Google Authenticator export")

    if not entries:
        fail("the Google Authenticator export holds no accounts")

    chosen = [entry for entry in entries if "htwg" in entry["name"].lower()]
    if len(chosen) != 1:
        chosen = entries
    if len(chosen) != 1:
        names = ", ".join(entry["name"] or "(no name)" for entry in entries)
        fail("the export holds several accounts (" + names + "); export only the HTWG one")

    entry = chosen[0]
    if entry["type"] != 2:
        fail("only time-based (TOTP) tokens can be automated")
    if entry["digits"] not in (0, 1):
        fail("unsupported OTP settings (expected 6 digits)")
    if entry["algorithm"] not in ALGORITHMS:
        fail("unsupported OTP algorithm")

    return ALGORITHMS[entry["algorithm"]], base64.b32encode(entry["secret"]).decode()


def from_otpauth(link):
    url = urlparse(link)
    if url.netloc.lower() != "totp":
        fail("only time-based (TOTP) tokens can be automated")
    query = parse_qs(url.query)
    if query.get("digits", ["6"])[0] != "6" or query.get("period", ["30"])[0] != "30":
        fail("unsupported OTP settings (expected 6 digits every 30 seconds)")
    return query.get("algorithm", ["SHA1"])[0].upper(), query.get("secret", [""])[0]


value = os.environ["OTP_INPUT"].strip()
if value.lower().startswith("otpauth-migration://"):
    algorithm, secret = from_migration(value)
elif value.lower().startswith("otpauth://"):
    algorithm, secret = from_otpauth(value)
else:
    algorithm, secret = "SHA1", value

secret = re.sub(r"[\s-]", "", secret).upper()
if not re.fullmatch(r"[A-Z2-7]+=*", secret) or algorithm not in ("SHA1", "SHA256", "SHA512"):
    fail("that does not look like an OTP secret")

print(algorithm, secret)
