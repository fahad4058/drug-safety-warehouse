"""
Run a .sql file statement-by-statement against the Databricks SQL warehouse.

Usage: uv run scripts/run_sql.py <file.sql> [--csv] [--max-rows N]

Reads DATABRICKS_HOST, DATABRICKS_HTTP_PATH, DBT_ENV_SECRET_DATABRICKS_TOKEN
from the environment (via .env).

Without --csv only --max-rows rows are fetched, so a stray SELECT * against a
raw table can't drag the whole warehouse into memory.
"""

import argparse
import csv
import os
import re
from pathlib import Path

from databricks import sql
from dotenv import load_dotenv

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("file", type=Path)
parser.add_argument("--csv", action="store_true",
                    help="fetch all rows and write them to query_output/")
parser.add_argument("--max-rows", type=int, default=20,
                    help="rows to print when not writing CSV (default: 20)")
args = parser.parse_args()

load_dotenv()

host = os.environ["DATABRICKS_HOST"].removeprefix("https://").strip("/")
http_path = os.environ["DATABRICKS_HTTP_PATH"]
token = os.environ["DBT_ENV_SECRET_DATABRICKS_TOKEN"]

text = re.sub(r"--[^\n]*", "", args.file.read_text())  # strip -- comments
statements = [s.strip() for s in text.split(";") if s.strip()]

with sql.connect(server_hostname=host, http_path=http_path, access_token=token) as conn:
    with conn.cursor() as cur:
        for i, stmt in enumerate(statements, 1):
            print(f">>> {stmt.splitlines()[0]}")
            cur.execute(stmt)
            if not cur.description:
                continue
            if args.csv:
                rows = cur.fetchall()
                out_dir = Path("query_output")
                out_dir.mkdir(exist_ok=True)
                path = out_dir / f"{args.file.stem}_{i:02d}.csv"
                with path.open("w", newline="") as fh:
                    writer = csv.writer(fh)
                    writer.writerow([d[0] for d in cur.description])
                    writer.writerows(rows)
                print(f"    wrote {len(rows):,} rows -> {path}")
            else:
                rows = cur.fetchmany(args.max_rows + 1)
                for row in rows[: args.max_rows]:
                    print("   ", row)
                if len(rows) > args.max_rows:
                    print(f"    ... more rows not shown "
                          f"(--max-rows {args.max_rows}, --csv for all)")
print("done")
