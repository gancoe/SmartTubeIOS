#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hmac
import http.server
import json
import math
import os
import re
import tempfile
import threading
import urllib.parse
import uuid
from pathlib import Path
from typing import Any


DEFAULT_BIND_ADDRESS = "127.0.0.1"
DEFAULT_PORT = 8765
DEFAULT_MAX_RECORDS = 10_000
DEFAULT_READ_LIMIT = 100
MAX_BODY_BYTES = 64 * 1024
MIN_TOKEN_LENGTH = 32

REQUIRED_FIELDS = {
    "schema_version",
    "event_id",
    "timestamp",
    "report_id",
    "video_id",
    "resolution",
    "item_status",
    "playback_status",
    "waiting_reason",
    "stream_route",
    "access_event_count",
    "error_event_count",
    "dropped_frames",
    "stalls",
}
OPTIONAL_NULLABLE_FIELDS = {
    "rate",
    "buffer_media_seconds",
    "buffer_viewing_seconds",
    "playback_position_seconds",
    "advertised_bitrate_bps",
    "observed_bitrate_bps",
    "peak_bitrate_bps",
    "downloaded_bytes",
    "error_domain",
    "error_code",
    "error_timestamp",
    "error_comment",
    "error_resource",
}
ALL_FIELDS = REQUIRED_FIELDS | OPTIONAL_NULLABLE_FIELDS
FIELD_ORDER = (
    "schema_version",
    "event_id",
    "timestamp",
    "report_id",
    "video_id",
    "resolution",
    "rate",
    "buffer_media_seconds",
    "buffer_viewing_seconds",
    "playback_position_seconds",
    "item_status",
    "playback_status",
    "waiting_reason",
    "stream_route",
    "advertised_bitrate_bps",
    "observed_bitrate_bps",
    "peak_bitrate_bps",
    "access_event_count",
    "error_event_count",
    "dropped_frames",
    "stalls",
    "downloaded_bytes",
    "error_domain",
    "error_code",
    "error_timestamp",
    "error_comment",
    "error_resource",
)

SAFE_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
SAFE_DOMAIN = re.compile(r"^[A-Za-z0-9_.-]{1,80}$")
SAFE_ROUTE = re.compile(r"^[A-Za-z0-9/_. -]{1,100}$")
RESOLUTION = re.compile(r"^(?:unknown|[1-9][0-9]{0,4}[x×][1-9][0-9]{0,4})$")
TIMEOUT_COMMENT = re.compile(
    r"^(?:Media (?:file|playlist) not received in [0-9]+(?:\.[0-9]+)?s|"
    r"No response for media file in [0-9]+(?:\.[0-9]+)?s|HTTP [1-5][0-9]{2}|Details redacted|—)$"
)
RESOURCE_SUMMARY = re.compile(
    r"^(?:unknown|(?:playlist URL|captions URL|audio URL \(MIME hint\)|"
    r"video URL \(MIME hint\)|media URL \(track unknown\)|unknown URL)"
    r" · (?:HTTPS|HTTP|playlist proxy)(?: · itag=[1-9][0-9]*)?)$"
)

ITEM_STATUSES = {"unknown", "ready", "failed"}
PLAYBACK_STATUSES = {"unknown", "playing", "paused", "waiting"}
WAITING_REASONS = {
    "unknown",
    "toMinimizeStalls",
    "evaluatingBufferingRate",
    "noItemToPlay",
    "—",
}


class PayloadError(ValueError):
    pass


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise PayloadError("duplicate key")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> None:
    raise PayloadError(f"invalid number {value}")


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _finite_number(
    value: Any,
    field: str,
    *,
    minimum: float | None = None,
    maximum: float | None = None,
) -> None:
    if not _is_number(value):
        raise PayloadError(f"invalid {field}")
    try:
        numeric = float(value)
    except OverflowError as exc:
        raise PayloadError(f"invalid {field}") from exc
    if not math.isfinite(numeric):
        raise PayloadError(f"invalid {field}")
    if minimum is not None and numeric < minimum:
        raise PayloadError(f"invalid {field}")
    if maximum is not None and numeric > maximum:
        raise PayloadError(f"invalid {field}")


def _optional_number(
    event: dict[str, Any],
    field: str,
    *,
    minimum: float | None = None,
    maximum: float | None = None,
) -> None:
    if field not in event or event[field] is None:
        return
    _finite_number(event[field], field, minimum=minimum, maximum=maximum)


