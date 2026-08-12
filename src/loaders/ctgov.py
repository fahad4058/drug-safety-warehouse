"""Pull ClinicalTrials.gov studies (API v2) into gzipped NDJSON.

Cohort: interventional oncology phase 2/3, windowed on LastUpdatePostDate.
Append-only: each pull writes a new file; every line carries a _pulled_at
stamp. Resolving "latest state per study" is dbt's job, not the loader's.
"""

import argparse
import gzip
import json
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import httpx

MAX_RETRIES = 6
RETRYABLE = {429, 500, 502, 503, 504}

BASE_URL = "https://clinicaltrials.gov/api/v2/studies"

FIELDS = ",".join([
    "protocolSection.identificationModule",
    "protocolSection.statusModule",
    "protocolSection.sponsorCollaboratorsModule",
    "protocolSection.conditionsModule",
    "protocolSection.designModule",
    "protocolSection.armsInterventionsModule",
])

def get_with_retry(client: httpx.Client, params: dict) -> httpx.Response:
    """GET with exponential backoff on transient failures.

    429 and 5xx mean "try again later"; 4xx otherwise means the request is
    wrong and retrying would just repeat the mistake.
    """
    delay = 2.0
    for attempt in range(1, MAX_RETRIES + 1):
        resp = client.get(BASE_URL, params=params)
        if resp.status_code not in RETRYABLE:
            resp.raise_for_status()
            return resp
        retry_after = resp.headers.get("Retry-After", "")
        wait = float(retry_after) if retry_after.isdigit() else delay
        print(f"  HTTP {resp.status_code} (Retry-After: {retry_after or 'absent'});"
              f" waiting {wait:.0f}s, attempt {attempt}/{MAX_RETRIES}", file=sys.stderr)
        time.sleep(wait)
        delay = min(delay * 2, 60)
    raise RuntimeError(f"gave up after {MAX_RETRIES} retries; last status {resp.status_code}")


def pull(since: str, until: str, out_dir: Path, page_size: int, sleep: float) -> None:
    pulled_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    file_stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"ctgov_{since}_{file_stamp}.ndjson.gz"
    tmp_path = out_path.with_name(out_path.name + ".partial")

    essie = (
        "AREA[StudyType]INTERVENTIONAL"
        " AND AREA[Phase](PHASE2 OR PHASE3)"
        f" AND AREA[LastUpdatePostDate]RANGE[{since},{until}]"
    )
    params = {
        "query.cond": "cancer",
        "filter.advanced": essie,
        "fields": FIELDS,
        "pageSize": page_size,
        "countTotal": "true",
    }

    n = 0
    total = None
    page_token = None
    with httpx.Client(timeout=60) as client, \
            gzip.open(tmp_path, "wt", encoding="utf-8") as f:
        while True:
            page_params = dict(params)
            if page_token:
                page_params["pageToken"] = page_token
                page_params.pop("countTotal", None)  # count once is enough
            payload = get_with_retry(client, page_params).json()
            if total is None:
                total = payload.get("totalCount")
            for study in payload.get("studies", []):
                study["_pulled_at"] = pulled_at
                f.write(json.dumps(study, separators=(",", ":")) + "\n")
                n += 1
            page_token = payload.get("nextPageToken")
            if not page_token:
                break
            print(f"  ...{n} studies", file=sys.stderr)
            time.sleep(sleep)

    tmp_path.rename(out_path)
    print(f"{n} studies -> {out_path} (API totalCount={total})")

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    default_since = (date.today() - timedelta(days=7)).isoformat()
    parser.add_argument("--since", default=default_since,
                        help="LastUpdatePostDate window start, YYYY-MM-DD (default: 90 days ago)")
    parser.add_argument("--until", default="MAX",
                        help="window end, YYYY-MM-DD or MAX (default: MAX)")
    parser.add_argument("--out-dir", type=Path, default=Path("data/ctgov"))
    parser.add_argument("--page-size", type=int, default=1000,
                        help="studies per API page (max 1000)")
    parser.add_argument("--sleep", type=float, default=1.0,
                        help="seconds to pause between pages (default: 1.0)")
    args = parser.parse_args()
    pull(args.since, args.until, args.out_dir, args.page_size, args.sleep)

if __name__ == "__main__":
    main()
