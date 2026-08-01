from pathlib import Path

import pytest
from slack_copilot_mcp.cli import main


def test_doctor_reports_missing_configuration_as_structured_output(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    missing = tmp_path / "missing"

    with pytest.raises(SystemExit) as exit_info:
        main(["doctor", "--env-file", str(missing)])

    output = capsys.readouterr().out
    assert exit_info.value.code == 1
    assert 'status: "not ready"' in output
    assert "environment file does not exist" in output
    assert "Traceback" not in output


def test_unknown_flag_is_a_usage_error(
    capsys: pytest.CaptureFixture[str],
) -> None:
    with pytest.raises(SystemExit) as exit_info:
        main(["doctor", "--unknown"])

    output = capsys.readouterr().out
    assert exit_info.value.code == 2
    assert 'error: "unrecognized arguments: --unknown"' in output
    assert "valid command flag is --env-file" in output
