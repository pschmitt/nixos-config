{
  lib,
  python3Packages,
  fetchPypi,
}:

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "skills-ref";
  version = "0.1.1";
  pyproject = true;

  src = fetchPypi {
    pname = "skills_ref";
    inherit (finalAttrs) version;
    hash = "sha256-a0AMpuAEm+YtygFn/5Q7onRf1n77N/u6TQ7jQfzNJpU=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    click
    strictyaml
  ];

  pythonImportsCheck = [ "skills_ref" ];

  meta = {
    description = "Reference library and validator for Agent Skills";
    homepage = "https://agentskills.io";
    license = lib.licenses.asl20;
    maintainers = [ lib.maintainers.pschmitt ];
    # The PyPI package names its command `agentskills`
    mainProgram = "agentskills";
  };
})
