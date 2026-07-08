#!/bin/bash
##############################################################################
# grace_rest.slurm  -  Process the remaining 15 series on TAMU Grace AFTER you
#                      have reviewed the first one from grace_first.slurm.
#
# Submit from a Grace login node:   sbatch grace_rest.slurm
##############################################################################
#SBATCH --job-name=fwsep_rest
#SBATCH --time=3-00:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=60G
#SBATCH --output=fwsep_rest_%j.out
#SBATCH --error=fwsep_rest_%j.err
### ---- EDIT THESE ----------------------------------------------------------
#SBATCH --account=ACCOUNT_XXXXXX        # your Grace allocation
# At ~3h/series x15 (~45h) the 384x384 batch exceeds the 24h 'medium' cap, so
# use 'long' (7-day limit). Refine --time from the first-series elapsed time.
#SBATCH --partition=long
##############################################################################

set -euo pipefail

# ---- EDIT: same values as grace_first.slurm --------------------------------
MATLAB_MODULE="Matlab/R2024a"
export FWSEP_HPRC="$SCRATCH/hprc"
export FWSEP_BIPOLAR_PATH="$SCRATCH/bipolar_fat_water_separation"
export FWSEP_ISMRM_PATH="$SCRATCH/CREAM_PDFF/hernando"
export FWSEP_DICOM_ROOT="$SCRATCH/Fat_water_separation/DICOM_Files/DICOM"
export FWSEP_OUTPUT_ROOT="$SCRATCH/Fat_water_separation/Results"
# ---------------------------------------------------------------------------

export FWSEP_MODE="rest"

module purge
module load "$MATLAB_MODULE"

mkdir -p "$FWSEP_OUTPUT_ROOT"
cd "$FWSEP_HPRC"

echo "Host: $(hostname)   Job: $SLURM_JOB_ID   CPUs: $SLURM_CPUS_PER_TASK"
matlab -nodisplay -nosplash -batch "run_batch('rest')"

echo "All remaining series complete. Pull results back with transfer_from_grace.sh."
