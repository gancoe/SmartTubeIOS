from __future__ import annotations

import datetime as dt
import http.client
import json
import tempfile
import threading
import unittest
import uuid
from pathlib import Path

from server import (
    DiagnosticHTTPServer,
    EventStore,
    MIN_TOKEN_LENGTH,
    read_token,
    validate_event,
)


TOKEN = "T" * MIN_TOKEN_LENGTH


def event(
    event_id: str | None = None, *, timestamp: str = "2026-10-04T00:00:00Z"
) -> dict[str, object]:
    return {
        "schema_version": 1,
        "event_id": event_id or str(uuid.uuid4()),
        "timestamp": timestamp,
        "report_id": "74446D15",
        "video_id": "CyEoXiiZZgc",
        "resolution": "854x480",
        "item_status": "ready",
        "playback_status": "waiting",
        "waiting_reason": "toMinimizeStalls",
        "stream_route": "Native4K/HLS",
        "observed_bitrate_bps": 1_500_000,
        "access_event_count": 2,
        "error_event_count": 1,
        "dropped_frames": 4,
        "stalls": 1,
        "downloaded_bytes": 200_000,
        "rate": 1.5,
        "buffer_media_seconds": 50.0,
        "buffer_viewing_seconds": 33.333,
        "playback_position_seconds": 123.45,
        "advertised_bitrate_bps": 2_000_000,
        "peak_bitrate_bps": None,
        "error_domain": "CoreMediaErrorDomain",
        "error_code": -16830,
        "error_timestamp": "2026-10-04T00:00:00Z",
        "error_comment": "Media file not received in 15s",
        "error_resource": "video URL (MIME hint) · HTTPS · itag=617",
    }


class CollectorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.data_file = Path(self.temp_dir.name) / "events.jsonl"
        self.server = DiagnosticHTTPServer(
            ("127.0.0.1", 0), EventStore(self.data_file, max_records=3), TOKEN
        )
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()
        self.host, self.port = self.server.server_address

    def tearDown(self) -> None:
        self.server.shutdown()
        self.thread.join(timeout=2)
        self.server.server_close()
        self.temp_dir.cleanup()

    def request(
        self,
        method: str,
        path: str,
        body: object | str | None = None,
        *,
        token: str | None = TOKEN,
    ) -> tuple[int, dict[str, object]]:
        connection = http.client.HTTPConnection(self.host, self.port, timeout=2)
        headers = {"Content-Type": "application/json"}
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        encoded = body
        if isinstance(body, dict):
            encoded = json.dumps(body)
        connection.request(method, path, body=encoded, headers=headers)
        response = connection.getresponse()
        payload = json.loads(response.read())
        connection.close()
        return response.status, payload

    def test_requires_authentication_and_rejects_credentials_in_payload(self) -> None:
        status, body = self.request("POST", "/v1/events", event(), token="wrong")
        self.assertEqual(status, 401)
        self.assertEqual(body, {"error": "unauthorized"})

        unsafe = event()
        unsafe["error_comment"] = "Authorization: bearer secret"
        status, body = self.request("POST", "/v1/events", unsafe)
        self.assertEqual(status, 400)
        self.assertEqual(body, {"error": "invalid payload"})

    def test_accepts_only_canonical_http_status_comments(self) -> None:
        for comment in ("HTTP 401", "HTTP 503"):
            payload = event()
            payload["event_id"] = str(uuid.uuid4())
            payload["error_comment"] = comment
            status, _ = self.request("POST", "/v1/events", payload)
            self.assertEqual(status, 201)
        for comment in (
            "HTTP 600",
            "HTTP 4010",
            "HTTP 401: secret",
            "HTTP 401\nCookie: secret",
        ):
            payload = event()
            payload["error_comment"] = comment
            status, _ = self.request("POST", "/v1/events", payload)
            self.assertEqual(status, 400)

    def test_rejects_unknown_fields_bad_payload_and_oversize(self) -> None:
        unknown = event()
        unknown["unexpected"] = True
        status, body = self.request("POST", "/v1/events", unknown)
        self.assertEqual(status, 400)
        self.assertEqual(body, {"error": "invalid payload"})

        status, body = self.request("POST", "/v1/events", "not json")
        self.assertEqual(status, 400)
        self.assertEqual(body, {"error": "invalid payload"})

        status, body = self.request("POST", "/v1/events", "x" * (64 * 1024 + 1))
        self.assertEqual(status, 413)
        self.assertEqual(body, {"error": "payload too large"})

    def test_duplicate_event_id_is_idempotent(self) -> None:
        payload = event()
        first_status, first_body = self.request("POST", "/v1/events", payload)
        second_status, second_body = self.request("POST", "/v1/events", payload)
        self.assertEqual(first_status, 201)
        self.assertEqual(second_status, 200)
        self.assertTrue(first_body["accepted"])
        self.assertFalse(second_body["accepted"])
        self.assertEqual(self.server.store.count(), 1)

    def test_retention_is_bounded_and_chronological(self) -> None:
        for index in range(4):
            timestamp = (
                dt.datetime(2026, 10, 4, 0, index, tzinfo=dt.timezone.utc)
                .isoformat()
                .replace("+00:00", "Z")
            )
            status, _ = self.request("POST", "/v1/events", event(timestamp=timestamp))
            self.assertEqual(status, 201)
        status, body = self.request("GET", "/v1/events?limit=3")
        self.assertEqual(status, 200)
        records = body["events"]
        self.assertEqual(len(records), 3)
        self.assertEqual(
            [record["timestamp"] for record in records],
            [
                "2026-10-04T00:01:00Z",
                "2026-10-04T00:02:00Z",
                "2026-10-04T00:03:00Z",
            ],
        )
        self.assertEqual(self.data_file.read_text(encoding="utf-8").count("\n"), 3)

    def test_retrieval_and_health_do_not_expose_token_or_extra_data(self) -> None:
        payload = event()
        self.request("POST", "/v1/events", payload)
        status, body = self.request("GET", "/v1/events?limit=1")
        self.assertEqual(status, 200)
        self.assertEqual(body["count"], 1)
        self.assertNotIn("Authorization", json.dumps(body))
        status, body = self.request("GET", "/health", token=None)
        self.assertEqual(status, 200)
        self.assertEqual(body, {"count": 1})
        self.assertNotIn("event_id", body)


