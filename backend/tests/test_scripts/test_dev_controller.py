from __future__ import annotations

import json
import shutil
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from scripts.dev_controller.flutter_session import (
    FlutterMachineSession,
    FlutterSessionError,
    build_flutter_web_command,
    decode_machine_line,
    encode_machine_request,
)
from scripts.dev_controller.controller import ControllerHTTPServer, DevController
from scripts.dev_controller.security import redact_text, resolve_test_target
from scripts.dev_controller.tasks import (
    TaskManager,
    TaskRunner,
    TaskValidationError,
    build_task_command,
)


@pytest.fixture
def frontend(tmp_path: Path) -> Path:
    frontend_dir = tmp_path / "frontend"
    test_dir = frontend_dir / "test" / "widget"
    test_dir.mkdir(parents=True)
    (test_dir / "card_test.dart").write_text("void main() {}", encoding="utf-8")
    return frontend_dir


def test_fixed_tasks_reject_extra_arguments(frontend: Path) -> None:
    assert build_task_command("analyze", {"task": "analyze"}, frontend) == [
        "flutter",
        "analyze",
    ]
    with pytest.raises(TaskValidationError, match="不接受参数"):
        build_task_command(
            "analyze",
            {"task": "analyze", "command": "Remove-Item"},
            frontend,
        )


def test_test_task_only_accepts_existing_test_file(frontend: Path) -> None:
    command = build_task_command(
        "test",
        {
            "task": "test",
            "target": "test/widget/card_test.dart",
            "reporter": "expanded",
        },
        frontend,
    )
    assert command[:2] == ["flutter", "test"]
    assert command[-2:] == ["--reporter", "expanded"]
    assert Path(command[2]) == frontend / "test" / "widget" / "card_test.dart"

    with pytest.raises(TaskValidationError, match="frontend/test"):
        build_task_command(
            "test",
            {"task": "test", "target": "../outside_test.dart"},
            frontend,
        )
    with pytest.raises(TaskValidationError, match="只允许"):
        build_task_command(
            "test",
            {"task": "test", "target": "test/widget/card.dart"},
            frontend,
        )


def test_resolve_test_target_rejects_sibling_prefix(frontend: Path) -> None:
    sibling = frontend / "test-escape" / "bad_test.dart"
    sibling.parent.mkdir()
    sibling.write_text("", encoding="utf-8")
    with pytest.raises(ValueError, match="frontend/test"):
        resolve_test_target(frontend, "test-escape/bad_test.dart")


def test_machine_protocol_uses_single_object_array() -> None:
    encoded = encode_machine_request(
        "vaultstream-1",
        "app.restart",
        {"appId": "app-1", "fullRestart": False},
    )
    assert json.loads(encoded) == [
        {
            "id": "vaultstream-1",
            "method": "app.restart",
            "params": {"appId": "app-1", "fullRestart": False},
        }
    ]
    assert decode_machine_line(encoded) == json.loads(encoded)[0]
    assert decode_machine_line("ordinary compiler output") is None


def test_flutter_web_command_preserves_local_api_contract() -> None:
    assert build_flutter_web_command(
        "C:/sdk/flutter.bat",
        device="web-server",
        web_host="127.0.0.1",
        web_port=8123,
        api_base_url="http://127.0.0.1:8008/api/v1",
    ) == [
        "C:/sdk/flutter.bat",
        "run",
        "--machine",
        "-d",
        "web-server",
        "--web-hostname",
        "127.0.0.1",
        "--web-port",
        "8123",
        "--dart-define=API_BASE_URL=http://127.0.0.1:8008/api/v1",
    ]


def test_reload_is_rejected_until_flutter_reports_ready(frontend: Path) -> None:
    session = FlutterMachineSession(frontend, web_port=18123)
    session._handle_machine_message(  # type: ignore[attr-defined]
        {
            "event": "app.start",
            "params": {"appId": "app-1", "supportsRestart": True},
        }
    )
    with pytest.raises(FlutterSessionError, match="尚未就绪"):
        session.reload()


def test_log_redaction_covers_headers_bearer_and_query_secrets() -> None:
    raw = (
        "Authorization: Bearer abc.def\n"
        "X-API-Token: private\n"
        "https://local/media?a=1&signature=signed-value&token=abc"
    )
    redacted = redact_text(raw)
    assert "abc.def" not in redacted
    assert "private" not in redacted
    assert "signed-value" not in redacted
    assert "token=<redacted>" in redacted


class _FakeRunner:
    def __init__(self) -> None:
        self.commands: list[list[str]] = []

    def run(self, command: list[str]) -> tuple[int, str, str]:
        self.commands.append(command)
        return 0, "No issues found!", ""

    def stop(self) -> None:
        pass


def test_task_manager_returns_machine_readable_result(frontend: Path) -> None:
    runner = _FakeRunner()
    manager = TaskManager(frontend, runner=runner)  # type: ignore[arg-type]
    try:
        submitted = manager.submit({"task": "analyze"})
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            result = manager.get(submitted["taskId"])
            if result is not None and result["state"] == "completed":
                break
            time.sleep(0.01)
        else:
            pytest.fail("task did not complete")
        assert result["exitCode"] == 0
        assert result["stdout"] == "No issues found!"
        assert runner.commands == [["flutter", "analyze"]]
    finally:
        manager.close()


def test_task_runner_resolves_batch_executable_without_shell(
    frontend: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: dict[str, object] = {}

    class _Process:
        returncode = 0

        def communicate(self) -> tuple[str, str]:
            return "ok", ""

        def poll(self) -> int:
            return 0

    def fake_popen(command: list[str], **kwargs: object) -> _Process:
        captured["command"] = command
        captured["shell"] = kwargs["shell"]
        return _Process()

    monkeypatch.setattr(shutil, "which", lambda command: f"C:/sdk/{command}.bat")
    monkeypatch.setattr("subprocess.Popen", fake_popen)
    result = TaskRunner(frontend).run(["flutter", "analyze"])
    assert result == (0, "ok", "")
    assert captured == {
        "command": ["C:/sdk/flutter.bat", "analyze"],
        "shell": False,
    }


def test_http_control_plane_requires_token_and_rejects_command_injection(
    tmp_path: Path,
) -> None:
    repo_root = tmp_path / "repo"
    (repo_root / "frontend" / "test").mkdir(parents=True)
    controller = DevController(repo_root, web_port=18123, control_port=0)
    server = ControllerHTTPServer(("127.0.0.1", 0), controller)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f"http://127.0.0.1:{server.server_port}"
    try:
        with pytest.raises(urllib.error.HTTPError) as unauthorized:
            urllib.request.urlopen(f"{base_url}/status", timeout=2)
        assert unauthorized.value.code == 401

        body = json.dumps(
            {"task": "analyze", "command": "Remove-Item -Recurse C:\\"}
        ).encode()
        request = urllib.request.Request(
            f"{base_url}/tasks",
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {controller.token}",
                "Content-Type": "application/json",
            },
        )
        with pytest.raises(urllib.error.HTTPError) as rejected:
            urllib.request.urlopen(request, timeout=2)
        assert rejected.value.code == 400
        assert "不接受参数" in rejected.value.read().decode("utf-8")
    finally:
        server.shutdown()
        server.server_close()
        controller.close()
        thread.join(timeout=2)
