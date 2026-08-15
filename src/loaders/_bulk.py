"""Shared helpers for openFDA-style bulk downloads.

Both faers and drugsfda pull .zip files holding one JSON document shaped
{"meta": ..., "results": [...]}. Fetching those with retries and streaming
`results` out as NDJSON is identical work, so it lives here.
"""

import gzip
import json
import sys
import time
import zipfile
from pathlib import Path

import httpx
import ijson

MAX_RETRIES = 4
RETRYABLE = {429, 500, 502, 503, 504}


def download(client: httpx.Client, url: str, dest: Path) -> None:
    """Stream a file to disk, retrying transient failures, rename on success."""
    tmp = dest.with_name(dest.name + ".partial")
    delay = 2.0
    for attempt in range(1, MAX_RETRIES + 1):
        with client.stream("GET", url) as resp:
            if resp.status_code not in RETRYABLE:
                resp.raise_for_status()
                with tmp.open("wb") as fh:
                    for chunk in resp.iter_bytes(1 << 20):
                        fh.write(chunk)
                tmp.rename(dest)
                return
            print(f"  HTTP {resp.status_code}; waiting {delay:.0f}s "
                  f"(attempt {attempt}/{MAX_RETRIES})", file=sys.stderr)
        time.sleep(delay)
        delay = min(delay * 2, 60)
    raise RuntimeError(f"gave up downloading {url}")


def stream_zip_to_ndjson(zip_path: Path, out_path: Path, pulled_at: str,
                         prefix: str = "results.item") -> int:
    """Zip -> NDJSON.gz, one record per line, in constant memory."""
    tmp = out_path.with_name(out_path.name + ".partial")
    n = 0
    with zipfile.ZipFile(zip_path) as zf:
        members = [m for m in zf.namelist() if m.endswith(".json")]
        if len(members) != 1:
            raise RuntimeError(f"{zip_path.name}: expected one .json member, got {members}")
        with zf.open(members[0]) as src, gzip.open(tmp, "wt", encoding="utf-8") as out:
            # use_float: ijson yields Decimal otherwise, which json.dumps rejects.
            for record in ijson.items(src, prefix, use_float=True):
                record["_pulled_at"] = pulled_at
                out.write(json.dumps(record, separators=(",", ":")) + "\n")
                n += 1
    tmp.rename(out_path)
    return n
