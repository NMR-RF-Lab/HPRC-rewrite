# Dog fat-water separation — HPRC port

Headless, batch **fat-water separation** for the canine GRE2D_FATWATER DICOM
data, ported to run on **TAMU Grace** (Linux). It uses the bipolar graph-cut
separator and produces **Fat / Water / PDFF / FieldMap / R2\*** — no QSM, no
MEDI. The original request is in [`changes.txt`](changes.txt).

The pipeline itself lives in [`hprc/`](hprc/); see
[`hprc/README.md`](hprc/README.md) for how to run it. Everything else is a
third-party toolbox obtained by cloning (below), not committed here.

## Layout

```
repos/
├── hprc/                          ← the pipeline (this repo's code)
├── changes.txt                    ← original spec
├── bipolar_fat_water_separation/  ← dependency (clone; git-ignored)
├── CREAM_PDFF/                    ← dependency, Hernando toolbox (clone; git-ignored)
├── GRMD/                          ← legacy QSM pipeline (clone; not needed)
└── MEDI-2024.11.26/               ← legacy MEDI toolbox (download; not needed)
```

## Get the dependencies

Clone these as siblings of `hprc/` (i.e. inside this folder). The pinned
commits are the versions this pipeline was built and validated against.

**Required**

```bash
# Bipolar fat-water separator (provides Function_Bipolar_GC)
git clone https://gitlab.com/jacobdegitz/bipolar_fat_water_separation.git
git -C bipolar_fat_water_separation checkout 3cf5dca

# Hernando ISMRM fat-water toolbox (graph-cut engine, in CREAM_PDFF/hernando)
git clone https://github.com/degitz/CREAM_PDFF.git
git -C CREAM_PDFF checkout 7ee4cc6
```

**Legacy (not used by this pipeline; clone only if you need the old QSM code)**

```bash
# Old interactive Windows QSM pipeline
git clone git@github.com:NMR-RF-Lab/GRMD.git
git -C GRMD checkout 84d1f1a
# MEDI toolbox (MEDI-2024.11.26) is a plain download, not a git repo — obtain
# from the Cornell MRI Research Lab MEDI Toolbox page if ever needed.
```

`fw_config.m` finds `bipolar_fat_water_separation/` and `CREAM_PDFF/hernando`
automatically when they sit next to `hprc/`. On Grace, override with
`FWSEP_BIPOLAR_PATH` / `FWSEP_ISMRM_PATH` (the SLURM scripts already do).

## Quick start

```matlab
% Windows smoke test
cd hprc
run_batch('first')     % process + preview the review series (SUSHI 20250506)
```

For the full Grace workflow (transfer up, review, batch, transfer back) see
[`hprc/README.md`](hprc/README.md).
