#!/usr/bin/env python3
"""Podcast feed of the latest tagesschau editions, as published in the ARD Mediathek.

The official tagesschau podcasts only carry the 20:00 edition (and late). This
feed lists every regular edition that has already aired (09:00, 12:00, 15:00,
...), newest first, so a podcast app always has the most recent one.
"""

import json
import os
import re
import threading
import time
import urllib.request
from datetime import datetime, timezone
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

GROUPING = (
    "https://api.ardmediathek.de/page-gateway/pages/ard/grouping/"
    "Y3JpZDovL2Rhc2Vyc3RlLmRlL3RhZ2Vzc2NoYXU?embedded=true"
)
ITEM = "https://api.ardmediathek.de/page-gateway/pages/ard/item/{}?devicetype=pc&embedded=true"
TITLE_RE = re.compile(r"^tagesschau \d\d:\d\d Uhr")
SKIP_RE = re.compile(r"Gebärden|einfacher Sprache|Audiodeskription", re.I)
QUALITIES = ["webm", "webl", "webs", "webxl", "webxxl"]  # preference order
PREFERRED = os.environ.get("TAGESSCHAU_QUALITY", "webm")
KEEP = int(os.environ.get("TAGESSCHAU_ITEMS", "12"))
CACHE_TTL = int(os.environ.get("TAGESSCHAU_CACHE_SECONDS", "60"))
BASE = os.environ.get("TAGESSCHAU_BASE_URL", "https://tagesschau.brkn.lol")

_lock = threading.Lock()
_listing = {"at": 0.0, "teasers": []}
_media = {}  # item id -> (url, length) ; immutable once published
_feed = {"at": 0.0, "xml": b""}


def get(url, method="GET"):
    req = urllib.request.Request(url, method=method, headers={"User-Agent": "tagesschau-feed/1"})
    return urllib.request.urlopen(req, timeout=20)


def parse_ts(value):
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def editions():
    if time.time() - _listing["at"] > CACHE_TTL:
        data = json.load(get(GROUPING))
        teasers = []
        for widget in data.get("widgets", []):
            teasers.extend(widget.get("teasers", []))
        _listing.update(at=time.time(), teasers=teasers)
    now = datetime.now(timezone.utc)
    found = []
    for t in _listing["teasers"]:
        title = t.get("longTitle") or t.get("title") or ""
        when = t.get("broadcastedOn")
        if not when or not TITLE_RE.match(title) or SKIP_RE.search(title):
            continue
        ts = parse_ts(when)
        if ts <= now:
            found.append((ts, title, t["id"]))
    found.sort(reverse=True)
    return found[:KEEP]


def media(item_id):
    if item_id in _media:
        return _media[item_id]
    raw = get(ITEM.format(item_id)).read().decode()
    urls = set(re.findall(r"https://[^\"\\ ]+\.web[a-z]+\.h264\.mp4", raw))
    by_q = {re.search(r"\.(web[a-z]+)\.h264", u).group(1): u for u in urls}
    order = [PREFERRED] + [q for q in QUALITIES if q != PREFERRED]
    url = next((by_q[q] for q in order if q in by_q), None)
    if not url:
        return None
    length = int(get(url, "HEAD").headers.get("Content-Length", "0"))
    _media[item_id] = (url, length)
    return _media[item_id]


def build():
    items = []
    for ts, title, item_id in editions():
        try:
            m = media(item_id)
        except Exception:
            m = None
        if not m:
            continue
        url, length = m
        items.append(
            "<item><title>%s</title><guid isPermaLink=\"false\">%s</guid>"
            "<pubDate>%s</pubDate><link>https://www.ardmediathek.de/video/%s</link>"
            "<description>%s</description>"
            "<enclosure url=\"%s\" length=\"%d\" type=\"video/mp4\"/></item>"
            % (escape(title), escape(item_id), format_datetime(ts),
               escape(item_id), escape(title), escape(url), length)
        )
    return (
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<rss version=\"2.0\" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"><channel>"
        "<title>tagesschau (alle Ausgaben)</title><link>https://www.tagesschau.de</link>"
        "<language>de</language>"
        "<description>Die jeweils neuesten tagesschau-Ausgaben aus der ARD Mediathek.</description>"
        "<itunes:author>ARD</itunes:author><itunes:explicit>false</itunes:explicit>"
        + "".join(items) + "</channel></rss>"
    ).encode()


def feed():
    with _lock:
        if time.time() - _feed["at"] > CACHE_TTL or not _feed["xml"]:
            try:
                _feed.update(at=time.time(), xml=build())
            except Exception:
                if not _feed["xml"]:
                    raise
                _feed["at"] = time.time() - CACHE_TTL + 10  # serve stale, retry soon
        return _feed["xml"]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] in ("/", "/feed.xml", "/feed"):
            try:
                body = feed()
            except Exception as exc:
                self.send_error(502, str(exc)[:100])
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/rss+xml; charset=utf-8")
            self.send_header("Cache-Control", "public, max-age=30")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)

    do_HEAD = do_GET

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8089"))
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
