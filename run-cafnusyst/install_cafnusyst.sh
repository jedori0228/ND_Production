. /cvmfs/dune.opensciencegrid.org/spack/v1.1.1/setup-env.sh

# gcc
#     wrkusgq gcc@12.5.0 platform=linux os=almalinux9 target=x86_64_v3%gcc@11.5.0
spack load /wrkusgq
export LD_LIBRARY_PATH="$(spack location -i /wrkusgq)/lib64:$LD_LIBRARY_PATH"

# genie
#     6aokbh5 genie@3.06.02 platform=linux os=almalinux9 target=x86_64_v3%gcc@12.5.0
spack load /6aokbh5

# genie-xsec
spack load genie-xsec

# pythia6
#     vrxmo2i pythia6@6.4.28 platform=linux os=almalinux9 target=x86_64_v3%gcc@12.5.0
spack load /vrxmo2i
export PYTHIA6=`spack location -i /vrxmo2i`/lib

# eigen
#     7lgtjja eigen@3.4.1 platform=linux os=almalinux9 target=x86_64_v3%gcc@12.5.0
spack load /7lgtjja

# yaml-cpp
#    xsxa2rq yaml-cpp@0.8.0 platform=linux os=almalinux9 target=x86_64_v3%gcc@12.5.0
spack load /xsxa2rq

# duneanaobj 03.15.00
#     pau2evj duneanaobj@03.15.00 platform=linux os=almalinux9 target=x86_64_v3%gcc@12.5.0
spack load /pau2evj

# srproxy
spack load /dv3vwu6
#    dv3vwu6 py-srproxy@00.45 platform=linux os=almalinux9 target=x86_64_v3nonenone
export CPLUS_INCLUDE_PATH="$(spack location -i /dv3vwu6)/include:$CPLUS_INCLUDE_PATH"


# build nusystematics

git clone git@github.com:NuSystematics/nusystematics.git -b feature/YAML nusystematics-src
mkdir nusystematics-build; cd nusystematics-build
cmake ../nusystematics-src -Dnusyst_DOWNLOAD_DATA=OFF
make install -j4

source Linux/bin/setup.systematicstools.sh
source Linux/bin/setup.nusystematics.sh
export NUSYST_DATA_DIR=/exp/dune/data/users/jskim/NuSyst/nusyst_data
cd ../


# build cafnusyst

git clone git@github.com:jedori0228/cafnusyst.git cafnusyst-src -b feature/init_v03_15_00

mkdir cafnusyst-build; cd cafnusyst-build
cmake ../cafnusyst-src/
make install -j4

source Linux/bin/setup.cafnusyst.sh
cd ../