class ValidationTests(unittest.TestCase):
    def test_compose_command_complements_entrypoint_and_binds_explicitly(self) -> None:
        directory = Path(__file__).parent
        dockerfile = (directory / "Dockerfile").read_text(encoding="utf-8")
        compose = (directory / "compose.yaml").read_text(encoding="utf-8")
        self.assertIn('ENTRYPOINT ["python", "/app/server.py"]', dockerfile)
        self.assertNotIn("- /app/server.py", compose)
        self.assertIn("      - --host\n", compose)
        self.assertIn("${DIAGNOSTICS_BIND_IP:-127.0.0.1}:8765:8765", compose)
        self.assertIn("restart: unless-stopped", compose)
        self.assertIn(
            "./.secrets/diagnostics-token:/run/secrets/diagnostics-token:ro", compose
        )

    def test_token_file_is_required_and_long_enough(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "token"
            with self.assertRaises(RuntimeError):
                read_token(path)
            path.write_text("short", encoding="utf-8")
            with self.assertRaises(RuntimeError):
                read_token(path)

    def test_nullable_fields_may_be_omitted_and_are_normalized(self) -> None:
        payload = event()
        for field in (
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
        ):
            del payload[field]
        normalized = validate_event(payload)
        self.assertIsNone(normalized["rate"])
        self.assertIsNone(normalized["error_resource"])

    def test_playback_position_is_finite_and_nonnegative(self) -> None:
        payload = event()
        self.assertEqual(validate_event(payload)["playback_position_seconds"], 123.45)
        payload["playback_position_seconds"] = -0.1
        with self.assertRaises(ValueError):
            validate_event(payload)
        payload["playback_position_seconds"] = float("inf")
        with self.assertRaises(ValueError):
            validate_event(payload)

    def test_rejects_nonfinite_numbers_and_raw_resource(self) -> None:
        payload = event()
        payload["rate"] = float("nan")
        with self.assertRaises(ValueError):
            validate_event(payload)
        payload = event()
        payload["error_resource"] = "https://cdn.example/secret"
        with self.assertRaises(ValueError):
            validate_event(payload)
        payload = event()
        payload["error_resource"] = "unknown"
        self.assertEqual(validate_event(payload)["error_resource"], "unknown")


if __name__ == "__main__":
    unittest.main()
