# HPRC bipolar fat-water pipeline

Headless, batch fat-water separation for the dog GRE2D_FATWATER DICOM data,
built to run on **TAMU Grace** (Linux) using the **bipolar graph-cut**
separator from the `bipolar_fat_water_separation` repo
(`Function_Bipolar_GC`). It replaces the old interactive Windows pipeline
(`GRMD/AnalysisCode.m`, `DogAnalysis.m`, `dogexplorer.m`) for this task and
produces **Fat, Water, PDFF, FieldMap, R2\*** only — **no QSM, no MEDI
toolbox**.

This `hprc/` folder is the only original code here; the separator and the
Hernando ISMRM toolbox are cloned dependencies (see the top-level README for
clone instructions). `fw_config.m` locates them as sibling clones by default
and via `FWSEP_BIPOLAR_PATH` / `FWSEP_ISMRM_PATH` on the cluster.

## What it does

1. Scans the DICOM tree for every `GRE2D_FATWATER_*` magnitude series (the
   `_0012`, `_0014`, … folders; phase is the next series number).
2. Processes the **last SUSHI date first**
   (`20250506/GRE2D_FATWATER_SUSHI_0012`) and writes a PDFF preview so you can
   confirm it looks right.
3. After you approve, processes the other 15 series in a batch.
4. Saves one `.mat` per series (`struct res` with Fat/Water/PDFF/FieldMap/R2\*).
5. You pull the results back over SSH.

## Files

| File | Role |
|------|------|
| `fw_config.m` | All paths + parameters. **Edit here** (or set env vars). |
| `find_series.m` | Locate the 16 magnitude series, review series first. |
| `load_fatwater_dicom.m` | Read a mag+phase `.IMA` series → complex image, TE, voxel size, B0. |
| `make_bodymask.m` | Automatic body mask (replaces interactive ROI drawing). |
| `separate_one.m` | Run `Function_Bipolar_GC` on one series → maps + PDFF. |
| `run_batch.m` | Headless driver. `run_batch('first'|'rest'|'all')`. |
| `save_pdff_preview.m` | Write a PDFF PNG montage (no display needed). |
| `grace_first.slurm` / `grace_rest.slurm` | SLURM jobs for Grace. |
| `transfer_to_grace.sh` / `transfer_from_grace.sh` | rsync data up / results down. |

## One-time setup (required)

1. **Clone the two dependencies** as siblings of this folder (see top-level
   README for URLs/commits): `bipolar_fat_water_separation` (the separator)
   and `CREAM_PDFF` (its `hernando/` subfolder is the ISMRM graph-cut engine).
   `fw_config.m` finds them by default; `run_batch` adds them to the path and
   warns if missing; `transfer_to_grace.sh` copies them up to Grace.
   (`matlab_bgl` inside `hernando` uses MEX max-flow; the Linux `glnxa64`
   builds — including `max_flow_mex.mexa64` — are already present, so it runs
   on Grace as-is.)
2. **Fill in your details** in:
   - `grace_first.slurm` / `grace_rest.slurm`: `--account`, `MATLAB_MODULE`,
     and the three `FWSEP_*` paths.
   - `transfer_to_grace.sh` / `transfer_from_grace.sh`: `NETID` (currently
     `apad0525`) and local paths.
   Run `module spider MATLAB` on Grace to get the exact module name. Any
   **R2019a or newer** MATLAB works (the separator only needs `lsqlin` from the
   Optimization Toolbox and the `size(x,1:3)` syntax); validated on **R2024a**.
3. **Required MATLAB toolboxes:** Image Processing, Optimization, Parallel
   Computing. `run_batch` checks `license('test', ...)` and warns if any are
   not exposed by the loaded module.

## Run it

Local smoke test on Windows (uses the paths in `fw_config.m`):

```matlab
cd hprc
run_batch('first')     % just the SUSHI review series
```

On Grace:

```bash
# from Git Bash on your PC
bash transfer_to_grace.sh          # push code + DICOM up

# from a Grace login node
cd $SCRATCH/hprc
sbatch grace_first.slurm           # process + preview the review series
#   ... inspect $FWSEP_OUTPUT_ROOT/20250506__..._PDFF.png ...
sbatch grace_rest.slurm            # process the other 15

# back on your PC
bash transfer_from_grace.sh        # pull Results/*.mat back
```

## Tutorial: manual terminal walkthrough (no helper scripts)

