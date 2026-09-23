{
  lib,
  buildDotnetModule,
  dotnetCorePackages,
  fetchFromGitHub,
}:

buildDotnetModule rec {
  pname = "immich-mcp";
  version = "3.3.3";

  src = fetchFromGitHub {
    owner = "barryw";
    repo = "ImmichMCP";
    tag = "v${version}";
    hash = "sha256-uSR2SVDBFdsGBNplCBll1A9ULUF7HYRbLzGE9hfpoRw=";
  };

  projectFile = "ImmichMCP/ImmichMCP.csproj";
  nugetDeps = ./deps.json;
  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.sdk_10_0.aspnetcore;
  executables = [ "ImmichMCP" ];

  meta = {
    description = "MCP server for Immich photo management";
    homepage = "https://github.com/barryw/ImmichMCP";
    license = lib.licenses.mit;
    mainProgram = "ImmichMCP";
    platforms = lib.platforms.unix;
  };
}
