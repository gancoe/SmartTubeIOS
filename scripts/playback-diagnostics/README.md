# SmartTube playback diagnostics collector

This is a small local collector for the redacted playback events emitted by the
Apple TV diagnostic build. It stores validated events as JSONL and keeps the
newest 10,000 event records. Each write replaces the data file atomically, so a
process or host interruption cannot leave a partially written JSONL file.

The service requires a bearer token in `DIAGNOSTICS_TOKEN_FILE`. The token must
be at least 32 non-whitespace characters. The default bind address is
`127.0.0.1` and the default port is `8765`.

Run locally from this directory with a private token file:

```sh
umask 077
mkdir -p -m 700 .secrets
openssl rand -hex 32 > .secrets/diagnostics-token
DIAGNOSTICS_TOKEN_FILE="$PWD/.secrets/diagnostics-token" \
  python3 server.py --data-file "$PWD/events.jsonl"
```

Run the standard-library tests without making arbitrary network calls:

```sh
python3 -m unittest discover -s . -p 'test_*.py' -v
```

The compose file is a ready-to-review deployment proposal. It has not been
deployed by this change. Before using it, create `.secrets/diagnostics-token` with the
same minimum length and keep that file private. The non-root container runs as
UID 10001, so the host token should be readable by the container while its
parent directory stays private:

```sh
mkdir -p -m 700 .secrets
openssl rand -hex 32 > .secrets/diagnostics-token
chmod 444 .secrets/diagnostics-token
```

The compose service mounts the token read-only, persists `/data`, and restarts
unless stopped. Its host port binding defaults to loopback through
`DIAGNOSTICS_BIND_IP=127.0.0.1`. To make the service reachable from the Apple
TV, set `DIAGNOSTICS_BIND_IP` to the collector host's private LAN address, for
example `192.168.1.20`; this explicit setting keeps LAN exposure deliberate.
Use host firewall rules or a private VPN, never expose the port to the public
internet, and rotate the token if the LAN trust boundary changes.

```sh
DIAGNOSTICS_BIND_IP=192.168.1.20 docker compose up --build
```

The authenticated API is:

* `POST /v1/events` with `Authorization: Bearer <token>` and one JSON event.
  Unknown fields, malformed values, raw URLs, credentials, oversized bodies,
  and duplicate JSON keys are rejected.
* `GET /v1/events?limit=N` with the same authorization header. It returns an
  object containing `events` in timestamp order and the retained `count`.
* `GET /health` returns only the retained record count and does not require
  authentication.

The collector accepts only schema version `1`. Nullable fields may be omitted
by the sender and are returned as JSON `null`; all other fields are required.
The service does not log request headers or bodies.

Error comments permit known timeout messages or a canonical `HTTP NNN` status
extracted from the native error comment. The original HTTP comment is never sent.
