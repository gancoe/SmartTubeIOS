import importlib.util
import json
import pathlib
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "diagnostics_configuration",
    pathlib.Path(__file__).with_name("configure-playback-diagnostics.py"),
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ConfigurationTests(unittest.TestCase):
    def test_packages_only_configured_local_exception_and_preserves_existing_settings(
        self,
    ):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            app = root / "App.app"
            app.mkdir()
            info = {
                "CFBundleIdentifier": "test",
                "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": False},
            }
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            config = {
                "endpoint": "http://192.168.68.74:8765/v1/events",
                "token": "test-only-value-" * 4,
            }
            source = root / "config.json"
            source.write_text(json.dumps(config))
            module.configure(source, app)
            result = plistlib.loads((app / "Info.plist").read_bytes())
            self.assertFalse(result["NSAppTransportSecurity"]["NSAllowsArbitraryLoads"])
            self.assertEqual(
                result["NSAppTransportSecurity"]["NSExceptionDomains"],
                {"192.168.68.74": {"NSExceptionAllowsInsecureHTTPLoads": True}},
            )
            self.assertEqual(
                json.loads((app / "PlaybackDiagnostics.json").read_text()), config
            )

    def test_rejects_public_http_and_credentials_in_url_before_touching_app(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "config.json"
            for endpoint in [
                "http://public.example/v1/events",
                "https://user:secret@example.com/v1/events",
            ]:
                source.write_text(
                    json.dumps({"endpoint": endpoint, "token": "test-only-value-" * 4})
                )
                with self.assertRaises(ValueError):
                    module.configure(source, root / "Missing.app")

    def test_rejects_whitespace_in_token(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "config.json"
            for whitespace in [" ", "\t", "\n", "\u2003"]:
                source.write_text(json.dumps({"endpoint": "http://127.0.0.1/v1/events", "token": "a" * 32 + whitespace}))
                with self.assertRaises(ValueError):
                    module.configure(source, root / "Missing.app")


if __name__ == "__main__":
    unittest.main()
