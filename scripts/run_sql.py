"""
Run a .sql file statement-by-statement against the Databricks SQL warehouse.
Usage: uv run scripts/run_sql.py <file.sql>
Reads DATABRICKS_HOST, DATABRICKS_HTTP_PATH, DBT_ENV_SECRET_DATABRICKS_TOKEN
from the environment (via .env).
"""

import os
import re
import sys

from databricks import sql
from dotenv import load_dotenv

load_dotenv()

host = os.environ["DATABRICKS_HOST"].removeprefix("https://").strip("/")
http_path = os.environ["DATABRICKS_HTTP_PATH"]
token = os.environ["DBT_ENV_SECRET_DATABRICKS_TOKEN"]

text = re.sub(r"--[^\n]*", "", open(sys.argv[1]).read())  # strip -- comments
statements = [s.strip() for s in text.split(";") if s.strip()]

with sql.connect(server_hostname=host, http_path=http_path, access_token=token) as conn:
    with conn.cursor() as cur:
        for stmt in statements:
            print(f">>> {stmt.splitlines()[0]}")
            cur.execute(stmt)
            if cur.description:
                for row in cur.fetchall():
                    print("   ", row)
print("done")
