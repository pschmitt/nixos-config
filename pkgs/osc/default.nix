{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "osc";
  version = "0.4.8";

  src = fetchFromGitHub {
    owner = "theimpostor";
    repo = "osc";
    rev = "v${version}";
    hash = "sha256-XVFNcQH4MFZKmuOD9b3t320/hE+s+3igjlyHBWGKr0Q=";
  };

  vendorHash = "sha256-k+4m9y7oAZqTr8S0zldJk5FeI3+/nN9RggKIfiyxzDI=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Access the system clipboard from anywhere using the ANSI OSC52 sequence";
    homepage = "https://github.com/theimpostor/osc";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "osc";
  };
}
