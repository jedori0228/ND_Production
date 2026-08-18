#!/usr/bin/env bash

# run_cafnusyst.sh: runs cafnusyst's UpdateReweight over one CAF file (from
# the run-cafmaker stage) to add interaction reweights, as a stage of a DUNE
# justIN production workflow.
#
# Unlike most other run_*.sh scripts in this repo, this script does not
# manage its own container -- justIN does that (--image), and
# run_cafnusyst.jobscript sets up the spack/cafnusyst environment before
# invoking this script -- and it does not write into $ND_PRODUCTION_OUTDIR_BASE:
# output is written straight into the justIN workspace so justIN's wrapper
# job can find and upload it (see util/init.justin.inc.sh).
#
# Configuration is read from ND_PRODUCTION_* environment variables, in
# keeping with the rest of this repo (c.f. run-genie/run_genie.sh). These
# would normally be set at submission time via
# `justin simple-workflow --env NAME=VALUE ...`, e.g.:
#
#   justin simple-workflow \
#     --mql 'files from <namespace>:<cafmaker-dataset> where core.data_tier=caf' \
#     --jobscript run_cafnusyst.jobscript \
#     --scope usertests \
#     --image fnal-wn-el9:latest \
#     --output-pattern '*.CAF.root:usertests-w${JUSTIN_WORKFLOW_ID}s${JUSTIN_STAGE_ID}' \
#     --lifetime-days 30 \
#     --env ND_PRODUCTION_NUSYST_CONFIG=default_nusyst_config.yaml \
#     --env ND_PRODUCTION_NAMESPACE=neardet-2x2-lar \
#     --env ND_PRODUCTION_CAMPAIGN=<campaign-name>
#
# The `where core.data_tier=caf` clause selects only cafmaker's non-flat
# *.CAF.root output (assuming cafmaker was itself submitted with
# `--tier caf`, SubmitProductionJustIn.py's default for that stage --
# confirm this against how it's actually run before relying on it). This
# script also refuses to process a *.flat.root file defensively, in case
# that filter is missing or wrong (see below).

source "$(dirname "${BASH_SOURCE[0]}")/../util/init.justin.inc.sh"

# Refuse a flat CAF file even if the submission's --mql didn't filter it
# out: this stage is meant to consume cafmaker's non-flat *.CAF.root only.
case "$(basename "$ND_PRODUCTION_INPUT_PATH")" in
    *.flat.root)
        echo "FATAL: got a flat CAF file ($ND_PRODUCTION_INPUT_PATH); this stage only processes non-flat *.CAF.root." >&2
        exit 1
        ;;
esac

# write_metadata <dataFile> <dataTier>
#
# Writes the MetaCat sidecar JSON for an output file via the sibling
# write_caf_metadata.py (see that file for why this doesn't reuse
# toolbox/scripts/MetadataExtract.py directly: it's wired to UPS, which
# isn't available in this el9/spack container).
write_metadata() {
    local dataFile=$1 dataTier=$2
    python3 "$(dirname "${BASH_SOURCE[0]}")/write_caf_metadata.py" \
        --input "$dataFile" \
        --parent-did "$ND_PRODUCTION_DID" \
        --namespace "${ND_PRODUCTION_NAMESPACE:-neardet-2x2-lar}" \
        --data-tier "$dataTier" \
        --workflow-id "${JUSTIN_WORKFLOW_ID:-None}" \
        --site-name "${JUSTIN_SITE_NAME:-None}" \
        --campaign "${ND_PRODUCTION_CAMPAIGN:-None}" \
        --application-name UpdateReweight
}

# ND_PRODUCTION_NAMESPACE: MetaCat namespace / Rucio scope for the output's
# metadata -- TODO: neardet-2x2-lar matches CafmakerProduction.jobscript by
# pattern-matching, not confirmed; verify before relying on it.
export ND_PRODUCTION_NAMESPACE=${ND_PRODUCTION_NAMESPACE:-neardet-2x2-lar}

# ND_PRODUCTION_DATA_TIER: core.data_tier value recorded in the output's
# metadata. Deliberately distinct from cafmaker's own tiers ("caf" for the
# non-flat file, "caf-flat-analysis" for the flat one).
export ND_PRODUCTION_DATA_TIER=${ND_PRODUCTION_DATA_TIER:-caf-nusyst}

# ND_PRODUCTION_NUSYST_CONFIG: the cafnusyst/nusystematics config (yaml)
# naming which knobs to reweight, resolved relative to this directory unless
# given as an absolute path.
# TODO: no config has been finalized for production use yet; the default
# below is a placeholder and must be replaced once one is agreed on.
export ND_PRODUCTION_NUSYST_CONFIG=${ND_PRODUCTION_NUSYST_CONFIG:-default_nusyst_config.yaml}
configFile=$ND_PRODUCTION_NUSYST_CONFIG
[[ "$configFile" != /* ]] && configFile=$PWD/$configFile

if [[ ! -f "$configFile" ]]; then
    echo "FATAL: nusyst config file $configFile does not exist." >&2
    exit 1
fi

# ND_PRODUCTION_OUTPUT_SUFFIX: appended to the input CAF file's basename to
# form the output filename, e.g. foo.CAF.root -> foo.NUSYST.CAF.root
export ND_PRODUCTION_OUTPUT_SUFFIX=${ND_PRODUCTION_OUTPUT_SUFFIX:-NUSYST}

inputCafFile=$ND_PRODUCTION_INPUT_PATH
outName=$(basename "$inputCafFile" .root).$ND_PRODUCTION_OUTPUT_SUFFIX.root
outFile=$ND_PRODUCTION_JUSTIN_WORKSPACE/$outName
echo "outFile is $outFile"

# UpdateReweight takes a text file listing its input file(s), not the CAF
# file directly.
inputList=$(mktemp)
echo "$inputCafFile" > "$inputList"

run UpdateReweight -c "$configFile" -i "$inputList" -o "$outFile"

rm -f "$inputList"

if [[ ! -f "$outFile" ]]; then
    echo "FATAL: UpdateReweight did not produce the expected output file $outFile" >&2
    exit 1
fi

write_metadata "$outFile" "$ND_PRODUCTION_DATA_TIER"

# Only mark the input DID as processed once the output file (which justIN
# will look for using --output-pattern) is safely in place.
mark_processed

echo "run_cafnusyst.sh finished: $outFile"
