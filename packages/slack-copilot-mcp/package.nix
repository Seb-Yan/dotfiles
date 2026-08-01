{ python3Packages }:

python3Packages.buildPythonApplication {
  pname = "slack-copilot-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [
    python3Packages.hatchling
  ];

  dependencies = [
    python3Packages.mcp
    python3Packages.slack-sdk
  ];

  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    python3Packages.pytest-asyncio
  ];

  pythonImportsCheck = [
    "slack_copilot_mcp"
  ];
}
