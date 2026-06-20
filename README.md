# IndPenSim - Industrial Penicillin Fermentation Simulator

A MATLAB/Octave simulator for Penicillin G fed-batch fermentation at 100,000L (100 kL) industrial scale. Originally developed by Stephen Goldrick et al. at University College London, University of Manchester, Newcastle University, and Perceptive Engineering.

**The full source paper is included in this repo: [`indPensim.pdf`](indPensim.pdf)** — read it for the complete model derivation, kinetics, and validation. It is the authoritative description of the underlying model; this README documents how to *run and configure* the code.

**References:**
- Goldrick et al., "The Development of an Industrial Scale Fed-Batch Fermentation Simulation", *Journal of Biotechnology*, 2015. DOI: [10.1016/j.jbiotec.2014.10.029](https://doi.org/10.1016/j.jbiotec.2014.10.029) — included as [`indPensim.pdf`](indPensim.pdf).
- Goldrick et al., "Modern day control challenges for industrial-scale fermentation processes", *Computers and Chemical Engineering*, 2019. DOI: [10.1016/j.compchemeng.2019.05.037](https://doi.org/10.1016/j.compchemeng.2019.05.037)

---

## TL;DR — running any number of batches

1. **Set the campaign** (how many batches, which faults): edit the single line in [`get_fault_batch_run_flags.m`](get_fault_batch_run_flags.m). See [Configuring a campaign](#configuring-a-campaign).
2. **Run it**, one of three ways:
   - **MATLAB / Octave, sequential** — `octave --quiet Generate_Production_Batch_data_V4.m`
   - **Parallel (one Octave process per core)** — `./run_parallel_batches.sh [workers]`
   - **On the provisioned GCP VM** — start it, scale cores to the batch count, run the parallel script, **stop it when done**. See [Running on the GCP VM](#running-on-the-gcp-vm).
3. **Collect output** — one CSV per batch in `output_<N>/batch_csv/`, named `Batch_NN_fault_C.csv`.

There is **one** place to change the number of batches and the fault profile: `get_fault_batch_run_flags.m`. Both the sequential and parallel paths read from it, so they can never drift apart.

---

## Configuring a campaign

Everything about *what* gets generated lives in **`get_fault_batch_run_flags.m`**. The key line is:

```matlab
Batch_run_flags.Batch_fault_order_reference = [repmat(1:8,1,96), repmat(1:4,1,8)];
```

This is a `1 × N` row vector:
- its **length** `N` is the **number of batches**, and
- each **entry** is the **fault code** applied to that batch.

`Num_of_Batches` is derived automatically from the vector length — you never set a count separately.

### How to change the number of batches

Change the length of the vector. Examples (replace the line above):

| Goal | Line |
|------|------|
| 10 fault-free batches | `zeros(1, 10)` |
| 50 batches, all with the aeration fault | `ones(1, 50) * 1` |
| 24 batches cycling through faults 1–8 | `repmat(1:8, 1, 3)` |
| 800 faulty batches (current default) | `[repmat(1:8,1,96), repmat(1:4,1,8)]` |

### How to change fault types

Set the entries to the fault codes you want:

| Code | Fault |
|------|-------|
| `0` | No fault (fault-free) |
| `1` | Aeration rate fault |
| `2` | Vessel back-pressure fault |
| `3` | Substrate feed rate fault |
| `4` | Base flowrate fault |
| `5` | Coolant flowrate fault |
| `6` | All process faults 1–5 combined |
| `7` | Temperature sensor fault |
| `8` | pH sensor fault |

For example, `[0 0 0 1 2]` runs 5 batches: three fault-free, one aeration fault, one pressure fault.

### Other per-batch settings (same file)

These default to sensible values and rarely need changing:

```matlab
Batch_run_flags.Control_strategy = zeros(1, Num_of_Batches); % 0 = recipe-driven (SBC), 1 = operator-controlled
Batch_run_flags.Batch_length     = ones(1, Num_of_Batches);  % 0 = fixed 230 h, 1 = variable length
Batch_run_flags.Raman_spec       = zeros(1, Num_of_Batches); % 0 = no Raman, 1 = record, 2 = use for PAA control
```

---

## Faults — what each one does

Faults are injected in [`fctrl_indpensim.m`](fctrl_indpensim.m). You **invoke** a fault by putting its code in the campaign vector in `get_fault_batch_run_flags.m` (see [Configuring a campaign](#configuring-a-campaign)); e.g. `[0 1 7]` runs a fault-free batch, an aeration-fault batch, and a temperature-sensor-fault batch.

Timing is given as the simulator sample index `k`; with `h = 0.2 h`, **time (h) = k × 0.2** (so `k = 100` ≈ 20 h).

### Process faults — force a manipulated variable to a wrong value during fixed windows

| Code | Name | What it does | Active windows (k → time) |
|------|------|--------------|---------------------------|
| `1` | Aeration rate | Forces aeration `Fg` to **20 L/h** (vs the normal 30–75 L/h ramp), starving oxygen transfer | k 100–120 (20–24 h); k 500–550 (100–110 h) |
| `2` | Vessel back-pressure | Forces head pressure to **2 bar** (vs nominal 0.6–1.1), altering O₂/CO₂ solubility | k 500–520 (100–104 h); k 1000–1200 (200–240 h) |
| `3` | Substrate feed rate | Forces sugar feed `Fs` to **2 L/h** then **20 L/h** (vs scheduled 8–150), starving/limiting the culture | k 100–150 (20–30 h); k 380–460 (76–92 h); k 1000–1070 (200–214 h) |
| `4` | Base flowrate | Forces base feed `Fb` to **5** then **10 L/h**, overriding the pH controller and disturbing pH | k 400–420 (80–84 h); k 700–800 (140–160 h) |
| `5` | Coolant flowrate | Forces cooling-water `Fc` to **2** then **10 L/h**, overriding the temperature controller | k 350–450 (70–90 h); k 1200–1350 (240–270 h) |
| `6` | All process faults | Applies faults **1–5 simultaneously** in the same batch | union of the windows above |

### Sensor faults — bias a measurement so the controller reacts wrongly

The controller acts on a corrupted reading, so the *true* process drifts even though the loop "looks" fine. The bias ramps in linearly between k≈200 and k≈800 (≈40–160 h) and is held to the end.

| Code | Name | What it does |
|------|------|--------------|
| `7` | Temperature sensor | Adds a bias to the **measured** temperature, ramping 0 → **+0.4 K**. The temperature PID then over-cools the real broth. |
| `8` | pH sensor | Adds a bias to the **measured** pH, ramping 0 → **+0.1**. The pH PID then over-doses acid/base. |

In each output CSV, the `Fault_code` column records the fault assigned to that batch (constant per batch). The faults themselves only act within the windows above.

---

## Running the simulator

All three methods produce the **same output**: one CSV per batch in `output_<N>/batch_csv/`, named `Batch_NN_fault_C.csv` (e.g. `Batch_01_fault_1.csv`). No combined CSV, statistics file, or `.mat` file is produced. Each batch takes roughly 1–2 minutes of CPU time.

### Method A — MATLAB or Octave (sequential)

Runs every batch one after another in a single process. Simplest; best for a handful of batches.

```bash
octave --quiet Generate_Production_Batch_data_V4.m
```

Or in MATLAB: open the repo, then run `Generate_Production_Batch_data_V4.m`. (It keeps `Data_generation_flag = 2`, which reads the campaign from `get_fault_batch_run_flags.m`.)

### Method B — Parallel (one Octave process per core)

Runs many batches at once — one independent Octave process per worker. Best for large campaigns and for the VM.

```bash
./run_parallel_batches.sh [workers] [output_dir]
```

- `workers` — number of parallel Octave processes. Defaults to the machine's logical CPU count. **Set this to the number of cores you have** (see VM section).
- `output_dir` — optional; defaults to `output_<N>/batch_csv`.

The script reads the batch count `N` from `get_fault_batch_run_flags.m`, clears any old `Batch_*.csv` in the output dir, runs all `N` batches across the workers, and verifies exactly `N` CSVs were produced.

Check completion manually any time:

```bash
find output_<N>/batch_csv -name 'Batch_*.csv' | wc -l
```

> Octave may print `error: ignoring const execution_exception& while preparing to exit` after a worker finishes. This has been observed even when the CSV was written correctly — validate by counting the `Batch_*.csv` files rather than trusting the absence of this message.

### Running on the GCP VM

A VM named **`octave-matlab`** (zone `asia-south1-c`) is provisioned for fast parallel generation. The workflow is deliberately manual: **you size the cores to the batch count and stop the VM when finished** so it isn't billed idle.

**1. Start the VM:**

```bash
gcloud compute instances start octave-matlab --zone asia-south1-c
```

**2. (Optional) Resize cores to match the campaign.** More batches → more cores. Resize only while the VM is **stopped**:

```bash
gcloud compute instances stop octave-matlab --zone asia-south1-c
gcloud compute instances set-machine-type octave-matlab \
  --machine-type=h4d-standard-192 \
  --zone=asia-south1-c
gcloud compute instances start octave-matlab --zone asia-south1-c
```

`h4d-standard-192` gives 192 full cores (SMT disabled), which suits the independent per-batch workers. If H4D is unavailable in the region, pick any machine type with enough vCPUs.

**3. Copy the repo up** (first time, or after local changes). Copy source only — not the large outputs:

```bash
gcloud compute scp --recurse /Users/kartikey/Desktop/work_products/IndPenSim \
  octave-matlab:~/IndPenSim --zone asia-south1-c
```

**4. Install dependencies** (first time only):

```bash
gcloud compute ssh octave-matlab --zone asia-south1-c
sudo apt update && sudo apt install -y octave git zip
```

**5. Set the campaign and run.** Edit `get_fault_batch_run_flags.m` on the VM, then run the parallel script with workers matched to your cores:

```bash
cd ~/IndPenSim
chmod +x run_parallel_batches.sh
./run_parallel_batches.sh 180     # use 180 first on a 192-core VM; try 192 if stable
```

**6. Zip and download the results:**

```bash
# on the VM
zip -r indpensim_batch_csv.zip output_*/batch_csv

# from your local machine
gcloud compute scp \
  octave-matlab:~/IndPenSim/indpensim_batch_csv.zip ./indpensim_batch_csv.zip \
  --zone asia-south1-c
```

**7. STOP the VM when done** (so it isn't billed while idle):

```bash
gcloud compute instances stop octave-matlab --zone asia-south1-c
```

---

## Output data

Each batch is written as one CSV at 12-minute resolution (`h = 0.2 h`). Batch length is ~230 h, varying slightly when variable length is enabled, so row counts differ a little between batches.

Columns, in order:
- **`Time (h)`**
- **Online + manipulated channels**, each headed `Name(symbol:unit)` — e.g. substrate (S), dissolved O2, O2/CO2 off-gas, dissolved CO2, penicillin (P), volume, weight, pH, temperature, heat, viscosity, OUR, CER, PAA, NH3, and the manipulated variables (aeration Fg, agitator RPM, substrate feed Fs, oil feed Foil, PAA feed Fpaa, acid Fa, base Fb, cooling/heating water Fc/Fh, water injection Fw, pressure, discharge).
- **`Batch_ref`** — the batch number, repeated on every row.
- **`Fault_code`** — the fault code for this batch (0–8), repeated on every row.

Offline measurements (PAA, penicillin, biomass, NH3, viscosity), sampled every 12 h with a 4 h analysis delay, are included as their own channels.

---

## Repository structure

| File | Purpose |
|------|---------|
| `get_fault_batch_run_flags.m` | **Campaign config — the single source of truth.** Sets the number of batches and the per-batch fault schedule. Edit this to change a campaign. |
| `Generate_Production_Batch_data_V4.m` | **Sequential entry point.** Reads the campaign from `get_fault_batch_run_flags.m` and runs all batches in one process. |
| `run_parallel_batches.sh` | **Parallel runner.** One Octave process per worker; reads the batch count from `get_fault_batch_run_flags.m`. |
| `Generate_Single_Batch_CSV.m` | Runs one batch and writes its CSV. Invoked by the parallel runner. |
| `Generate_Batch_records.m` | Post-processing: strips internal states and writes one `Batch_NN_fault_C.csv` per batch. |
| `indpensim_run.m` | **Single-batch wrapper.** Sets control flags, initial conditions, disturbances, and calls the simulator. |
| `indpensim.m` | **Simulation engine.** Main time-stepping loop that calls the controller and ODE solver each sample. |
| `indpensim_ode.m` | **ODE system.** The 33 ordinary differential equations (mass/energy balances, morphology, etc.). |
| `fctrl_indpensim.m` | **Control system.** PID controllers for pH and temperature; sequential batch control (SBC) recipes for all feed rates. |
| `Parameter_list.m` | Assembles the 105-element parameter vector (kinetic, thermodynamic, physical constants). |
| `PIDSimple3.m` | Generic incremental PID controller with saturation limits. |
| `createBatch.m` | Initializes the batch data structure (~60 channels of time-series). |
| `createChannel.m` | Creates a single channel struct (name, units, time vector, data vector). |
| `Raman_Sim.m` | Simulates Raman spectroscopy measurements (optional, disabled by default). |
| `Substrate_prediction.m` | PLS-based PAA prediction from simulated Raman spectra (optional). |
| `csvwrite_with_headers.m` | Utility to write CSV files with a header row. |
| `IndPenSim_QbD_Figure_properties.m` | Plot styling (plotting section is commented out by default). |
| `PAA_PLS_model.mat` | Pre-trained PLS model coefficients for PAA prediction from Raman spectra. |
| `reference_Specra.txt` | Reference Raman spectral baseline (2200 wavenumber points). |

> Generated outputs (`output_*/`, `*.zip`, exported `*.mat`) are intentionally **not** committed — they are large and regenerable. See `.gitignore`.

---

## Exact code flow

### 1. Campaign configuration (`get_fault_batch_run_flags.m` → entry point)

The campaign vector in `get_fault_batch_run_flags.m` defines `Batch_fault_order_reference` (fault code per batch) and the derived `Num_of_Batches`, plus `Control_strategy`, `Batch_length`, and `Raman_spec`. Both entry points read this:

- **Sequential** (`Generate_Production_Batch_data_V4.m`): with `Data_generation_flag = 2` (default), loops `Batch_no = 1:Num_of_Batches`, calls `indpensim_run()` per batch, then `Generate_Batch_records()`. (`Data_generation_flag = 1` instead generates batches to fill a fixed time interval — an older mode, left intact.)
- **Parallel** (`run_parallel_batches.sh` → `Generate_Single_Batch_CSV.m`): runs each batch in its own Octave process, each calling `indpensim_run()` then `Generate_Batch_records()` for its single batch.

### 2. Single batch setup (`indpensim_run.m`)

Called once per batch. Performs three jobs:

#### 2a. Control flags
Translates campaign-level flags into the `Ctrl_flags` struct consumed by the simulator:
- `Inhib = 2` (full inhibition model: DO2, T, pH, CO2, PAA, N)
- `Dis = 1` (process disturbances enabled)
- `Off_line_m = 12` (offline sampling every 12 hours)
- `Off_line_delay = 4` (4-hour analysis delay on offline measurements)
- Temperature set-point: 298 K, pH set-point: 6.5

#### 2b. Randomized initial conditions
No two batches start identically — that batch-to-batch variability is what makes the dataset realistic for analysis and modelling. Each batch gets a unique random seed derived from `Seed_ref + Batch_no + Rand_ref`, so runs are **reproducible** (same batch number → same starting point) yet **varied** across the campaign. Each initial condition is drawn from a normal distribution `N(nominal, std)`; to shift the operating point or widen/narrow the spread, edit these nominal/std values in `indpensim_run.m`:

| Variable | Nominal | Std Dev | Units |
|----------|---------|---------|-------|
| Biomass (X) | 0.5 | 0.05 | g/L |
| mu_x (max) | 0.41 | 0.025 | h^-1 |
| mu_p (max) | 0.041 | 0.0025 | h^-1 |
| Substrate (S) | 1.0 | 0.1 | g/L |
| Dissolved O2 | 15 | 0.5 | mg/L |
| Volume | 58,000 | 500 | L |
| Weight | 62,000 | 500 | kg |
| pH | 6.5 | 0.1 | - |
| Temperature | 297 | 0.5 | K |
| PAA | 1,400 | 50 | mg/L |
| NH3 | 1,700 | 50 | mg/L |
| alpha_kla | 85 | 10 | - |

Batch length: nominally 230 hours, with variation `6*randn` hours when variable length is enabled. Sampling rate `h = 0.2 h` (12 minutes).

#### 2c. Process disturbances
Low-frequency colored noise is generated via a first-order IIR filter (`b=0.005, a=[1, -0.995]`) applied to white noise for 8 disturbance channels:
- Penicillin growth rate (mu_P)
- Biomass growth rate (mu_X)
- Substrate inlet concentration
- Oil inlet concentration
- Acid/base molar concentration
- PAA inlet concentration
- Coolant inlet temperature
- Oxygen inlet concentration

These are stored in `Xinterp` and passed to the simulator as time-varying disturbance signals.

#### 2d. Launch simulation
Calls `Parameter_list()` to build the 105-parameter vector, then:
```matlab
[Xref] = indpensim(@fctrl_indpensim, Xinterp, x0, h, T, 2, par, Ctrl_flags);
```
Solver `2` = `ode15s` (stiff ODE solver). After simulation, calculates penicillin yield statistics.

### 3. Simulation engine (`indpensim.m`)

The core time-stepping loop running `k = 1:N` where `N = T/h` (typically ~1150 steps).

Each time step:

1. **Get control inputs**: Calls `fctrl_indpensim(X, Xd, k, h, T, Ctrl_flags)` which returns the manipulated variable struct `u`.
2. **Assemble state vector**: Builds `x00` (33-element vector) from either initial conditions (k=1) or the previous step's results.
3. **Apply disturbances**: Reads current disturbance values from `Xd` for this time step.
4. **Growth rate adaptation**: If inhibition is enabled and `k > 65`, checks if biomass growth rate has been declining for 63+ consecutive steps. If so, permanently reduces `mu_x_max` to the current value (irreversible damage from prolonged suboptimal conditions).
5. **ODE integration**: Calls `ode15s` over `[t(k), t(k+1)]` with internal step size `h_ode = h/20`:
   ```matlab
   [t_sol, y_sol] = ode15s('indpensim_ode', t(k):h_ode:t(k+1), x00, [], u00, p);
   ```
6. **Numerical stability**: Clamps all state variables to a minimum of 0.001.
7. **Store results**: Saves all 33 ODE states and 12 manipulated variables into the batch struct `X`.
8. **Derived calculations**: Computes OUR (Oxygen Uptake Rate) and CER (Carbon Evolution Rate) from off-gas data.
9. **Optional Raman**: If enabled, generates simulated Raman spectra via `Raman_Sim()`.
10. **Offline measurements**: Every `Off_line_m` hours (12h), records offline measurements of NH3, viscosity, PAA, penicillin, and biomass with a 4-hour delay. All other time steps get NaN for offline channels.

Post-loop: converts internal H+ concentration back to pH scale, converts heat units to kcal.

### 4. ODE system (`indpensim_ode.m`)

Contains the 33 coupled ordinary differential equations representing the bioreactor physics. The system receives the 105-parameter vector and 26-element input vector.

#### State variables (Y(1) through Y(33)):

**Process states:**
- `Y(1)` - Substrate concentration S [g/L]
- `Y(2)` - Dissolved oxygen DO2 [mg/L]
- `Y(3)` - O2 off-gas [%]
- `Y(4)` - Penicillin concentration P [g/L]
- `Y(5)` - Volume V [L]
- `Y(6)` - Weight Wt [kg]
- `Y(7)` - pH (stored as H+ concentration internally)
- `Y(8)` - Temperature T [K]
- `Y(9)` - Generated heat Q [kJ]
- `Y(10)` - Viscosity [cP]

**Morphological model (structured biomass):**
- `Y(11)` - Culture age integral [g/L*h]
- `Y(12)` - A0: growing/branching biomass [g/L]
- `Y(13)` - A1: non-growing/extension biomass [g/L]
- `Y(14)` - A3: degenerated biomass [g/L]
- `Y(15)` - A4: autolysed biomass [g/L]
- `Y(16)-Y(25)` - Vacuole number density functions n0-n9 (10 size bins)
- `Y(26)` - Maximum vacuole volume department
- `Y(27)` - Mean vacuole volume

**Additional species:**
- `Y(28)` - CO2 off-gas [%]
- `Y(29)` - Dissolved CO2 [mg/L]
- `Y(30)` - Phenylacetic acid PAA [mg/L]
- `Y(31)` - Nitrogen NH3 [mg/L]
- `Y(32)` - Current mu_p [h^-1] (diagnostic)
- `Y(33)` - Current mu_x [h^-1] (diagnostic)

#### Key biological equations:

**Structured biomass model:**
Biomass is modeled as four morphological regions of *Penicillium chrysogenum* hyphae:
- **A0 (branching)**: growing tips that branch. Growth rate = `mu_a0 * a1 * s / (K_b + s)`.
- **A1 (extension)**: non-growing regions that extend. Growth rate = `mu_e * a0 * s / (K_e + s)`.
- **A3 (degenerated)**: formed when vacuoles in A1 reach critical size, causing wall rupture.
- **A4 (autolysed)**: dead biomass from A3 autolysis. Rate = `mu_a * a3`.

**Vacuole formation:** Modeled using population balance equations. 10 discrete size bins (Y(16)-Y(25)) track vacuole number density. Vacuoles grow inside A1 regions; when they reach critical size, A1 transitions to A3 (degeneration). The vacuole dynamics use advection-diffusion PDEs discretized in space.

**Penicillin production:**
Penicillin is produced by A1 (non-growing) regions:
```
r_p = mu_p * rho_a0 * v_a1 * P_inhib * DO2_inhib_P * PAA_inhib_P - mu_h * P
```
where `P_inhib` is a Gaussian substrate inhibition term, and `mu_h` is the hydrolysis rate (temperature/pH dependent).

**Inhibition model (flag=2, full):**
All growth rates are multiplied by inhibition terms:
- **pH**: `1 / (1 + H+/K1 + K2/H+)` - optimal near pH 6.5
- **Temperature**: Arrhenius-type `k_g*exp(-Eg/RT) - k_d*exp(-Ed/RT)`
- **Dissolved O2**: Sigmoid `0.5*(1 - tanh(A*(X_crit - DO2)))` - inhibition below critical DO2
- **CO2**: Sigmoid on dissolved CO2 - inhibition above critical level
- **PAA**: Sigmoid - biomass inhibited at high PAA, penicillin production requires minimum PAA
- **Nitrogen**: Sigmoid - biomass inhibited when NH3 drops below critical level

**Oxygen transfer:**
```
kla = alpha_kla * (V_s^a * (P_t/V_m)^b * vis^c) * (1 - oil_f^d)
OTR = kla * (DO2* - DO2)
```
Where `DO2*` is the saturation concentration from Henry's law adjusted for log-mean vessel pressure, and `P_t` is total power input (agitation + aeration).

**Substrate balance:**
```
dS/dt = -growth_consumption - maintenance - penicillin_production + Fs*c_s/V + Foil*c_oil/V - dilution
```

**Volume/Weight:**
Account for all inlet flows (substrate, oil, acid, base, water, PAA), discharge, and evaporation. Evaporation rate depends exponentially on temperature.

**pH model:**
Switches between H+ and OH- balance depending on whether pH is above or below 7. Accounts for acid/base addition, metabolic H+ production from growth and penicillin synthesis.

**Temperature:**
Full energy balance including feed enthalpy, evaporative cooling, reaction heat, agitation power, jacket heat exchange (cooling water + heating water), and convective losses.

### 5. Control system (`fctrl_indpensim.m`)

Called every time step to compute manipulated variables.

#### Closed-loop PID controllers:
- **pH control**: PID controller (`PIDSimple3`) with dead-band of +/- 0.05 around set-point (6.5). If pH drops, adds base (max 225 L/h). If pH rises, adds acid.
- **Temperature control**: PID controller with 0.05 K dead-band around set-point (298 K). Below set-point: activates heating water. Above: activates cooling water.

#### Sequential batch control (SBC) recipes:
Time-varying set-point profiles defined as piecewise-constant schedules:

| Variable | Typical Range | Schedule Points |
|----------|---------------|-----------------|
| Substrate feed (Fs) | 8-150 L/h | Ramps up to 150 L/h at k=120, drops back, slowly increases to ~116 L/h |
| Oil feed (Foil) | 22-35 L/h | Peaks around k=80-280, then gradually decreases |
| Aeration (Fg) | 30-75 L/h | Ramps from 30 to 75 over the batch |
| Pressure | 0.6-1.1 bar | Steps up then slightly decreases |
| Discharge (F_discharge) | 0 or 4000 L/h | Periodic dumps every ~100 steps starting at k=500 |
| Water injection (Fw) | 0-500 L/h | Variable schedule |
| PAA feed (Fpaa) | 0-10 L/h | 5 L/h initially, off for a period, then ~10 L/h, tapering |

#### Optional PRBS (Pseudo-Random Binary Sequence):
When `Control_strategy = 1`, a PRBS signal (+/- noise_factor) is added to Fs and Fpaa after k=500 (every 100 steps) for system identification purposes.

#### Fault injection:
If enabled, overrides specific manipulated variables during defined time windows (e.g., aeration drops to 20 at k=100-120, pressure jumps to 2 bar at k=500-520, etc.). Sensor faults (temperature, pH) add ramp errors to measurements.

### 6. Post-processing (`Generate_Batch_records.m`)

For each batch present in the input struct:

1. **Strip internal states**: Removes non-measurable variables (biomass regions a0-a4, vacuole densities, culture age, internal growth rates, etc.).
2. **Build the time-series matrix**: Time column, every channel whose length matches the time vector, then the `Batch_ref` and `Fault_code` columns.
3. **Write one CSV per batch**: `Batch_NN_fault_C.csv` in the output directory. Runs independently per batch, so parallel workers never collide.

---

## Copyright

Stephen Goldrick. University of Manchester, Newcastle University, Perceptive Engineering, and University College London. All rights reserved.

Please reference: DOI: 10.1016/j.jbiotec.2014.10.029 and https://doi.org/10.1016/j.compchemeng.2019.05.037
