#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../util/prelude.inc.sh"

# This is the justIN counterpart to init.inc.sh / init.data.inc.sh, for
# run_*.sh scripts that are meant to run as a stage of a justIN production
# workflow (e.g. run-cafnusyst/run_cafnusyst.sh) rather than directly on
# NERSC/a local host.
#
# NOTE: We assume this script is sourced from e.g. run-cafnusyst/run_cafnusyst.sh
# with the current working directory being e.g. run-cafnusyst, itself part of
# an ND_Production checkout that the stage's .jobscript placed inside the
# justIN workspace (see run-cafnusyst/run_cafnusyst.jobscript). So:
#   $PWD      == .../<justIN workspace>/ND_Production/run-cafnusyst
#   $baseDir  == .../<justIN workspace>/ND_Production
#   $ND_PRODUCTION_JUSTIN_WORKSPACE == .../<justIN workspace>
#
# Unlike init.inc.sh, this file deliberately does NOT set up
# ND_PRODUCTION_OUTDIR_BASE/ND_PRODUCTION_LOGDIR_BASE: justIN itself manages
# the container and the logs, and uploads whatever output files match the
# --output-pattern given when the stage was created. Output must therefore be
# written directly into $ND_PRODUCTION_JUSTIN_WORKSPACE, alongside a
# justin-processed-dids.txt (see mark_processed below) -- not into some
# ND_PRODUCTION_OUTDIR tree.
#
# See https://justin.dune.hep.ac.uk/docs/jobscripts.md for the justIN-side
# conventions this file implements.
#
# NOTE: this lives under run-cafnusyst/ rather than util/ deliberately, even
# though it isn't cafnusyst-specific in principle: other justIN-based stages
# (e.g. Tammy's toolbox/scripts work) may add their own similarly-purposed
# util/init.justin*.inc.sh, and keeping this one local avoids a collision/
# conflict when that lands. If a shared version emerges later, this can be
# pointed at it (or deleted in favor of it).

if [[ -z "$JUSTIN_PATH" ]]; then
    echo "FATAL: \$JUSTIN_PATH is not set. This script must be run inside a justIN job." >&2
    exit 1
fi

baseDir=$(realpath "$PWD"/..)

ND_PRODUCTION_JUSTIN_WORKSPACE=$(realpath "$baseDir"/..)
export ND_PRODUCTION_JUSTIN_WORKSPACE
echo "ND_PRODUCTION_JUSTIN_WORKSPACE is $ND_PRODUCTION_JUSTIN_WORKSPACE"

run() {
    echo "RUNNING $*"
    time "$@"
}

#-----------------------------------------------------------------------
# Ask justIN for a file to process
#-----------------------------------------------------------------------
did_pfn_rse=$("$JUSTIN_PATH"/justin-get-file)
if [[ -z "$did_pfn_rse" ]]; then
    # Nothing left to process (or not enough wall time left): per the
    # justIN jobscripts checklist, this is not an error.
    echo "justin-get-file returned nothing; no more files to process. Exiting cleanly."
    exit 0
fi

ND_PRODUCTION_DID=$(echo "$did_pfn_rse" | cut -d' ' -f1)
ND_PRODUCTION_PFN=$(echo "$did_pfn_rse" | cut -d' ' -f2)
ND_PRODUCTION_RSE=$(echo "$did_pfn_rse" | cut -d' ' -f3)
export ND_PRODUCTION_DID ND_PRODUCTION_PFN ND_PRODUCTION_RSE
echo "ND_PRODUCTION_DID is $ND_PRODUCTION_DID"
echo "ND_PRODUCTION_PFN is $ND_PRODUCTION_PFN"
echo "ND_PRODUCTION_RSE is $ND_PRODUCTION_RSE"

# ND_PRODUCTION_INDEX: run_genie.sh uses this to number a --monte-carlo
# instance (and seed GENIE from it). Reprocessing stages like this one are
# instead handed one pre-existing file per job by justin-get-file, with no
# such counter available. Derive a stable, deterministic pseudo-index from
# the DID justIN gave us, so any shared code that expects
# $ND_PRODUCTION_INDEX to be set (logging, temp-dir naming, etc.) still has
# something sensible and reproducible to use.
ND_PRODUCTION_INDEX=$(($(echo -n "$ND_PRODUCTION_DID" | cksum | cut -d' ' -f1) % 10000000))
export ND_PRODUCTION_INDEX
echo "ND_PRODUCTION_INDEX (derived from ND_PRODUCTION_DID) is $ND_PRODUCTION_INDEX"

ND_PRODUCTION_INPUT_FILE=$(basename "$ND_PRODUCTION_PFN")
export ND_PRODUCTION_INPUT_FILE

#-----------------------------------------------------------------------
# Fetch the file itself into the justIN workspace. --monte-carlo instances
# (rse == MONTECARLO) have no real file to fetch; only used for jobscript/
# environment testing (c.f. test_justin.jobscript), not real reprocessing.
#-----------------------------------------------------------------------
if [[ "$ND_PRODUCTION_RSE" != "MONTECARLO" ]]; then
    echo "Downloading $ND_PRODUCTION_DID via rucio..."
    (
        source /cvmfs/fermilab.opensciencegrid.org/products/common/etc/setups
        source /cvmfs/dune.opensciencegrid.org/products/dune/setup_dune.sh
        setup python v3_9_15
        setup rucio

        export RUCIO_ACCOUNT=justinreadonly
        rucio download "$ND_PRODUCTION_DID" --dir "$ND_PRODUCTION_JUSTIN_WORKSPACE"

        scope=${ND_PRODUCTION_DID%%:*}
        mv "$ND_PRODUCTION_JUSTIN_WORKSPACE/$scope"/* "$ND_PRODUCTION_JUSTIN_WORKSPACE"/
        rmdir "$ND_PRODUCTION_JUSTIN_WORKSPACE/$scope" 2>/dev/null || true
    )
fi

ND_PRODUCTION_INPUT_PATH=$ND_PRODUCTION_JUSTIN_WORKSPACE/$ND_PRODUCTION_INPUT_FILE
export ND_PRODUCTION_INPUT_PATH

if [[ ! -f "$ND_PRODUCTION_INPUT_PATH" ]]; then
    echo "FATAL: expected input file $ND_PRODUCTION_INPUT_PATH does not exist after fetching." >&2
    exit 1
fi
echo "ND_PRODUCTION_INPUT_PATH is $ND_PRODUCTION_INPUT_PATH"

#-----------------------------------------------------------------------
# Helpers for run_*.sh scripts to properly finish a justIN job. Call
# mark_processed once the output file(s) derived from $ND_PRODUCTION_DID
# have been safely written to $ND_PRODUCTION_JUSTIN_WORKSPACE.
#-----------------------------------------------------------------------
mark_processed() {
    echo "$ND_PRODUCTION_DID" >> "$ND_PRODUCTION_JUSTIN_WORKSPACE/justin-processed-dids.txt"
}

# NOTE: metadata-JSON generation is NOT provided here. toolbox/scripts/
# MetadataExtract.py (the tool CafmakerProduction.jobscript uses) is wired
# internally to UPS (`setup metacat`, `setup python`, etc. inside its own
# subprocess calls), which is not available inside justIN's el9/spack
# container that run_*.sh scripts using this file run in. Each stage's
# run_*.sh is expected to provide its own write_metadata(), matching
# MetaCat's real schema with tools available in its own environment; see
# run-cafnusyst/write_caf_metadata.py + run_cafnusyst.sh for the pattern.