def _parse_timestamp(value: Any, field: str) -> dt.datetime:
    if not isinstance(value, str) or len(value) > 64:
        raise PayloadError(f"invalid {field}")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise PayloadError(f"invalid {field}") from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise PayloadError(f"invalid {field}")
    return parsed


def validate_event(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise PayloadError("event must be an object")
    unknown = set(raw) - ALL_FIELDS
    missing = REQUIRED_FIELDS - set(raw)
    if unknown or missing:
        raise PayloadError("event fields are invalid")

    event: dict[str, Any] = {field: raw[field] for field in FIELD_ORDER if field in raw}

    if event["schema_version"] != 1 or isinstance(event["schema_version"], bool):
        raise PayloadError("invalid schema version")
    try:
        event_uuid = uuid.UUID(event["event_id"])
    except (AttributeError, ValueError, TypeError) as exc:
        raise PayloadError("invalid event id") from exc
    if str(event_uuid) != event["event_id"].lower():
        raise PayloadError("invalid event id")
    event["event_id"] = str(event_uuid)
    _parse_timestamp(event["timestamp"], "timestamp")

    for field in ("report_id", "video_id"):
        if not isinstance(event[field], str) or not SAFE_ID.fullmatch(event[field]):
            raise PayloadError(f"invalid {field}")
    if not isinstance(event["resolution"], str) or not RESOLUTION.fullmatch(
        event["resolution"]
    ):
        raise PayloadError("invalid resolution")
    if (
        not isinstance(event["item_status"], str)
        or event["item_status"] not in ITEM_STATUSES
    ):
        raise PayloadError("invalid item status")
    if (
        not isinstance(event["playback_status"], str)
        or event["playback_status"] not in PLAYBACK_STATUSES
    ):
        raise PayloadError("invalid playback status")
    if (
        not isinstance(event["waiting_reason"], str)
        or event["waiting_reason"] not in WAITING_REASONS
    ):
        raise PayloadError("invalid waiting reason")
    if not isinstance(event["stream_route"], str) or not SAFE_ROUTE.fullmatch(
        event["stream_route"]
    ):
        raise PayloadError("invalid stream route")
    if (
        not isinstance(event["access_event_count"], int)
        or isinstance(event["access_event_count"], bool)
        or event["access_event_count"] < 0
    ):
        raise PayloadError("invalid access event count")
    if (
        not isinstance(event["error_event_count"], int)
        or isinstance(event["error_event_count"], bool)
        or event["error_event_count"] < 0
    ):
        raise PayloadError("invalid error event count")

    _optional_number(event, "rate", minimum=0, maximum=4)
    _optional_number(event, "buffer_media_seconds", minimum=0)
    _optional_number(event, "buffer_viewing_seconds", minimum=0)
    _optional_number(event, "playback_position_seconds", minimum=0)
    _optional_number(event, "advertised_bitrate_bps", minimum=0, maximum=None)
    if (
        "advertised_bitrate_bps" in event
        and event["advertised_bitrate_bps"] is not None
        and event["advertised_bitrate_bps"] <= 0
    ):
        raise PayloadError("invalid advertised bitrate")
    _optional_number(event, "observed_bitrate_bps", minimum=0, maximum=None)
    if (
        "observed_bitrate_bps" in event
        and event["observed_bitrate_bps"] is not None
        and event["observed_bitrate_bps"] <= 0
    ):
        raise PayloadError("invalid observed bitrate")
    _optional_number(event, "peak_bitrate_bps", minimum=0)

    for field in ("dropped_frames", "stalls"):
        if (
            not isinstance(event[field], int)
            or isinstance(event[field], bool)
            or event[field] < 0
        ):
            raise PayloadError(f"invalid {field}")
    if "downloaded_bytes" in event and event["downloaded_bytes"] is not None:
        if (
            not isinstance(event["downloaded_bytes"], int)
            or isinstance(event["downloaded_bytes"], bool)
            or event["downloaded_bytes"] < 0
        ):
            raise PayloadError("invalid downloaded bytes")

    if "error_domain" in event and event["error_domain"] is not None:
        if not isinstance(event["error_domain"], str) or not SAFE_DOMAIN.fullmatch(
            event["error_domain"]
        ):
            raise PayloadError("invalid error domain")
    if "error_code" in event and event["error_code"] is not None:
        if not isinstance(event["error_code"], int) or isinstance(
            event["error_code"], bool
        ):
            raise PayloadError("invalid error code")
        if not -(2**31) <= event["error_code"] <= 2**31 - 1:
            raise PayloadError("invalid error code")
    if "error_timestamp" in event and event["error_timestamp"] is not None:
        _parse_timestamp(event["error_timestamp"], "error timestamp")
    if "error_comment" in event and event["error_comment"] is not None:
        if not isinstance(event["error_comment"], str) or not TIMEOUT_COMMENT.fullmatch(
            event["error_comment"]
        ):
            raise PayloadError("invalid error comment")
    if "error_resource" in event and event["error_resource"] is not None:
        if not isinstance(
            event["error_resource"], str
        ) or not RESOURCE_SUMMARY.fullmatch(event["error_resource"]):
            raise PayloadError("invalid error resource")

    for field in OPTIONAL_NULLABLE_FIELDS:
        event.setdefault(field, None)
    return {field: event[field] for field in FIELD_ORDER}


class EventStore:
    def __init__(
        self, path: str | os.PathLike[str], max_records: int = DEFAULT_MAX_RECORDS
    ) -> None:
        if max_records < 1:
            raise ValueError("max_records must be positive")
        self.path = Path(path)
        self.max_records = max_records
        self._records: list[dict[str, Any]] = []
        self._event_ids: set[str] = set()
        self._lock = threading.RLock()
        self._load()

    def _load(self) -> None:
        if not self.path.exists():
            return
        with self.path.open("r", encoding="utf-8") as stream:
            for line in stream:
                if not line.strip():
                    continue
                try:
                    raw = json.loads(
                        line,
                        object_pairs_hook=_reject_duplicate_keys,
                        parse_constant=_reject_json_constant,
                    )
                    event = validate_event(raw)
                except (json.JSONDecodeError, PayloadError) as exc:
                    raise ValueError(f"invalid event store: {self.path}") from exc
                if event["event_id"] not in self._event_ids:
                    self._records.append(event)
                    self._event_ids.add(event["event_id"])
        before = [
            json.dumps(event, ensure_ascii=False, separators=(",", ":"))
            for event in self._records
        ]
        self._sort_and_trim()
        after = [
            json.dumps(event, ensure_ascii=False, separators=(",", ":"))
            for event in self._records
        ]
        if before != after:
            with self._lock:
                self._persist_locked()

    def _sort_and_trim(self) -> None:
        self._records.sort(
            key=lambda event: _parse_timestamp(event["timestamp"], "timestamp")
        )
        if len(self._records) > self.max_records:
            removed = self._records[: -self.max_records]
            self._records = self._records[-self.max_records :]
            self._event_ids.difference_update(event["event_id"] for event in removed)

    def _persist_locked(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        directory = str(self.path.parent)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{self.path.name}.", suffix=".tmp", dir=directory
        )
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                for event in self._records:
                    stream.write(
                        json.dumps(event, ensure_ascii=False, separators=(",", ":"))
                    )
                    stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary_name, self.path)
        except BaseException:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass
            raise

    def append(self, raw: Any) -> tuple[dict[str, Any], bool]:
        event = validate_event(raw)
        with self._lock:
            if event["event_id"] in self._event_ids:
                return event, False
            previous_records = list(self._records)
            previous_event_ids = set(self._event_ids)
            self._records.append(event)
            self._event_ids.add(event["event_id"])
            self._sort_and_trim()
            try:
                self._persist_locked()
            except BaseException:
                self._records = previous_records
                self._event_ids = previous_event_ids
                raise
            return event, True

    def snapshot(self, limit: int) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(event) for event in self._records[-limit:]]

    def count(self) -> int:
        with self._lock:
            return len(self._records)


