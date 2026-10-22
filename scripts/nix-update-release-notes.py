#!/usr/bin/env python3
"""Render upstream release JSON as a bounded, collapsible Markdown section."""

import argparse
import html
import json
import posixpath
import re
import sys
from urllib.error import URLError
from urllib.parse import quote, unquote, urljoin, urlsplit
from urllib.request import Request, urlopen

INLINE_LINK = re.compile(r"(!?\[[^\]\n]*\]\()(<[^>\n]+>|[^\s)]+)([^)\n]*\))")
REFERENCE = re.compile(r"^( {0,3}\[[^\]\n]+\]:\s*)(<[^>\n]+>|\S+)")
HTML_LINK = re.compile(r'\b(href|src)=("|\')([^"\']+)\2', re.IGNORECASE)
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")


def absolute_link(destination, repo, tag, release_url, image=False, source_path=""):
    wrapped = destination.startswith("<") and destination.endswith(">")
    url = destination[1:-1] if wrapped else destination
    if not url or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", url) or url.startswith("//"):
        return destination
    if url.startswith("#"):
        source_url = (
            f"https://github.com/{repo}/blob/{quote(tag, safe='')}/{quote(source_path)}"
            if source_path
            else release_url
        )
        value = urljoin(source_url, url)
    elif url.startswith("/"):
        value = urljoin("https://github.com", url)
    else:
        if image:
            root = f"https://raw.githubusercontent.com/{repo}/{quote(tag, safe='')}/"
        else:
            root = f"https://github.com/{repo}/blob/{quote(tag, safe='')}/"
        directory = posixpath.dirname(source_path)
        if directory:
            root += directory + "/"
        value = urljoin(root, url)
    return f"<{value}>" if wrapped else value


def normalize_notes(body, repo, tag, release_url, source_path=""):
    """Keep code examples literal while fixing repository-relative links."""
    lines = body.replace("\r\n", "\n").replace("\r", "\n").strip().splitlines()
    result = []
    fence = None
    for line in lines:
        match = FENCE.match(line)
        if match:
            run, rest = match.groups()
            if fence is None:
                fence = run
            elif run[0] == fence[0] and len(run) >= len(fence) and not rest.strip():
                fence = None
            result.append(line)
            continue
        if fence is not None:
            result.append(line)
            continue

        def rewrite_link(match):
            lead, destination, tail = match.groups()
            return (
                lead
                + absolute_link(
                    destination,
                    repo,
                    tag,
                    release_url,
                    image=lead.startswith("!"),
                    source_path=source_path,
                )
                + tail
            )

        # Inline code is not Markdown link syntax and must remain untouched.
        segments = re.split(r"(`+[^`]*`+)", line)
        for i in range(0, len(segments), 2):
            segment = INLINE_LINK.sub(rewrite_link, segments[i])
            segment = REFERENCE.sub(
                lambda m: (
                    m[1]
                    + absolute_link(
                        m[2], repo, tag, release_url, source_path=source_path
                    )
                ),
                segment,
            )
            segment = HTML_LINK.sub(
                lambda m: (
                    m[1]
                    + "="
                    + m[2]
                    + absolute_link(
                        m[3],
                        repo,
                        tag,
                        release_url,
                        image=m[1].lower() == "src",
                        source_path=source_path,
                    )
                    + m[2]
                ),
                segment,
            )
            segments[i] = segment
        result.append("".join(segments))
    if fence is not None:
        result.append(fence)
    return "\n".join(result)


def linked_changelog_path(body, repo, tag):
    text = "\n".join(
        line for line in body.splitlines() if not line.lstrip().startswith("#")
    )
    matches = list(INLINE_LINK.finditer(text))
    if len(matches) != 1 or len(text) > 2000 or matches[0][1].startswith("!"):
        return None
    match = matches[0]
    remaining = text[: match.start()] + text[match.end() :]
    allowed = {
        "see",
        "read",
        "view",
        "the",
        "full",
        "release",
        "notes",
        "changelog",
        "changes",
        "at",
        "in",
        "here",
        "for",
        "this",
        "version",
        "is",
        "available",
        "can",
        "be",
        "found",
        "please",
    }
    if (
        "`" in remaining
        or not set(re.findall(r"[A-Za-z]+", remaining.lower())) <= allowed
    ):
        return None
    destination = match[2].strip("<>")
    try:
        parsed = urlsplit(destination)
    except ValueError:
        return None
    path = unquote(parsed.path)
    if parsed.netloc:
        prefix = f"/{repo}/"
        if not path.startswith(prefix):
            return None
        path = path[len(prefix) :]
        if parsed.netloc == "github.com" and path.startswith("blob/"):
            path = path[len("blob/") :]
        elif parsed.netloc != "raw.githubusercontent.com":
            return None
        ref = tag if path.startswith(tag + "/") else path.split("/", 1)[0]
        path = path[len(ref) + 1 :]
    path = posixpath.normpath("/" + path).lstrip("/")
    if not path.lower().endswith((".md", ".markdown")):
        return None
    if not re.search(
        r"change.?log|changes|history|release.?notes|news",
        path + match[1],
        re.IGNORECASE,
    ):
        return None
    return path


