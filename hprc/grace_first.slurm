#!/bin/bash
##############################################################################
# grace_first.slurm  -  Process ONLY the review series (last SUSHI date) on
#                       TAMU Grace, then stop so you can confirm it looks OK.
#
# Submit from a Grace login node:   sbatch grace_first.slurm
# Check progress:                   squeue -u $USER   /   tail -f fwsep_first_*.out
##############################################################################
#SBATCH --job-name=fwsep_first
#SBATCH --time=05:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=60G
#SBATCH --output=fwsep_first_%j.out
#SBATCH --error=fwsep_first_%j.err
### ---- EDIT THESE ----------------------------------------------------------
#SBATCH --account=ACCOUNT_XXXXXX        # your Grace allocation (module load; 'myproject')
# 384x384 before-separation zero-fill makes one series ~3h, over the 2h 'short'
# cap, so an explicit partition is required. 'medium' allows 24h.
#SBATCH --partition=medium
##############################################################################

set -euo pipefail

# ---- EDIT: MATLAB module ---------------------------------------------------
# Run `module spider MATLAB` on Grace to see exact names, then set below.
# R2019a+ is sufficient (only lsqlin / size(x,1:3) are needed); R2024a is used.
MATLAB_MODULE="Matlab/R2024a"

# ---- EDIT: where the code and data live on Grace ---------------------------
# This pipeline (the hprc folder you rsync'd up).
export FWSEP_HPRC="$SCRATCH/hprc"
# Bipolar separator repo and Hernando ISMRM toolbox (cloned dependencies).
export FWSEP_BIPOLAR_PATH="$SCRATCH/bipolar_fat_water_separation"
export FWSEP_ISMRM_PATH="$SCRATCH/CREAM_PDFF/hernando"
# DICOM root = folder containing the per-date folders (…/DICOM).
export FWSEP_DICOM_ROOT="$SCRATCH/Fat_water_separation/DICOM_Files/DICOM"
# Where results are written.
export FWSEP_OUTPUT_ROOT="$SCRATCH/Fat_water_separation/Results"
# ---------------------------------------------------------------------------

export FWSEP_MODE="first"

module purge
module load "$MATLAB_MODULE"

mkdir -p "$FWSEP_OUTPUT_ROOT"
cd "$FWSEP_HPRC"

echo "Host: $(hostname)   Job: $SLURM_JOB_ID   CPUs: $SLURM_CPUS_PER_TASK"
matlab -nodisplay -nosplash -batch "run_batch('first')"

echo "First-series run complete. Review \$FWSEP_OUTPUT_ROOT, then submit grace_rest.slurm."
