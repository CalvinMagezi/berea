"""Polite, sequential downloads of the CC0 narration, each recorded in a manifest."""

import hashlib
import json
import re
import time
import urllib.request
from pathlib import Path

import encode

NARRATORS = {"souer": "https://openbible.com/audio/souer/"}
AUDIO_LICENCE = (
    "CC0 1.0. The Holy Bible, Berean Standard Bible, BSB audio narrated by Bob Souer, "
    "dedicated to the public domain (https://bereanbible.com/audio/)"
)
USER_AGENT = "Berea build tool (https://github.com/CalvinMagezi/berea)"
# openbible.com serves the files for free; one request at a time with a pause between.
PAUSE_SECONDS = 2.0
TIMEOUT_SECONDS = 120
CHUNK_BYTES = 1 << 20
HTTP_OK = 200


def get(url: str) -> urllib.request.addinfourl:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    return urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS)


def file_name(listing: str, book: int, chapter: int) -> str:
    """The narration's own name for a chapter, from its directory listing (BSB_43_Jhn_003.mp3)."""
    m = re.search(rf'href="(BSB_{book:02d}_[A-Za-z0-9]+_{chapter:03d}\.mp3)"', listing)
    if m is None:
        raise ValueError(f"no narration file for book {book} chapter {chapter}")
    return m[1]


def listing(narrator: str, cache: Path) -> str:
    path = cache / "listing.html"
    if not path.exists():
        cache.mkdir(parents=True, exist_ok=True)
        with get(NARRATORS[narrator]) as r:
            path.write_bytes(r.read())
    return path.read_text()


def fetch_chapter(narrator: str, book: int, chapter: int, cache: Path) -> Path:
    """Downloads one chapter unless the manifest already vouches for the file on disk."""
    name = file_name(listing(narrator, cache), book, chapter)
    path = cache / name
    manifest_path = cache / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    entry = manifest.get(name)
    if entry and path.exists() and _sha256(path) == entry["sha256"]:
        return path
    url = NARRATORS[narrator] + name
    time.sleep(PAUSE_SECONDS)
    tmp = path.with_suffix(".part")
    try:
        _download(url, tmp)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    tmp.rename(path)
    duration_ms = encode.duration_ms(str(path))
    if duration_ms <= 0:
        path.unlink()
        raise ValueError(f"{url}: not playable audio")
    manifest[name] = {
        "url": url,
        "licence": AUDIO_LICENCE,
        "sha256": _sha256(path),
        "bytes": path.stat().st_size,
        "duration_ms": duration_ms,
    }
    manifest_path.write_text(json.dumps(manifest, indent=1, sort_keys=True))
    return path


def _download(url: str, dest: Path) -> None:
    """Refuses a short body: urllib does not raise when the server closes early."""
    with get(url) as r, dest.open("wb") as out:
        expected = r.headers.get("Content-Length")
        while chunk := r.read(CHUNK_BYTES):
            out.write(chunk)
    if r.status != HTTP_OK or expected is None or dest.stat().st_size != int(expected):
        raise OSError(f"{url}: incomplete download ({dest.stat().st_size} of {expected} bytes)")


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(CHUNK_BYTES):
            h.update(chunk)
    return h.hexdigest()
