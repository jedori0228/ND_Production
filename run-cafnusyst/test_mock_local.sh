#!/usr/bin/env bash
# test_mock_local.sh: a fast, offline sanity check for run_cafnusyst.sh's
# control flow (env var handling, path construction, UpdateReweight
# invocation, justin-processed-dids.txt output) that runs on any machine
# with plain bash + python3 -- no DUNE software, no justin, no cafnusyst,
# no network required.
#
# It fakes:
#   - $JUSTIN_PATH/justin-get-file (returns a fixed DID/PFN, rse=MONTECARLO
#     so init.justin.inc.cafnusyst.sh's real `rucio download` step is skipped)
#   - UpdateReweight (just touches whatever -o path it's given)
#   - a placeholder nusyst config file
#
# write_caf_metadata.py itself is NOT faked -- it runs for real, against the
# (empty, fake) output file. Without PyROOT available it still produces
# valid metadata JSON with event counts of -1 (a real, intentional fallback
# path -- see write_caf_metadata.py); with PyROOT available but no cafTree
# in the fake output, same result. Either way this confirms the script
# doesn't crash and the JSON shape is right; it does NOT confirm real event
# counts get filled in correctly (needs a real cafTree, i.e. real testing).
#
# This does NOT exercise: the real cafnusyst spack environment, the real
# rucio download, the real UpdateReweight binary, or justIN's actual job
# matching/upload machinery. For that, see the "real" testing steps in the
# comment at the bottom of this file (justin-test-jobscript, then a small
# real `justin simple-workflow` submission), which need to be run on a
# machine with the DUNE justin client set up (e.g. a dunegpvm).
#
# Usage: ./test_mock_local.sh

set -euo pipefail

repoRoot=$(realpath "$(dirname "${BASH_SOURCE[0]}")"/..)
work=$(mktemp -d)
echo "Mock justIN workspace: $work"

mkdir -p "$work/ND_Production" "$work/justin-bin" "$work/fake-bin"
cp -r "$repoRoot/run-cafnusyst" "$work/ND_Production/"
cp -r "$repoRoot/util" "$work/ND_Production/"

cat > "$work/justin-bin/justin-get-file" <<'EOF'
#!/usr/bin/env bash
echo "usertests:fake_input.CAF.root /nonexistent/fake_input.CAF.root MONTECARLO"
EOF
chmod +x "$work/justin-bin/justin-get-file"

cat > "$work/fake-bin/UpdateReweight" <<'EOF'
#!/usr/bin/env bash
echo "[fake UpdateReweight] args: $*"
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    -c|-i) shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$out" ]] && touch "$out"
EOF
chmod +x "$work/fake-bin/UpdateReweight"

: > "$work/fake_input.CAF.root"
: > "$work/ND_Production/run-cafnusyst/default_nusyst_config.yaml"

export JUSTIN_PATH="$work/justin-bin"
export PATH="$work/fake-bin:$PATH"

cd "$work/ND_Production/run-cafnusyst"
bash ./run_cafnusyst.sh

echo
echo "=== $work contents after run ==="
ls -la "$work"
echo
echo "=== justin-processed-dids.txt ==="
cat "$work/justin-processed-dids.txt" 2>/dev/null || { echo "MISSING"; exit 1; }
echo
echo "=== metadata json ==="
cat "$work"/*.json 2>/dev/null || { echo "MISSING"; exit 1; }
echo
echo "OK: mock run completed. Inspect $work for details, delete it when done."

# --- Real testing, once you have DUNE justin set up (e.g. on a dunegpvm) ---
#
# 1) justin-test-jobscript: runs the real jobscript (real spack setup, real
#    cafnusyst build, real container) locally, against one real input file,
#    without submitting to the grid:
#
#      source /cvmfs/dune.opensciencegrid.org/products/dune/setup_dune.sh
#      setup justin
#      justin get-token   # first time / if your session expired
#
#      MQL='files from <namespace>:<cafmaker-dataset> where core.data_tier=caf limit 1'
#      justin-test-jobscript --mql "$MQL" \
#        --jobscript run_cafnusyst.jobscript \
#        --env ND_PRODUCTION_NUSYST_CONFIG=default_nusyst_config.yaml \
#        --env ND_PRODUCTION_NAMESPACE=neardet-2x2-lar \
#        --env ND_PRODUCTION_CAMPAIGN=<campaign-name>
#
#    This prints the workspace directory it ran in (under /tmp) so you can
#    inspect the output CAF file, its .json (real MetaCat schema -- check
#    core.events isn't -1, meaning PyROOT + the cafTree lookup worked), and
#    justin-processed-dids.txt.
#
# 2) Once that's clean, do one real small-scale grid submission (a single
#    job) before trusting it at scale:
#
#      justin simple-workflow --mql "$MQL" \
#        --jobscript run_cafnusyst.jobscript \
#        --scope usertests --image fnal-wn-el9:latest \
#        --output-pattern '*.CAF.root:output-test' \
#        --lifetime-days 1 \
#        --env ND_PRODUCTION_NUSYST_CONFIG=default_nusyst_config.yaml \
#        --env ND_PRODUCTION_NAMESPACE=neardet-2x2-lar \
#        --env ND_PRODUCTION_CAMPAIGN=<campaign-name>
#
#    then watch it on the justIN dashboard (https://dunejustin.fnal.gov/dashboard/)
#    using the workflow ID it prints.
