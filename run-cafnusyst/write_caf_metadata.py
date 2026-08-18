#!/usr/bin/env python3
"""
write_caf_metadata.py: writes a MetaCat sidecar JSON (<input>.json) for a
CAF file produced by run_cafnusyst.sh, matching the real schema used
elsewhere in this pipeline (see toolbox/scripts/MetadataExtract.py) -- but
without any UPS dependency, since run_cafnusyst.sh runs inside justIN's
el9/spack container, where UPS products are not available.

Differences from MetadataExtract.py (documented, not oversights):
  - The checksum is computed locally with Python's zlib.adler32 (the same
    algorithm xrdadler32 implements) instead of shelling out to xrdadler32.
  - The parent file's own MetaCat metadata is NOT fetched (that needs the
    UPS-only `metacat` client), so core.runs / core.runs_subruns are not
    inherited from it and are left empty lists. The parent DID itself is
    still recorded under "parents".
  - Event counts come from PyROOT reading the "cafTree" tree directly (the
    tree cafmaker's own output uses; UpdateReweight is assumed to preserve
    it). If ROOT can't be imported (e.g. this spack build lacks PyROOT
    bindings) or the tree isn't found, counts fall back to -1 rather than
    failing the job, matching how MetadataExtract.py treats a missing file.
"""
import argparse
import json
import os
import sys
import zlib


def event_counts(path):
    try:
        import ROOT
    except ImportError as e:
        print(f"write_caf_metadata.py: WARNING: could not import ROOT ({e}); "
              "event counts will be -1", file=sys.stderr)
        return -1, -1, -1

    try:
        f = ROOT.TFile.Open(path, "READ")
    except OSError as e:
        print(f"write_caf_metadata.py: WARNING: could not open {path} with ROOT "
              f"({e}); event counts will be -1", file=sys.stderr)
        return -1, -1, -1

    if not f or f.IsZombie():
        print(f"write_caf_metadata.py: WARNING: could not open {path} with ROOT; "
              "event counts will be -1", file=sys.stderr)
        return -1, -1, -1

    tree = f.Get("cafTree")
    if not tree:
        print(f"write_caf_metadata.py: WARNING: no cafTree in {path}; "
              "event counts will be -1", file=sys.stderr)
        f.Close()
        return -1, -1, -1

    total = tree.GetEntries()
    f.Close()
    return 0, total - 1, total


def adler32_checksum(path, chunk_size=1 << 20):
    checksum = 1  # zlib.adler32's identity/seed value
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(chunk_size), b""):
            checksum = zlib.adler32(chunk, checksum)
    return format(checksum & 0xffffffff, "08x")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="path to the output CAF file")
    ap.add_argument("--parent-did", required=True, help="DID of the input CAF file this was derived from")
    ap.add_argument("--namespace", required=True, help="MetaCat namespace / Rucio scope")
    ap.add_argument("--data-tier", required=True, help="core.data_tier value, e.g. caf-nusyst")
    ap.add_argument("--workflow-id", default="None")
    ap.add_argument("--site-name", default="None")
    ap.add_argument("--campaign", default="None")
    ap.add_argument("--application-name", default="UpdateReweight")
    ap.add_argument("--application-version", default="None")
    args = ap.parse_args()

    first, last, total = event_counts(args.input)

    metadata = {
        "core.data_tier": args.data_tier,
        "core.data_stream": "simulation",
        "core.file_type": "mc",
        "core.file_format": "root",
        "core.events": total,
        "core.first_event_number": first,
        "core.last_event_number": last,
        "core.file_content_status": "good",
        "core.group": "dune",
        "core.run_type": args.namespace,
        "core.runs": [],
        "core.runs_subruns": [],
        "core.application.family": "cafnusyst",
        "core.application.name": args.application_name,
        "core.application.version": args.application_version,
        "dune.dqc_quality": "unknown",
        "dune.campaign": args.campaign,
        "dune.workflow": {"workflow_id": args.workflow_id, "site_name": args.site_name},
        "dune.output_status": "good",
        "retention.status": "active",
        "retention.class": "physics",
    }

    doc = {
        "name": os.path.basename(args.input),
        "namespace": args.namespace,
        "creator": os.environ.get("USER", "None"),
        "size": os.path.getsize(args.input),
        "metadata": metadata,
        "parents": [{"did": args.parent_did}],
        "checksums": {"adler32": adler32_checksum(args.input)},
    }

    jsonPath = args.input + ".json"
    with open(jsonPath, "w") as fh:
        json.dump(doc, fh, indent=2)
    print(f"write_caf_metadata.py: wrote {jsonPath}")


if __name__ == "__main__":
    main()
