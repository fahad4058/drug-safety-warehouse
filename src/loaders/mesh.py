"""Stream the NLM MeSH descriptor XML into Parquet.

MeSH is the controlled vocabulary that gives free-text conditions a hierarchy.
Each descriptor carries one or more tree numbers -- dotted paths like
C04.588.945 -- and holding more than one means the concept sits in several
branches at once. That is why Step 6's hierarchy is a DAG, not a tree.

Parsed with iterparse and cleared as it goes: the file is a few hundred MB and
ElementTree.parse() would hold the whole document in memory.

Tree numbers stay as an array column. stg_mesh__descriptors is what explodes
them to one row per (descriptor, tree number).

NLM discontinued the ASCII mtrees*.bin serialization in January 2026 -- the XML
is the current distribution and carries the same tree numbers.
"""

import argparse
import gzip
from datetime import datetime, timezone
from pathlib import Path
from xml.etree import ElementTree as ET

import httpx
import pyarrow as pa
import pyarrow.parquet as pq

from _bulk import download

MESH_URL = "https://nlmpubs.nlm.nih.gov/projects/mesh/MESH_FILES/xmlmesh/desc2026.xml"

SCHEMA = pa.schema([
    ("descriptor_ui", pa.string()),
    ("descriptor_name", pa.string()),
    ("tree_numbers", pa.list_(pa.string())),
    ("_pulled_at", pa.string()),
])


def descriptors(xml_path: Path):
    """Yield (ui, name, tree_numbers) per record, freeing memory as we go."""
    opener = gzip.open if xml_path.suffix == ".gz" else open
    with opener(xml_path, "rb") as fh:
        context = ET.iterparse(fh, events=("start", "end"))
        _, root = next(context)
        for event, elem in context:
            if event != "end" or elem.tag != "DescriptorRecord":
                continue
            yield (
                elem.findtext("DescriptorUI"),
                elem.findtext("DescriptorName/String"),
                [t.text for t in elem.findall("TreeNumberList/TreeNumber")],
            )
            elem.clear()
            root.clear()  # drop processed siblings, or the root grows unbounded


def flush(writer: pq.ParquetWriter, rows: list, pulled_at: str) -> None:
    if not rows:
        return
    writer.write_table(pa.Table.from_pydict({
        "descriptor_ui": [r[0] for r in rows],
        "descriptor_name": [r[1] for r in rows],
        "tree_numbers": [r[2] for r in rows],
        "_pulled_at": [pulled_at] * len(rows),
    }, schema=SCHEMA))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=MESH_URL)
    parser.add_argument("--out-dir", type=Path, default=Path("data/mesh"))
    parser.add_argument("--batch-size", type=int, default=5000)
    args = parser.parse_args()

    pulled_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    args.out_dir.mkdir(parents=True, exist_ok=True)

    xml_path = args.out_dir / Path(args.url).name
    out_path = args.out_dir / "mesh_descriptors.parquet"
    tmp_path = out_path.with_name(out_path.name + ".partial")

    if out_path.exists():
        print(f"skip, already written: {out_path.name}")
        return

    if not xml_path.exists():
        print(f"  downloading {args.url}")
        with httpx.Client(timeout=300, follow_redirects=True) as client:
            download(client, args.url, xml_path)
    else:
        print(f"  using cached {xml_path.name}")
    print(f"  {xml_path.stat().st_size / 1e6:.0f} MB on disk")

    n = 0
    batch = []
    writer = pq.ParquetWriter(tmp_path, SCHEMA, compression="snappy")
    try:
        for row in descriptors(xml_path):
            batch.append(row)
            n += 1
            if len(batch) >= args.batch_size:
                flush(writer, batch, pulled_at)
                batch = []
                print(f"  ...{n:,} descriptors", end="\r")
        flush(writer, batch, pulled_at)
    finally:
        writer.close()
    tmp_path.rename(out_path)

    print(f"\n{n:,} descriptors -> {out_path} "
          f"({out_path.stat().st_size / 1e6:.1f} MB parquet)")


if __name__ == "__main__":
    main()
