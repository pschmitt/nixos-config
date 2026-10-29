"""Lint agent skill directories beyond what the Agent Skills spec checks.

Each ROOT holds one directory per skill (ROOT/<name>/SKILL.md). Pass every
skill root that gets deployed together, so links and mentions across skills
(e.g. a private skill pointing at a public one) resolve. Skill roots from
elsewhere go in --context: they resolve names and links, but are not linted.

Checks:
- SKILL.md stays short: move details into references/<topic>.md
- relative Markdown links point at existing files inside the skills (only
  the skill folders are deployed)
- references/ paths mentioned in the text exist
- every file under references/ is linked or mentioned in SKILL.md or another
  reference
- "the `name` skill" names a skill that exists
- scripts/ files are executable and start with a shebang
- no trailing whitespace, files end with a newline
- a skill name exists in one root only (deployment merges the folders)
"""

import argparse
import os
import re
import sys
from pathlib import Path

LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
SKILL_MENTION_RE = re.compile(r"`([a-z0-9][a-z0-9-]*)` skill\b")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
# references/foo.md or scripts/bar.sh as a word of its own, not the tail of
# some other path (.github/workflows/scripts/lint.sh).
PATH_RE = re.compile(r"(?<![\w./$-])((?:references|scripts)/[\w./-]*[\w-])")


def strip_code_blocks(text):
    """Blank out fenced code blocks, keeping line numbers."""
    out = []
    fenced = False
    for line in text.splitlines():
        if FENCE_RE.match(line):
            fenced = not fenced
            out.append("")
            continue
        out.append("" if fenced else line)
    return out


def text_files(skill_dir):
    for path in sorted(skill_dir.rglob("*")):
        if "__pycache__" in path.parts:
            continue
        if path.is_file() and path.suffix in {".md", ".sh", ".py", ".yaml", ".yml", ".txt", ".zsh"}:
            yield path


class Linter:
    def __init__(self, roots, context, max_lines, external):
        self.roots = roots
        self.max_lines = max_lines
        self.errors = []
        self.skills = {}
        self.skill_dirs = []
        for root in roots + context:
            for skill_md in sorted(root.glob("*/SKILL.md")):
                skill_dir = skill_md.parent
                if skill_dir not in self.skill_dirs:
                    self.skill_dirs.append(skill_dir)
                self.skills.setdefault(skill_dir.name, skill_dir)
        self.known = set(self.skills) | set(external)

    def error(self, path, line, msg):
        self.errors.append(f"{path}:{line}: {msg}" if line else f"{path}: {msg}")

    def is_known(self, name):
        return any(name == k or (k.endswith("*") and name.startswith(k[:-1])) for k in self.known)

    def resolve(self, source, target):
        """Resolve a link, looking up ../<skill>/ in every root."""
        path = (source.parent / target).resolve()
        if path.exists():
            return path
        skill_dir = self.skill_of(source)
        rel = Path(os.path.relpath(source.parent / target, skill_dir.parent))
        if rel.parts and rel.parts[0] in self.skills:
            return (self.skills[rel.parts[0]].parent / rel).resolve()
        return path

    def skill_of(self, path):
        for skill_dir in self.skill_dirs:
            if skill_dir in path.parents:
                return skill_dir
        raise ValueError(path)

    def check_paths(self, path, text):
        """Paths like references/foo.md, also inside code blocks."""
        skill_dir = self.skill_of(path)
        mentioned = set()
        for no, line in enumerate(text.splitlines(), 1):
            # Links are checked (and resolved) by check_links.
            for target in PATH_RE.findall(LINK_RE.sub("", line)):
                resolved = (skill_dir / target).resolve()
                if resolved.exists():
                    mentioned.add(resolved)
                elif target.startswith("references/"):
                    # scripts/ paths often name a file in some other repo
                    self.error(path, no, f"missing file: {target}")
        return mentioned

    def check_links(self, path, lines):
        linked = set()
        for no, line in enumerate(lines, 1):
            for target in LINK_RE.findall(line):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
                    continue
                target = target.split("#", 1)[0]
                resolved = self.resolve(path, target)
                if not resolved.exists():
                    self.error(path, no, f"broken link: {target}")
                elif not any(d.resolve() == resolved or d.resolve() in resolved.parents for d in self.skill_dirs):
                    self.error(path, no, f"link leaves the skills, which are deployed alone: {target}")
                else:
                    linked.add(resolved)
            for name in SKILL_MENTION_RE.findall(line):
                if not self.is_known(name):
                    self.error(path, no, f"unknown skill: `{name}`")
        return linked

    def check_skill(self, skill_dir):
        skill_md = skill_dir / "SKILL.md"
        count = len(skill_md.read_text().splitlines())
        if count > self.max_lines:
            self.error(
                skill_md,
                None,
                f"{count} lines (max {self.max_lines}); move details into references/<topic>.md",
            )

        linked = set()
        for md in sorted(skill_dir.rglob("*.md")):
            text = md.read_text()
            linked |= self.check_links(md, strip_code_blocks(text))
            linked |= self.check_paths(md, text)

        refs = skill_dir / "references"
        if refs.is_dir():
            for ref in sorted(p for p in refs.rglob("*") if p.is_file()):
                if ref.resolve() not in linked:
                    self.error(ref, None, "not linked or mentioned in SKILL.md or another reference")

        scripts = skill_dir / "scripts"
        if scripts.is_dir():
            for script in sorted(p for p in scripts.rglob("*") if p.is_file() and "__pycache__" not in p.parts):
                if not os.access(script, os.X_OK):
                    self.error(script, None, "not executable")
                if not script.read_bytes().startswith(b"#!"):
                    self.error(script, 1, "no shebang")

        for path in text_files(skill_dir):
            text = path.read_text()
            if text and not text.endswith("\n"):
                self.error(path, None, "no newline at end of file")
            for no, line in enumerate(text.splitlines(), 1):
                if line != line.rstrip():
                    self.error(path, no, "trailing whitespace")

    def check_duplicates(self):
        first = {}
        for skill_dir in self.skill_dirs:
            other = first.setdefault(skill_dir.name, skill_dir)
            if other != skill_dir and any(r in skill_dir.parents or r in other.parents for r in self.roots):
                self.error(skill_dir / "SKILL.md", None, f"skill '{skill_dir.name}' also in {other}; deployment would merge both")

    def run(self):
        self.check_duplicates()
        for root in self.roots:
            for skill_md in sorted(root.glob("*/SKILL.md")):
                self.check_skill(skill_md.parent)
        return self.errors


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("roots", nargs="+", type=Path, metavar="ROOT")
    parser.add_argument(
        "--context",
        action="append",
        default=[],
        type=Path,
        metavar="ROOT",
        help="skill root deployed alongside, not linted; repeatable",
    )
    parser.add_argument("--max-lines", type=int, default=250, help="SKILL.md line limit (default: 250)")
    parser.add_argument(
        "--external",
        action="append",
        default=[],
        metavar="NAME",
        help="skill deployed from elsewhere (trailing * for a prefix); repeatable",
    )
    args = parser.parse_args()

    roots = [root.resolve() for root in args.roots]
    context = [root.resolve() for root in args.context]
    for root in roots + context:
        if not root.is_dir():
            parser.error(f"not a directory: {root}")

    errors = Linter(roots, context, args.max_lines, args.external).run()
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"{len(errors)} problem(s)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
