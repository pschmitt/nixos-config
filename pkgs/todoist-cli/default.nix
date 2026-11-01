{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  installAgentSkills,
  installShellFiles,
  nodejs,
}:

buildNpmPackage (finalAttrs: {
  pname = "todoist-cli";
  version = "5.9.0";

  src = fetchFromGitHub {
    owner = "Doist";
    repo = finalAttrs.pname;
    rev = "v${finalAttrs.version}";
    hash = "sha256-5kpEk8ZD8Z0GhfLakfkTKu6uRjC4twALHxdqXfVVoDE=";
  };

  npmDepsHash = "sha256-1mREhEx+Gi6z8YB75v8BTL+KM5pcLQTq5oHhLviUq8c=";

  doCheck = false;

  nativeBuildInputs = [
    installAgentSkills
    installShellFiles
  ];

  # The source tree may carry its own SKILL.md; the skill below is generated
  # from the installed package, so install it explicitly.
  dontInstallAgentSkills = true;

  # Under qemu-user aarch64 emulation (cross builds on x86_64), Node's V8 JIT
  # hits a known QEMU TCG translation cache threading race causing SIGILL
  # (signal 4: Illegal instruction). Running with --jitless forces bytecode
  # interpretation, preventing dynamic code generation races in QEMU.
  env.NODE_OPTIONS = lib.optionalString stdenv.hostPlatform.isAarch64 "--jitless";

  postInstall = ''
    tabtabTemplates=$out/lib/node_modules/@doist/todoist-cli/node_modules/@pnpm/tabtab/lib/templates

    mkdir -p "$TMPDIR/completions"
    sed "s/{pkgname}/td/g; s|{completer}|$out/bin/td|g" \
      "$tabtabTemplates/completion.bash" > "$TMPDIR/completions/td.bash"
    sed "s/{pkgname}/td/g; s|{completer}|$out/bin/td|g" \
      "$tabtabTemplates/completion.zsh" > "$TMPDIR/completions/_td"
    sed "s/{pkgname}/td/g; s|{completer}|$out/bin/td|g" \
      "$tabtabTemplates/completion.fish" > "$TMPDIR/completions/td.fish"

    installShellCompletion --cmd td \
      --bash "$TMPDIR/completions/td.bash" \
      --zsh "$TMPDIR/completions/_td" \
      --fish "$TMPDIR/completions/td.fish"

    # Ship the skill of the CLI: $out/share/skills/todoist-cli/todoist-cli/
    mkdir -p "$TMPDIR/skill/todoist-cli"
    TD_PKG="$out/lib/node_modules/@doist/todoist-cli" \
    TD_SKILL_OUT="$TMPDIR/skill/todoist-cli/SKILL.md" \
    ${nodejs}/bin/node --input-type=module << 'JSEOF'
    import { readFileSync, writeFileSync } from 'node:fs';
    const pkgDir = process.env.TD_PKG;
    const { SKILL_NAME, SKILL_DESCRIPTION, SKILL_COMPATIBILITY, SKILL_CONTENT } = await import(pkgDir + '/dist/lib/skills/content.js');
    const pkg = JSON.parse(readFileSync(pkgDir + '/package.json', 'utf-8'));
    const frontmatter = '---\n'
      + 'name: ' + SKILL_NAME + '\n'
      + 'description: ' + JSON.stringify(SKILL_DESCRIPTION) + '\n'
      + 'compatibility: ' + JSON.stringify(SKILL_COMPATIBILITY) + '\n'
      + 'license: ' + pkg.license + '\n'
      + 'metadata:\n'
      + '  author: Doist\n'
      + '  version: ' + JSON.stringify(pkg.version) + '\n'
      + '---\n\n';
    writeFileSync(process.env.TD_SKILL_OUT, frontmatter + SKILL_CONTENT, 'utf-8');
    JSEOF
    installSkill "$TMPDIR/skill/todoist-cli"
  '';

  passthru.updatePolicy.autoMerge = "patch";

  meta = {
    description = "Command-line interface for Todoist";
    homepage = "https://github.com/Doist/todoist-cli";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "td";
  };
})
