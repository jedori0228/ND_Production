#!/bin/bash
# justIN jobscript for the cafnusyst production stage.
#
# This sets up the cafnusyst/nusystematics/systematicstools/genie spack
# environment (as validated interactively in test_justin.jobscript in this
# same directory), fetches this stage's copy of ND_Production, and hands off
# to run-cafnusyst/run_cafnusyst.sh, which does the actual work: retrieving
# a file via justin-get-file, running UpdateReweight on it, and leaving the
# result (plus metadata, plus justin-processed-dids.txt) in this workspace
# for justIN's wrapper job to pick up.
#
# All stage configuration (which nusyst config to use, etc.) is passed
# through as ND_PRODUCTION_* environment variables via `justin ... --env
# NAME=VALUE`; see the header comment in run_cafnusyst.sh for an example
# submission command.

set -o errexit
set -o pipefail

# justIN provisions /home/workspace as the current working directory, but we
# explicitly cd into it just to be safe.
cd /home/workspace
export CAFNUSYST_WORKSPACE=`pwd`

echo "# Extracting Spack environment from CVMFS..."
# TODO: this points at a one-off build in a user's grid scratch area, which
# is not a stable location for production use. This needs to be replaced
# with a properly versioned/published cafnusyst build (e.g. on CVMFS) before
# this jobscript is used for real production running.
TAR_PATH=${ND_PRODUCTION_CAFNUSYST_TARBALL:-/cvmfs/fifeuser3.opensciencegrid.org/sw/dune/e234edcc6c7dcf9d8b68e23fe61f63b2ad9dd5c0/my_grid_env.tar.gz}
tar -xzf "$TAR_PATH"

export SPACK_USER_CACHE_PATH=/home/workspace/spack-cache

echo "# . /cvmfs/dune.opensciencegrid.org/spack/v1.1.1/setup-env.sh"
. /cvmfs/dune.opensciencegrid.org/spack/v1.1.1/setup-env.sh
echo "# . subspack_base_v1.1.1/setup-env.sh"
. subspack_base_v1.1.1/setup-env.sh

echo "# source \$SPACK_ROOT/load-build_genie_v03_04_02.sh"
source "${SPACK_ROOT}"/load-build_genie_v03_04_02.sh

echo "# Loading gcc, genie, genie-xsec, pythia6, eigen, yaml-cpp, duneanaobj, py-srproxy, cmake"
spack load /wrkusgq        # gcc
spack load genie
spack load genie-xsec
spack load pythia6
export PYTHIA6=$(spack location -i pythia6)/lib
spack load eigen
spack load yaml-cpp


USE_LOCAL_DUNEANAOBJ=true
if [ "$USE_LOCAL_DUNEANAOBJ" = true ] ; then
  echo "# using local duneanaobj, 04.01.00"
  export CMAKE_PREFIX_PATH=${CAFNUSYST_WORKSPACE}/duneanaobj-install/local_v04_01_00:${CMAKE_PREFIX_PATH}
  DUNEANAOBJ_VERSION_NAME=04_01_00
else
  echo "# loading duneanaobj@03.15.00 from spack"
  # duneanaobj 03.15.00
  spack load duneanaobj@03.15.00
  DUNEANAOBJ_VERSION_NAME=03_15_00
fi

spack load py-srproxy
export CPLUS_INCLUDE_PATH="$(spack location -i py-srproxy)/include:$CPLUS_INCLUDE_PATH"
spack load /64q3lof        # cmake

echo "# source systematicstools-build/Linux/bin/setup.systematicstools.sh"
source systematicstools-build/Linux/bin/setup.systematicstools.sh
echo "# source nusystematics-build/Linux/bin/setup.nusystematics.sh"
source nusystematics-build/Linux/bin/setup.nusystematics.sh

echo "# [setup.sh] source cafnusyst-install/for_duneanaobj_${DUNEANAOBJ_VERSION_NAME}/bin/setup.cafnusyst.sh"
source cafnusyst-install/for_duneanaobj_v${DUNEANAOBJ_VERSION_NAME}/bin/setup.cafnusyst.sh

echo "# Fetching ND_Production (${ND_PRODUCTION_GIT_REF:-main})..."
# TODO: confirm this is the right way to get ND_Production onto the worker
# node for production running. Tammy's toolbox/scripts reference a copy of
# ND_Production published under /cvmfs/dune.opensciencegrid.org/dunend/2x2/
# for the 2x2 workflows; if a similar CVMFS-published copy of this repo
# exists/is planned, prefer sourcing run-cafnusyst/ from there instead of a
# runtime git clone (which depends on outbound network access from the
# worker node, and floats with the branch tip unless ND_PRODUCTION_GIT_REF
# is pinned to a tag).
# TODO: Using custom repo/branch for now, until this lands upstream.
git clone --quiet --depth 1 \
    --branch "${ND_PRODUCTION_GIT_REF:-feature/jskim_cafnusyst}" \
    "${ND_PRODUCTION_GIT_REPO:-https://github.com/jedori0228/ND_Production.git}"

cd ND_Production/run-cafnusyst
