#!/usr/bin/env bash
##############################################################################
# transfer_from_grace.sh  -  Pull the result .mat files (and PDFF previews)
#                            back from TAMU Grace to this Windows PC over SSH.
#
# Run from Git Bash on the local machine:   bash transfer_from_grace.sh
##############################################################################
set -euo pipefail

# ---- EDIT THESE (match transfer_to_grace.sh) -------------------------------
NETID="apad0525"                                   # your TAMU NetID
GRACE="grace.hprc.tamu.edu"
REMOTE_SCRATCH="/scratch/user/${NETID}"

# Where to drop results locally (kept separate from the DICOM inputs).
LOCAL_RESULTS="/c/Users/apad2/Desktop/Fat_water_separation/Results"
# ---------------------------------------------------------------------------

SRC="${NETID}@${GRACE}:${REMOTE_SCRATCH}/Fat_water_separation/Results/"

mkdir -p "${LOCAL_RESULTS}"

echo ">> Pulling results from Grace..."
rsync -avz --progress "${SRC}" "${LOCAL_RESULTS}/"

echo ">> Done. Results are in ${LOCAL_RESULTS}"
ls -1 "${LOCAL_RESULTS}" | sed 's/^/   /'