def expand_linked_changelog(release, repo, tag):
    body = release.get("body") or ""
    tag = release.get("tag_name") or tag
    path = linked_changelog_path(body, repo, tag)
    if not path or not repo or not tag:
        return release
    # Raw public GitHub content needs no token; never embed a private file.
    url = (
        f"https://raw.githubusercontent.com/{repo}/{quote(tag, safe='')}/{quote(path)}"
    )
    try:
        request = Request(url, headers={"User-Agent": "nixos-config-release-notes"})
        with urlopen(request, timeout=15) as response:
            contents = response.read(250000).decode("utf-8", errors="replace")
    except (URLError, OSError):
        print(
            "Linked changelog could not be fetched; retaining its link.",
            file=sys.stderr,
        )
        return release
    contents = normalize_notes(contents, repo, tag, release.get("html_url", ""), path)
    return {**release, "body": body + "\n\n---\n\n" + contents}


def bound_notes(notes, limit=45000):
    if len(notes.encode()) <= limit:
        return notes
    clipped = notes.encode()[:limit].decode(errors="ignore")
    if "\n" in clipped:
        clipped = clipped.rsplit("\n", 1)[0]
    fence = None
    for line in clipped.splitlines():
        match = FENCE.match(line)
        if match:
            run, rest = match.groups()
            if fence is None:
                fence = run
            elif run[0] == fence[0] and len(run) >= len(fence) and not rest.strip():
                fence = None
    if fence:
        clipped += "\n" + fence
    return (
        clipped
        + "\n\n_Changelog truncated; see the upstream release for the full notes._"
    )


def render(release, repo, tag, old_version, new_version, compare_url):
    release_url = release.get("html_url", "")
    tag = release.get("tag_name") or tag or new_version
    summary = html.escape(f"Release notes for {tag or 'the new version'}")
    lines = ["<details>", f"<summary>{summary}</summary>", ""]
    if release_url:
        lines += [f"[Upstream release]({release_url})", ""]
        body = release.get("body") or "_The upstream release has no notes._"
        lines += [bound_notes(normalize_notes(body, repo, tag, release_url)), ""]
    else:
        lines += [
            f"No upstream GitHub release notes were found for `{new_version}`.",
            "",
        ]
        if compare_url:
            lines += [f"[Compare {old_version} → {new_version}]({compare_url})", ""]
        elif repo:
            lines += [f"[Upstream releases](https://github.com/{repo}/releases)", ""]
    lines += ["</details>", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--package", default="", help="Include the complete update PR header"
    )
    parser.add_argument("--repo", default="")
    parser.add_argument("--tag", default="")
    parser.add_argument("--old-version", default="")
    parser.add_argument("--new-version", required=True)
    parser.add_argument("--compare-url", default="")
    parser.add_argument("--release-json", action="store_true")
    parser.add_argument("--expand-linked-changelog", action="store_true")
    args = parser.parse_args()
    release = json.load(sys.stdin) if args.release_json else {}
    if args.expand_linked_changelog:
        release = expand_linked_changelog(release, args.repo, args.tag)
    if args.package:
        description = f"Updates `{args.package}`"
        if args.old_version and args.new_version:
            description += f" from `{args.old_version}` to `{args.new_version}`"
        elif args.new_version:
            description += f" to `{args.new_version}`"
        print(description + " for x86_64-linux and aarch64-linux.\n")
    print(
        render(
            release,
            args.repo,
            args.tag,
            args.old_version,
            args.new_version,
            args.compare_url,
        )
    )


if __name__ == "__main__":
    main()
