"""Drop GPS-spike trackpoints from a GPX file before upload.

A spike is a single trkpt that implies an implausible speed on BOTH its
incoming and outgoing leg (haversine distance / time delta) - a device
briefly losing satellite lock and teleporting, then snapping back. Only
dropping points anomalous on both legs is deliberate: a real point right
after a pause/resume gap is anomalous on one leg only and must survive.
Two adjacent spike points that jump to roughly the same wrong spot will
not be caught (the leg between them looks normal) - this is a conservative
filter, not a general outlier remover.

Processing is per <trkseg>, so segment boundaries are never compared
across. Everything outside a removed trkpt's exact text span (extensions,
namespaces, formatting) is preserved byte-for-byte.

Usage:
  fix-gpx-spikes [--verbose] <input.gpx> <output.gpx>
  fix-gpx-spikes [--verbose] --dry-run <input.gpx>

Prints the number of (would-be) removed points to stdout. When any points
are removed, a before/after total-distance summary is printed to stderr;
--dry-run writes nothing; --verbose additionally prints time/coords/speed
for each hit to stderr, for sanity-checking the threshold against real
archives before wiring this into anything unattended.
"""

import argparse
import itertools
import math
import os
import re
import sys
from datetime import datetime

MAX_SPEED_MPS = float(os.environ.get("GPX_MAX_SPEED_MPS", "25"))  # ~90 km/h
MAX_PASSES = 5

TRKSEG_RE = re.compile(r"<trkseg\b[^>]*>.*?</trkseg>", re.DOTALL)
TRKPT_RE = re.compile(r"<trkpt\b[^>]*?(?:/>|>.*?</trkpt>)", re.DOTALL)
LAT_RE = re.compile(r'lat="([-0-9.]+)"')
LON_RE = re.compile(r'lon="([-0-9.]+)"')
TIME_RE = re.compile(r"<time>([^<]+)</time>")


def haversine(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(
        dlambda / 2
    ) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def parse_point(block):
    lat = LAT_RE.search(block)
    lon = LON_RE.search(block)
    time = TIME_RE.search(block)
    if not lat or not lon or not time:
        return None
    try:
        t = datetime.fromisoformat(time.group(1).replace("Z", "+00:00"))
    except ValueError:
        return None
    return float(lat.group(1)), float(lon.group(1)), t


def find_spikes(points):
    """Return (index, speed_in_mps, speed_out_mps) for each spike point."""
    spikes = []
    for i in range(1, len(points) - 1):
        prev, cur, nxt = points[i - 1], points[i], points[i + 1]
        if prev is None or cur is None or nxt is None:
            continue
        dt_in = (cur[2] - prev[2]).total_seconds()
        dt_out = (nxt[2] - cur[2]).total_seconds()
        if dt_in <= 0 or dt_out <= 0:
            continue
        speed_in = haversine(prev[0], prev[1], cur[0], cur[1]) / dt_in
        speed_out = haversine(cur[0], cur[1], nxt[0], nxt[1]) / dt_out
        if speed_in > MAX_SPEED_MPS and speed_out > MAX_SPEED_MPS:
            spikes.append((i, speed_in, speed_out))
    return spikes


def total_distance(text):
    dist = 0.0
    prev = None
    for m in TRKPT_RE.finditer(text):
        pt = parse_point(m.group(0))
        if pt is None:
            continue
        if prev is not None:
            dist += haversine(prev[0], prev[1], pt[0], pt[1])
        prev = pt
    return dist


def remove_spans(text, spans):
    out = []
    pos = 0
    for start, end in sorted(spans):
        out.append(text[pos:start])
        pos = end
    out.append(text[pos:])
    return "".join(out)


def clean_segment(seg_text, seg_index):
    details = []
    for _ in range(MAX_PASSES):
        matches = list(TRKPT_RE.finditer(seg_text))
        if len(matches) < 3:
            break
        points = [parse_point(m.group(0)) for m in matches]
        spikes = find_spikes(points)
        if not spikes:
            break
        for idx, speed_in, speed_out in spikes:
            lat, lon, t = points[idx]
            details.append(
                {
                    "segment": seg_index,
                    "time": t.isoformat(),
                    "lat": lat,
                    "lon": lon,
                    "speed_in_mps": speed_in,
                    "speed_out_mps": speed_out,
                }
            )
        spans = [matches[idx].span() for idx, _, _ in spikes]
        seg_text = remove_spans(seg_text, spans)
    return seg_text, details


def process(text):
    """Return (cleaned_text, details) for the whole GPX document."""
    all_details = []
    seg_counter = itertools.count()

    def repl(m):
        cleaned, details = clean_segment(m.group(0), next(seg_counter))
        all_details.extend(details)
        return cleaned

    if TRKSEG_RE.search(text):
        cleaned_text = TRKSEG_RE.sub(repl, text)
    else:
        cleaned_text, all_details = clean_segment(text, 0)

    return cleaned_text, all_details


def report(details):
    for d in details:
        print(
            "  segment {segment}: {time} "
            "({lat:.6f}, {lon:.6f}) "
            "in={speed_in_mps:.1f} m/s "
            "out={speed_out_mps:.1f} m/s".format(**d),
            file=sys.stderr,
        )


def main():
    parser = argparse.ArgumentParser(
        description="Drop GPS-spike trackpoints from a GPX file."
    )
    parser.add_argument("input", help="input GPX file")
    parser.add_argument(
        "output", nargs="?", help="output GPX file (omit with --dry-run)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would be removed, write nothing",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="print time/coords/speed for each (would-be) removed point",
    )
    args = parser.parse_args()

    if not args.dry_run and not args.output:
        parser.error("output.gpx is required unless --dry-run")

    with open(args.input, encoding="utf-8") as fh:
        text = fh.read()

    cleaned_text, details = process(text)

    if details:
        d_before = total_distance(text)
        d_after = total_distance(cleaned_text)
        print(
            "distance: {:.3f} km -> {:.3f} km "
            "(-{:.3f} km via {} point(s))".format(
                d_before / 1000,
                d_after / 1000,
                (d_before - d_after) / 1000,
                len(details),
            ),
            file=sys.stderr,
        )

    if args.verbose:
        report(details)

    if not args.dry_run:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(cleaned_text)

    print(len(details))
    return 0


if __name__ == "__main__":
    sys.exit(main())
