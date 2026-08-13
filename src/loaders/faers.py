"""Pull openFDA drug-event bulk part-files into gzipped NDJSON.

openFDA publishes adverse-event reports as static CDN files, not through a
query API: discover partitions from the download index, pick quarters, take a
configurable number of parts from each. A part is a .zip holding one JSON
document shaped {"meta": ..., "results": [...]}; we stream `results` out one
report per line so COPY INTO maps one line to one row.

No flattening here. FAERS nests three deep (report -> patient -> drug[] and
reaction[]); unwrapping that is Step 4's work, in tested SQL.
"""

import argparse
import collections
import gzip
import json
import re
import sys
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import httpx
import ijson

INDEX_URL = "https://api.fda.gov/download.json"
QUARTER_RE = re.compile(r"/drug/event/(\d{4})q(\d)/")
MAX_RETRIES = 4
RETRYABLE = {429, 500, 502, 503, 504}


def parse_quarter(text: str) -> tuple[int, int]:
    m = re.fullmatch(r"(\d{4})[qQ]([1-4])", text.strip())
    if not m:
        raise argparse.ArgumentTypeError(f"expected e.g. 2026q2, got {text!r}")
    return int(m.group(1)), int(m.group(2))


def fetch_index(client: httpx.Client) -> list[dict]:
    resp = client.get(INDEX_URL)
    resp.raise_for_status()
    return resp.json()["results"]["drug"]["event"]["partitions"]


def group_by_quarter(partitions: list[dict]) -> dict[tuple[int, int], list[dict]]:
    """Group partitions by (year, quarter). Undated ones are skipped loudly."""
    grouped = collections.defaultdict(list)
    skipped = []
    for p in partitions:
        m = QUARTER_RE.search(p["file"])
        if m:
            grouped[(int(m.group(1)), int(m.group(2)))].append(p)
        else:
            skipped.append(p)
    for parts in grouped.values():
        parts.sort(key=lambda p: p["file"])
    if skipped:
        n = sum(p["records"] for p in skipped)
        print(f"skipping {len(skipped)} undated partitions ({n:,} records, "
              f"openFDA's 'all other data' bucket)", file=sys.stderr)
    return grouped


def download(client: httpx.Client, url: str, dest: Path) -> None:
    """Stream a part-file to disk, retrying transient failures, rename on success."""
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


def stream_part(zip_path: Path, out_path: Path, pulled_at: str) -> int:
    """Zip -> NDJSON.gz, one report per line, in constant memory."""
    tmp = out_path.with_name(out_path.name + ".partial")
    n = 0
    with zipfile.ZipFile(zip_path) as zf:
        members = [m for m in zf.namelist() if m.endswith(".json")]
        if len(members) != 1:
            raise RuntimeError(f"{zip_path.name}: expected one .json member, got {members}")
        with zf.open(members[0]) as src, gzip.open(tmp, "wt", encoding="utf-8") as out:
            # use_float: ijson yields Decimal otherwise, which json.dumps rejects.
            for report in ijson.items(src, "results.item", use_float=True):
                report["_pulled_at"] = pulled_at
                out.write(json.dumps(report, separators=(",", ":")) + "\n")
                n += 1
    tmp.rename(out_path)
    return n


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quarters", nargs="*", type=parse_quarter,
                        help="e.g. 2026q2 2026q1 (default: two most recent in the index)")
    parser.add_argument("--parts", type=int, default=3,
                        help="part-files per quarter (default: 3; a full quarter is ~30)")
    parser.add_argument("--out-dir", type=Path, default=Path("data/faers"))
    parser.add_argument("--keep-zip", action="store_true", help="don't delete part zips")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan and expected record count, download nothing")
    args = parser.parse_args()

    pulled_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    args.out_dir.mkdir(parents=True, exist_ok=True)

    with httpx.Client(timeout=120, follow_redirects=True) as client:
        grouped = group_by_quarter(fetch_index(client))
        quarters = args.quarters or sorted(grouped)[-2:]

        plan = []
        for q in quarters:
            if q not in grouped:
                raise SystemExit(f"quarter {q[0]}q{q[1]} is not in the index")
            plan.extend((q, p) for p in grouped[q][: args.parts])

        expected = sum(p["records"] for _, p in plan)
        mb = sum(float(p["size_mb"]) for _, p in plan)
        for q, p in plan:
            print(f"  {q[0]}q{q[1]}  {Path(p['file']).name}  "
                  f"{p['records']:>7,} records  {float(p['size_mb']):>6.1f} MB")
        print(f"plan: {len(plan)} parts, {expected:,} records, {mb:.0f} MB")
        if args.dry_run:
            return

        total = 0
        skipped = 0
        for q, p in plan:
            stem = Path(p["file"]).name.removesuffix(".json.zip")
            zip_path = args.out_dir / f"{q[0]}q{q[1]}_{stem}.zip"
            out_path = args.out_dir / f"faers_{q[0]}q{q[1]}_{stem}.ndjson.gz"
            if out_path.exists():
                print(f"  skip, already written: {out_path.name}")
                skipped += p["records"]
                continue
            print(f"  downloading {p['file']}")
            download(client, p["file"], zip_path)
            n = stream_part(zip_path, out_path, pulled_at)
            if not args.keep_zip:
                zip_path.unlink()
            flag = "" if n == p["records"] else "  <-- MISMATCH"
            print(f"  {n:,} reports -> {out_path.name} (index said {p['records']:,}){flag}")
            total += n

    print(f"{total:,} reports written, {skipped:,} already present "
          f"(plan total {expected:,})")


if __name__ == "__main__":
    main()
