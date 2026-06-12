{
  lib,
  buildPythonApplication,
  fetchFromGitHub,
  setuptools,
  wheel,
  distro,
  pyyaml,
  paho-mqtt,
  requests,
  psutil,
  inotify,
  jeepney,
  aiohttp,
  beaupy,
}:

buildPythonApplication rec {
  pname = "lnxlink";
  version = "2026.6.0";

  src = fetchFromGitHub {
    owner = "bkbilly";
    repo = "lnxlink";
    rev = version;
    hash = "sha256-FdAeEUwVQ4L6bl6x3SpHwo85uy/xPv4wU0NWpimaU/c=";
  };

  pyproject = true;

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"setuptools~=68.0.0"' '"setuptools"' \
      --replace-fail '"wheel~=0.40.0"' '"wheel"'
    sed -i '/"asyncio>=/d' pyproject.toml
    # Filter br-* (Docker bridge) interfaces alongside veth* in both modules
    substituteInPlace lnxlink/modules/interfaces.py \
      --replace-fail \
        'if interf.startswith("veth"):' \
        'if interf.startswith(("veth", "br-")):'
    substituteInPlace lnxlink/modules/wol.py \
      --replace-fail \
        'if interf.startswith("veth"):' \
        'if interf.startswith(("veth", "br-")):'
  '';

  nativeBuildInputs = [
    setuptools
    wheel
  ];

  propagatedBuildInputs = [
    distro
    pyyaml
    paho-mqtt
    requests
    psutil
    inotify
    jeepney
    aiohttp
    beaupy
  ];

  doCheck = false;

  meta = {
    description = "Internet of Things (IoT) integration with Linux using MQTT";
    homepage = "https://github.com/bkbilly/lnxlink";
    changelog = "https://github.com/bkbilly/lnxlink/releases/tag/${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "lnxlink";
  };
}