This is the same workflow the helper scripts automate, but as individual
commands you run by hand — useful if you drive Grace from a terminal
(e.g. MobaXterm), don't have the local Git Bash rsync set up, or want to see
exactly what each step does. It assumes TAMU Grace and the 8-core usage limit.
Everything hangs off `$SCRATCH`, so you never need to hard-code your NetID.

### 1. Put the two dependency repos on Grace

Clone them directly on Grace (faster than uploading) at the pinned commits:

```bash
cd $SCRATCH
git clone https://gitlab.com/jacobdegitz/bipolar_fat_water_separation.git
git clone https://github.com/degitz/CREAM_PDFF.git

# sanity check — these two paths must exist:
ls $SCRATCH/bipolar_fat_water_separation/Functions
ls $SCRATCH/CREAM_PDFF/hernando
```

### 2. Put this `hprc/` folder on Grace

Zip the `hprc` folder on your PC, upload `hprc.zip` with MobaXterm's SFTP
panel into `$SCRATCH`, then unzip:

```bash
cd $SCRATCH
unzip -o hprc.zip
ls $SCRATCH/hprc/fw_config.m        # confirm files are here, not nested one level deep
# if you see $SCRATCH/hprc/hprc/, flatten it:
#   mv $SCRATCH/hprc/hprc/* $SCRATCH/hprc/ && rmdir $SCRATCH/hprc/hprc
```

### 3. Put one DICOM series on Grace

For the first run you only need the review series **and its phase sibling**
(`_0012` magnitude + `_0013` phase) under their date folder. Zip the `20250506`
folder on your PC, upload it, and unzip into the DICOM root:

```bash
mkdir -p $SCRATCH/Fat_water_separation/DICOM_Files/DICOM
cd $SCRATCH/Fat_water_separation/DICOM_Files/DICOM
unzip -o $SCRATCH/20250506.zip
ls 20250506                         # must show ..._SUSHI_0012 AND ..._SUSHI_0013
ls 20250506/GRE2D_FATWATER_SUSHI_0012 | head   # must show *.IMA files
```

### 4. Load MATLAB and confirm the toolboxes

```bash
module purge
module load Matlab/R2024a           # exact name from: module avail 2>&1 | grep -i matlab
matlab -nodisplay -batch "disp([license('test','optimization_toolbox'), license('test','image_toolbox'), license('test','distrib_computing_toolbox')])"
# expect:  1   1   1
```

### 5. Point the pipeline at your paths

`fw_config.m` reads these environment variables, so you configure the run
without editing any code:

```bash
export FWSEP_DICOM_ROOT=$SCRATCH/Fat_water_separation/DICOM_Files/DICOM
export FWSEP_OUTPUT_ROOT=$SCRATCH/Fat_water_separation/Results
export FWSEP_BIPOLAR_PATH=$SCRATCH/bipolar_fat_water_separation
export FWSEP_ISMRM_PATH=$SCRATCH/CREAM_PDFF/hernando
mkdir -p "$FWSEP_OUTPUT_ROOT"
```

### 6. Submit the review series from the command line

Don't run the separation on a login node — it's heavy (~3 h at 384×384). Submit
a batch job entirely from the terminal with `sbatch --wrap`, so you need
neither an interactive session nor the `.slurm` files. Replace `<ACCOUNT>` with
your allocation from `myproject -l`:

```bash
sbatch --job-name=fwsep_first --account=<ACCOUNT> --partition=medium \
  --time=05:00:00 --nodes=1 --ntasks=1 --cpus-per-task=8 --mem=60G \
  --output=fwsep_first_%j.out --error=fwsep_first_%j.err \
  --wrap="module purge; module load Matlab/R2024a; \
export FWSEP_DICOM_ROOT=$SCRATCH/Fat_water_separation/DICOM_Files/DICOM; \
export FWSEP_OUTPUT_ROOT=$SCRATCH/Fat_water_separation/Results; \
export FWSEP_BIPOLAR_PATH=$SCRATCH/bipolar_fat_water_separation; \
export FWSEP_ISMRM_PATH=$SCRATCH/CREAM_PDFF/hernando; \
cd $SCRATCH/hprc; matlab -nodisplay -nosplash -batch \"run_batch('first')\""
```

> A batch job (SLURM) runs on a compute node independent of your SSH session —
> you can close MobaXterm and it keeps going. If instead you want an
> interactive node to debug on, grab one and run by hand:
> ```bash
> srun --account=<ACCOUNT> --partition=medium --time=05:00:00 \
>      --nodes=1 --ntasks=1 --cpus-per-task=8 --mem=60G --pty bash
> # then inside the node: the module load + exports from step 5 + step 4, then
> cd $SCRATCH/hprc && matlab -nodisplay -nosplash -batch "run_batch('first')"
> ```

