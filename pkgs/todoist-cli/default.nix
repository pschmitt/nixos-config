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
  version = "3.0.0";

  src = fetchFromGitHub {
    owner = "Doist";
    repo = finalAttrs.pname;
    rev = "v${finalAttrs.version}";
    hash = "sha256-5+FxpTQmxeoNF/lTjKvFxP1T7HYt7YaUflTvw0GcOac=";
  };

  npmDepsHash = "sha256-IVabpRYKMI6ST/TumG7pMwDoUMIJBlhjUm35Eo7mSlE=";

  doCheck = false;

  nativeBuildInputs = [ installShellFiles ];

  # Under qemu-user aarch64 emulation (cross builds on x86_64), `npm ci`
  # occasionally dies with "qemu: uncaught target signal 4 (Illegal
  # instruction)" -- a qemu TCG threading race hit by Node's JIT/worker
  # threads, not a bug in this package. Shadow `npm` on PATH with a retry
  # wrapper so a single flaky emulator crash doesn't fail the (cross-)build.
  # Native builds are unaffected and left alone.
  postPatch = lib.optionalString stdenv.hostPlatform.isAarch64 ''
    npmRetryDir="$TMPDIR/npm-retry-wrapper"
    mkdir -p "$npmRetryDir"
    realNpm="$(command -v npm)"
    cat > "$npmRetryDir/npm" <<EOF
    #!/bin/sh
    set -e
    for attempt in 1 2 3; do
      if "$realNpm" "\$@"; then
        exit 0
      fi
      echo "npm \$* failed (attempt \$attempt/3); retrying..." >&2
    done
    exit 1
    EOF
    chmod +x "$npmRetryDir/npm"
    export PATH="$npmRetryDir:$PATH"
  '';

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

  meta = {
    description = "Command-line interface for Todoist";
    homepage = "https://github.com/Doist/todoist-cli";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "td";
  };
})
