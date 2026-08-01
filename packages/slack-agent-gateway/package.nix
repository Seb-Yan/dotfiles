{ python3Packages }:

python3Packages.buildPythonApplication {
  pname = "slack-agent-gateway";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [
    python3Packages.hatchling
  ];

  dependencies = [
    python3Packages.slack-bolt
  ];

  nativeCheckInputs = [
    python3Packages.pytestCheckHook
  ];

  pythonImportsCheck = [
    "slack_agent_gateway"
  ];
}