def read_token(path: str | os.PathLike[str]) -> str:
    try:
        token = Path(path).read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as exc:
        raise RuntimeError("DIAGNOSTICS_TOKEN_FILE cannot be read") from exc
    if len(token) < MIN_TOKEN_LENGTH or any(character.isspace() for character in token):
        raise RuntimeError("DIAGNOSTICS_TOKEN_FILE token is too short or malformed")
    return token


class DiagnosticRequestHandler(http.server.BaseHTTPRequestHandler):
    server: "DiagnosticHTTPServer"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def _write_json(
        self, status: int, body: Any, *, headers: dict[str, str] | None = None
    ) -> None:
        payload = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode(
            "utf-8"
        )
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(payload)

    def _error(
        self, status: int, message: str, *, headers: dict[str, str] | None = None
    ) -> None:
        self._write_json(status, {"error": message}, headers=headers)

    def _authorized(self) -> bool:
        supplied = self.headers.get("Authorization", "")
        expected = "Bearer " + self.server.token
        return hmac.compare_digest(supplied, expected)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path == "/health":
            if parsed.query:
                self._error(400, "invalid request")
                return
            self._write_json(200, {"count": self.server.store.count()})
            return
        if parsed.path != "/v1/events":
            self._error(404, "not found")
            return
        if not self._authorized():
            self._error(401, "unauthorized", headers={"WWW-Authenticate": "Bearer"})
            return
        parameters = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        if set(parameters) - {"limit"} or len(parameters.get("limit", [])) > 1:
            self._error(400, "invalid request")
            return
        try:
            limit = int(parameters.get("limit", [str(DEFAULT_READ_LIMIT)])[0])
        except ValueError:
            self._error(400, "invalid request")
            return
        if not 1 <= limit <= self.server.store.max_records:
            self._error(400, "invalid request")
            return
        self._write_json(
            200,
            {
                "events": self.server.store.snapshot(limit),
                "count": self.server.store.count(),
            },
        )

    def do_POST(self) -> None:
        if urllib.parse.urlsplit(self.path).path != "/v1/events":
            self._error(404, "not found")
            return
        if not self._authorized():
            self._error(401, "unauthorized", headers={"WWW-Authenticate": "Bearer"})
            return
        content_type = self.headers.get("Content-Type", "")
        if not content_type.lower().startswith("application/json"):
            self._error(415, "invalid payload")
            return
        content_length = self.headers.get("Content-Length")
        try:
            length = int(content_length) if content_length is not None else -1
        except ValueError:
            length = -1
        if length < 0:
            self._error(411, "invalid payload")
            return
        if length > MAX_BODY_BYTES:
            self._error(413, "payload too large")
            self.close_connection = True
            return
        body = self.rfile.read(length)
        if len(body) != length:
            self._error(400, "invalid payload")
            return
        try:
            raw = json.loads(
                body.decode("utf-8"),
                object_pairs_hook=_reject_duplicate_keys,
                parse_constant=_reject_json_constant,
            )
            event, created = self.server.store.append(raw)
        except (UnicodeDecodeError, json.JSONDecodeError, PayloadError):
            self._error(400, "invalid payload")
            return
        except (OSError, ValueError):
            self._error(500, "collector unavailable")
            return
        self._write_json(
            201 if created else 200,
            {
                "accepted": created,
                "duplicate": not created,
                "event_id": event["event_id"],
            },
        )


class DiagnosticHTTPServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], store: EventStore, token: str) -> None:
        self.store = store
        self.token = token
        super().__init__(address, DiagnosticRequestHandler)


def build_server(
    host: str = DEFAULT_BIND_ADDRESS,
    port: int = DEFAULT_PORT,
    *,
    data_file: str | os.PathLike[str] = "playback-events.jsonl",
    token_file: str | os.PathLike[str] | None = None,
    max_records: int = DEFAULT_MAX_RECORDS,
) -> DiagnosticHTTPServer:
    resolved_token_file = token_file or os.environ.get("DIAGNOSTICS_TOKEN_FILE")
    if not resolved_token_file:
        raise RuntimeError("DIAGNOSTICS_TOKEN_FILE is required")
    return DiagnosticHTTPServer(
        (host, port),
        EventStore(data_file, max_records),
        read_token(resolved_token_file),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--host",
        default=os.environ.get("DIAGNOSTICS_BIND_ADDRESS", DEFAULT_BIND_ADDRESS),
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("DIAGNOSTICS_PORT", DEFAULT_PORT)),
    )
    parser.add_argument(
        "--data-file",
        default=os.environ.get("DIAGNOSTICS_DATA_FILE", "playback-events.jsonl"),
    )
    parser.add_argument("--max-records", type=int, default=DEFAULT_MAX_RECORDS)
    args = parser.parse_args()
    server = build_server(
        args.host, args.port, data_file=args.data_file, max_records=args.max_records
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
