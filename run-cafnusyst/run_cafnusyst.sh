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
#     --mql 'files from <caf-dataset-namespace:name>' \
#     --jobscript run_cafnusyst.jobscript \
#     --scope usertests \
#     --image fnal-wn-el9:latest \
#     --output-pattern '*.CAF.root:usertests-w${JUSTIN_WORKFLOW_ID}s${JUSTIN_STAGE_ID}' \
#     --lifetime-days 30 \
#     --env ND_PRODUCTION_NUSYST_CONFIG=default_nusyst_config.yaml

source "$(dirname "${BASH_SOURCE[0]}")/../util/init.justin.inc.sh"

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

write_metadata "$outFile" caf-nusyst root

# Only mark the input DID as processed once the output file (which justIN
# will look for using --output-pattern) is safely in place.
mark_processed

echo "run_cafnusyst.sh finished: $outFile"
