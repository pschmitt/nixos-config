#!/usr/bin/env python3
"""Podcast feed of the latest tagesschau editions, as published on tagesschau.de.

The official tagesschau podcasts only carry the 20:00 edition. tagesschau.de
publishes every regular edition (12:00, 14:00, 15:00, 17:00, ..., 20:00) as an
MP4 about 15-20 minutes after it aired. This feed lists them newest first, so
a podcast app always has the most recent one.

Discovery: the "letzte Sendung" pages link the newest editions (ts-N.html), and
every edition page links the previous ones. Each edition's JSON
(api2u/<section>/ts-N.json) carries its air time and MP4 URLs.
"""

import json
import os
import re
import threading
import time
import urllib.request
from datetime import datetime, timedelta
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

SITE = "https://www.tagesschau.de"
LISTING_PAGES = [SITE + "/multimedia/letzte_sendung", SITE + "/multimedia"]
EDITION_RE = re.compile(r"/(tagesschau|tagesschau_20_uhr)/ts-(\d+)\.html")
STREAMS = {"webs": "h264s", "webm": "h264m", "webxl": "h264xl"}
QUALITIES = ["webxxl", "webxl", "webm", "webs"]  # fallback order
PREFERRED = os.environ.get("TAGESSCHAU_QUALITY", "webxxl")
KEEP = int(os.environ.get("TAGESSCHAU_ITEMS", "12"))
MAX_AGE = timedelta(hours=int(os.environ.get("TAGESSCHAU_MAX_AGE_HOURS", "48")))
CACHE_TTL = int(os.environ.get("TAGESSCHAU_CACHE_SECONDS", "60"))
REMEMBER = 100  # editions kept in memory between polls

_lock = threading.Lock()
_known = {}  # ts id -> section, accumulated across polls
_editions = {}  # ts id -> (datetime, url) ; immutable once published
_lengths = {}  # url -> content length
_feed = {"at": 0.0, "xml": b""}


def get(url, method="GET"):
    req = urllib.request.Request(url, method=method, headers={"User-Agent": "tagesschau-feed/2"})
    return urllib.request.urlopen(req, timeout=20)


def links(url):
    html = get(url).read().decode("utf-8", "replace")
    return {"ts-" + n: section for section, n in EDITION_RE.findall(html)}


def discover():
    found = {}
    for page in LISTING_PAGES:
        try:
            found.update(links(page))
        except Exception:
            pass
    if not found and not _known:
        raise RuntimeError("no editions found on tagesschau.de")
    # The newest edition page of each section lists the previous editions.
    for section in set(found.values()):
        newest = max((i for i, s in found.items() if s == section), key=lambda i: int(i[3:]))
        try:
            found.update(links("%s/%s/%s.html" % (SITE, section, newest)))
        except Exception:
            pass
    _known.update(found)
    for old in sorted(_known, key=lambda i: int(i[3:]))[:-REMEMBER]:
        del _known[old]


def edition(ts_id):
    if ts_id in _editions:
        return _editions[ts_id]
    data = json.load(get("%s/api2u/%s/%s.json" % (SITE, _known[ts_id], ts_id)))
    if (data.get("title") or "").strip().lower() != "tagesschau":
        return None
    streams = data.get("streams") or {}
    urls = {q: streams[k] for q, k in STREAMS.items() if streams.get(k)}
    if "webxl" in urls:
        # The 1080p file is not in the JSON but sits next to the 720p one.
        urls["webxxl"] = urls["webxl"].replace(".webxl.h264.mp4", ".webxxl.h264.mp4")
    url = None
    for q in [PREFERRED] + [q for q in QUALITIES if q != PREFERRED]:
        try:
            if q in urls and length(urls[q]):
                url = urls[q]
                break
        except Exception:
            continue
    if not url or not data.get("date"):
        return None  # not published yet; retry on the next poll
    _editions[ts_id] = (datetime.fromisoformat(data["date"]), url)
    return _editions[ts_id]


def editions():
    discover()
    now = datetime.now().astimezone()
    found = []
    for ts_id in _known:
        try:
            e = edition(ts_id)
        except Exception:
            e = None
        if e and now - MAX_AGE <= e[0] <= now:
            found.append((e[0], ts_id, e[1]))
    found.sort(reverse=True)
    return found[:KEEP]


def length(url):
    if url not in _lengths:
        _lengths[url] = int(get(url, "HEAD").headers.get("Content-Length", "0"))
    return _lengths[url]


def build():
    items = []
    for ts, ts_id, url in editions():
        try:
            size = length(url)
        except Exception:
            continue
        title = "tagesschau %s Uhr, %s" % (ts.strftime("%H:%M"), ts.strftime("%d.%m.%Y"))
        items.append(
            "<item><title>%s</title><guid isPermaLink=\"false\">%s</guid>"
            "<pubDate>%s</pubDate><link>%s/%s/%s.html</link>"
            "<description>%s</description>"
            "<enclosure url=\"%s\" length=\"%d\" type=\"video/mp4\"/></item>"
            % (escape(title), escape(ts_id), format_datetime(ts),
               SITE, _known[ts_id], escape(ts_id), escape(title), escape(url), size)
        )
    return (
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<rss version=\"2.0\" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"><channel>"
        "<title>tagesschau (alle Ausgaben)</title><link>https://www.tagesschau.de</link>"
        "<language>de</language>"
        "<description>Die jeweils neuesten tagesschau-Ausgaben von tagesschau.de.</description>"
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
