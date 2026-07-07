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
   Run `module spider MATLAB` on Grace to get the exact module name — the
   Optimization Toolbox needs **MATLAB R2026a or newer** (see repo README).
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
