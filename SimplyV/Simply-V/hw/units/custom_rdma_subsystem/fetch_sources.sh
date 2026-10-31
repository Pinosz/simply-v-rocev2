#!/bin/bash
# Author: Domenico Coppola
# Description:
# This script clones the modified CERN RoCE/RDMA stack (with our dual-mux
# patches on RoCE_minimal_stack.sv and network_wrapper_roce_generic.sv) and
# flattens the SystemVerilog sources into the local rtl/ directory.
#
# IMPORTANT: replace GIT_URL with your fork URL once you create it
# (separate forks for U250 and U280 per the prof's instructions).

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
IP_NAME=$( basename $(dirname $( realpath ${BASH_SOURCE[0]} ) ))

# Create rtl dir (clean it first to avoid stale files from previous runs)
rm -rf rtl
mkdir -p rtl

# Clone repo. The default URL points at the Pinosz fork that contains the
# original CERN stack; if you need the local patches (ext_txmeta_* /
# ext_qp_init_* mux on RoCE_minimal_stack and network_wrapper_roce_generic),
# point GIT_URL at your own fork that includes them.
GIT_URL=https://github.com/Pinosz/SimplyV_Custom_RDMA.git
GIT_BRANCH=u250
CLONE_DIR=SimplyV_Custom_RDMA

printf "${YELLOW}[FETCH_SOURCES $IP_NAME] Cloning source repository${NC}\n"
rm -rf ${CLONE_DIR}
git clone ${GIT_URL} -b ${GIT_BRANCH} ${CLONE_DIR}

# Copy all SystemVerilog/Verilog files into rtl/ in a flattened structure.
# Exclude:
#   - testbenches (tb*.sv, *_tb.sv)
#   - FPGA-board top files (fpga_*.v)  -- we do not need their dev-board tops
LOOKUP_DIR="$PWD/${CLONE_DIR}"
RTL_DIR="$PWD/rtl"

printf "${YELLOW}[FETCH_SOURCES $IP_NAME] Copy all sources into rtl${NC}\n"
find "$LOOKUP_DIR" -type f \( -name "*.sv" -o -name "*.v" -o -name "*.svh" \) \
     ! -name "tb*.sv" \
     ! -name "*_tb.sv" \
     ! -name "fpga_*.v" \
     -print0 | while IFS= read -r -d '' filepath; do
    filename=$(basename "$filepath")
    cp "$filepath" "$RTL_DIR/$filename"
done

# Drop the cloned directory: we only need the flattened copies in rtl/.
rm -rf ${CLONE_DIR}

printf "${GREEN}[FETCH_SOURCES $IP_NAME] Completed${NC}\n"
