{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  installShellFiles,
  nodejs,
  runCommand,
}:

buildNpmPackage (finalAttrs: {
  pname = "todoist-cli";
  version = "5.8.2";

  src = fetchFromGitHub {
    owner = "Doist";
    repo = finalAttrs.pname;
    rev = "v${finalAttrs.version}";
    hash = "sha256-996o0ACxgkTJfSl4UdxD0/mTyhqXAi3Ui1aL05t4zOo=";
  };

  npmDepsHash = "sha256-OFFa+pR4/eJRUyqH2oU6Rpqd+Xv6tmUn7qjamDeT3M4=";

  doCheck = false;

  nativeBuildInputs = [ installShellFiles ];

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
  '';

  passthru.skill = runCommand "todoist-cli-skill" { } ''
    mkdir -p "$out/todoist-cli"
    TD_SKILL_OUT="$out/todoist-cli/SKILL.md" \
    ${nodejs}/bin/node --input-type=module << 'JSEOF'
    import { SKILL_NAME, SKILL_DESCRIPTION, SKILL_COMPATIBILITY, SKILL_CONTENT } from '${finalAttrs.finalPackage}/lib/node_modules/@doist/todoist-cli/dist/lib/skills/content.js';
    import { readFileSync, writeFileSync } from 'node:fs';
    const pkg = JSON.parse(readFileSync('${finalAttrs.finalPackage}/lib/node_modules/@doist/todoist-cli/package.json', 'utf-8'));
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
