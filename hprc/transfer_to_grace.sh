#!/usr/bin/env bash
##############################################################################
# transfer_to_grace.sh  -  Push the code and DICOM data from this Windows PC
#                          up to TAMU Grace scratch over SSH (rsync).
#
# Run from Git Bash on the local machine:   bash transfer_to_grace.sh
# Uses rsync so re-runs only copy what changed. You will be prompted for your
# Grace password / 2FA unless you have SSH keys set up.
##############################################################################
set -euo pipefail

# ---- EDIT THESE ------------------------------------------------------------
NETID="apad0525"                                   # your TAMU NetID
GRACE="grace.hprc.tamu.edu"
REMOTE_SCRATCH="/scratch/user/${NETID}"            # Grace scratch path

# Local sources (Git Bash paths).
LOCAL_HPRC="/c/Users/apad2/Desktop/repos/hprc"                   # this pipeline
LOCAL_REPO="/c/Users/apad2/Desktop/repos/bipolar_fat_water_separation"
LOCAL_ISMRM="/c/Users/apad2/Desktop/repos/CREAM_PDFF/hernando"   # Hernando toolbox
LOCAL_DICOM="/c/Users/apad2/Desktop/Fat_water_separation/DICOM_Files"
# ---------------------------------------------------------------------------

DEST="${NETID}@${GRACE}:${REMOTE_SCRATCH}"

echo ">> Creating remote folders..."
ssh "${NETID}@${GRACE}" "mkdir -p '${REMOTE_SCRATCH}/Fat_water_separation' '${REMOTE_SCRATCH}/Fat_water_separation/Results' '${REMOTE_SCRATCH}/CREAM_PDFF'"

echo ">> Syncing pipeline code (hprc)..."
rsync -avz --progress "${LOCAL_HPRC}/" "${DEST}/hprc/"

echo ">> Syncing bipolar separator repo..."
rsync -avz --progress \
    --exclude '.git' \
    "${LOCAL_REPO}/" "${DEST}/bipolar_fat_water_separation/"

echo ">> Syncing Hernando ISMRM toolbox..."
rsync -avz --progress \
    --exclude '.git' \
    "${LOCAL_ISMRM}/" "${DEST}/CREAM_PDFF/hernando/"

echo ">> Syncing DICOM data (this is large; only changes are sent)..."
rsync -avz --progress \
    "${LOCAL_DICOM}/DICOM" \
    "${DEST}/Fat_water_separation/"

echo ">> Done. On Grace:  cd ${REMOTE_SCRATCH}/hprc && sbatch grace_first.slurm"