### 7. Watch it

```bash
squeue -u $USER                                  # ST=R means running
tail -f fwsep_first_*.out                         # live log; Ctrl-C to stop watching
grep -c 'slice of interest' fwsep_first_*.out     # slices done in the dual-GC phase
grep -E 'succeeded|elapsed' fwsep_first_*.out     # summary + per-series time when done
```

### 8. Review, then run the rest

```bash
ls "$FWSEP_OUTPUT_ROOT"                           # want ..._0012.mat + ..._0012_PDFF.png
head -c 20 "$FWSEP_OUTPUT_ROOT"/*SUSHI*.mat        # "MATLAB 5.0 MAT-file" = v7 saved OK
```

Open the `_PDFF.png` (MobaXterm previews it over SFTP). If fat/water look
swapped everywhere, set `cfg.PrecessionIsClockwise = -1` in `fw_config.m`,
re-upload, and rerun step 6. If it looks right, upload the **full** `DICOM/`
tree the same way as step 3, size the walltime from the first-series `elapsed`
(≈ per-series seconds × 15 × 1.4), and submit the batch:

```bash
sbatch --job-name=fwsep_rest --account=<ACCOUNT> --partition=long \
  --time=3-00:00:00 --nodes=1 --ntasks=1 --cpus-per-task=8 --mem=60G \
  --output=fwsep_rest_%j.out --error=fwsep_rest_%j.err \
  --wrap="module purge; module load Matlab/R2024a; \
export FWSEP_DICOM_ROOT=$SCRATCH/Fat_water_separation/DICOM_Files/DICOM; \
export FWSEP_OUTPUT_ROOT=$SCRATCH/Fat_water_separation/Results; \
export FWSEP_BIPOLAR_PATH=$SCRATCH/bipolar_fat_water_separation; \
export FWSEP_ISMRM_PATH=$SCRATCH/CREAM_PDFF/hernando; \
cd $SCRATCH/hprc; matlab -nodisplay -nosplash -batch \"run_batch('rest')\""
```

### 9. Get the results back

Scratch is auto-purged, so pull the `.mat` files to your PC. From **your PC's**
terminal (Git Bash / MobaXterm local shell), or just drag them out of the SFTP
panel:

```bash
rsync -avz "<NETID>@grace.hprc.tamu.edu:/scratch/user/<NETID>/Fat_water_separation/Results/" \
      "/c/Users/apad2/Desktop/Fat_water_separation/Results/"
```

## Assumptions (verify these)

- **Magnitude = even series id, phase = id+1.** True for all 16 series here
  (`_0012` magnitude / `_0013` phase). Matches the lab's `loadima.m`.
- **7 echoes, 50 slices, 192×192, 3T**, ΔTE ≈ 1.28 ms, phase rescale
  slope 2 / intercept −4096 → [−π, π]. Read live from the headers, so other
  series with different geometry still work.
- **`PrecessionIsClockwise = 1`** for this data. If Fat and Water come out
  swapped everywhere in the review series, flip it to `-1` in `fw_config.m`.
  This is the main thing the review step exists to catch.
- **Fat model** in `fw_config.m` is the reference 6-peak peanut-oil model.
  Swap in an in-vivo canine fat model if you have one.
- One series has 351 files instead of 350 (`20250501/..._WAYLON_0012`); the
  loader warns and keeps the last image per (echo, slice), which is fine.
- **The scan finds 16 magnitude series** (SUSHI 20250506 first + 15). Most
  dates hold the series directly under `<date>/`, but `20240711/` nests two
  dogs a level deeper (`Aphrodite/` and `Selene/`); the recursive scan handles
  both and gives each a unique tag (e.g.
  `20240711__Aphrodite__GRE2D_FATWATER_APHRODITE_0012`). Nothing runs until you
  approve the first series, so review the printed list first.

## Notes on the old pipeline

`GRMD/` (AnalysisCode.m, DogInitialize.m, DogAnalysis.m, dogexplorer.m,
Images/+DI, +BC, +BFR) implemented the full QSM chain and depended on MEDI for
bipolar correction, `Fit_ppm_complex`, and dipole inversion. Dropping QSM
removes every MEDI dependency, so the `MEDI-2024.11.26` toolbox is no longer
needed for this workflow. Those scripts are left untouched but are **not used**
by this pipeline.
