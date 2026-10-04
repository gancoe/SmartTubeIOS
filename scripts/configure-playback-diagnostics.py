#!/usr/bin/env python3
import ipaddress
import json
import pathlib
import plistlib
import sys
import urllib.parse


def configure(config_path, app_path):
    config = json.loads(pathlib.Path(config_path).read_text())
    if set(config) != {"endpoint", "token"}:
        raise ValueError("invalid diagnostics configuration keys")
    endpoint = urllib.parse.urlsplit(config["endpoint"])
    token = config["token"]
    if (
        endpoint.scheme not in {"http", "https"}
        or not endpoint.hostname
        or endpoint.username is not None
        or endpoint.password is not None
        or endpoint.query
        or endpoint.fragment
        or endpoint.path != "/v1/events"
        or not isinstance(token, str)
        or len(token) < 32
        or any(character.isspace() for character in token)
    ):
        raise ValueError("invalid diagnostics endpoint or token")
    if endpoint.scheme == "http":
        try:
            address = ipaddress.IPv4Address(endpoint.hostname)
            allowed = any(
                address in ipaddress.ip_network(network)
                for network in [
                    "10.0.0.0/8",
                    "172.16.0.0/12",
                    "192.168.0.0/16",
                    "127.0.0.0/8",
                ]
            )
        except ipaddress.AddressValueError:
            allowed = endpoint.hostname.endswith(".local")
        if not allowed:
            raise ValueError("HTTP diagnostics requires a local endpoint")
    app = pathlib.Path(app_path)
    info_path = app / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    if endpoint.scheme == "http":
        ats = info.setdefault("NSAppTransportSecurity", {})
        exceptions = ats.setdefault("NSExceptionDomains", {})
        exceptions[endpoint.hostname] = {"NSExceptionAllowsInsecureHTTPLoads": True}
        ats["NSAllowsLocalNetworking"] = True
    info["NSLocalNetworkUsageDescription"] = (
        "Send playback diagnostics to your configured home server."
    )
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
    (app / "PlaybackDiagnostics.json").write_text(json.dumps(config))
    (app / "PlaybackDiagnostics.json").chmod(0o600)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("expected configuration and app paths")
        configure(sys.argv[1], sys.argv[2])
    except (ValueError, TypeError, KeyError, OSError):
        sys.exit("Invalid playback diagnostics configuration; no credentials printed.")
