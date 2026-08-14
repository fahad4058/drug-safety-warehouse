"""Pull the Drugs@FDA bulk file into gzipped NDJSON.

Reference data, not events: approved applications with their sponsors,
products, active ingredients and marketing status. One bulk file, nothing to
window or page; the simplest of the four loaders.

One application nests many products, each with many active ingredients.
"""

import argparse
from datetime import datetime, timezone
from pathlib import Path

import httpx

from _bulk import download, stream_zip_to_ndjson

INDEX_URL = "https://api.fda.gov/download.json"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=Path("data/drugsfda"))
    parser.add_argument("--keep-zip", action="store_true", help="don't delete the zip")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan and expected record count, download nothing")
    args = parser.parse_args()

    pulled_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    args.out_dir.mkdir(parents=True, exist_ok=True)

    with httpx.Client(timeout=120, follow_redirects=True) as client:
        resp = client.get(INDEX_URL)
        resp.raise_for_status()
        section = resp.json()["results"]["drug"]["drugsfda"]
        partitions = section["partitions"]

        expected = sum(p["records"] for p in partitions)
        mb = sum(float(p["size_mb"]) for p in partitions)
        for p in partitions:
            print(f"  {Path(p['file']).name}  {p['records']:>7,} records  "
                  f"{float(p['size_mb']):>6.1f} MB")
        print(f"plan: {len(partitions)} file(s), {expected:,} records, {mb:.0f} MB "
              f"(export_date {section.get('export_date')})")
        if args.dry_run:
            return

        total = 0
        already = 0
        for p in partitions:
            stem = Path(p["file"]).name.removesuffix(".json.zip")
            zip_path = args.out_dir / f"{stem}.zip"
            out_path = args.out_dir / f"drugsfda_{stem}.ndjson.gz"
            if out_path.exists():
                print(f"  skip, already written: {out_path.name}")
                already += p["records"]
                continue
            print(f"  downloading {p['file']}")
            download(client, p["file"], zip_path)
            n = stream_zip_to_ndjson(zip_path, out_path, pulled_at)
            if not args.keep_zip:
                zip_path.unlink()
            flag = "" if n == p["records"] else "  <-- MISMATCH"
            print(f"  {n:,} applications -> {out_path.name} "
                  f"(index said {p['records']:,}){flag}")
            total += n

    print(f"{total:,} applications written, {already:,} already present "
          f"(plan total {expected:,})")


if __name__ == "__main__":
    main()
