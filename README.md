# IndPenSim - Industrial Penicillin Fermentation Simulator

A MATLAB-based simulator for Penicillin G fed-batch fermentation at 100,000L (100 kL) industrial scale. Originally developed by Stephen Goldrick et al. at University College London, University of Manchester, Newcastle University, and Perceptive Engineering.

**References:**
- Goldrick et al., "The Development of an Industrial Scale Fed-Batch Fermentation Simulation", *Journal of Biotechnology*, 2015. DOI: [10.1016/j.jbiotec.2014.10.029](https://doi.org/10.1016/j.jbiotec.2014.10.029)
- Goldrick et al., "Modern day control challenges for industrial-scale fermentation processes", *Computers and Chemical Engineering*, 2019. DOI: [10.1016/j.compchemeng.2019.05.037](https://doi.org/10.1016/j.compchemeng.2019.05.037)

---

## Repository Structure

| File | Purpose |
|------|---------|
| `Generate_Production_Batch_data_V4.m` | **Top-level entry point.** Configures campaign settings and loops over batches. |
| `indpensim_run.m` | **Single-batch wrapper.** Sets control flags, initial conditions, disturbances, and calls the simulator. |
| `indpensim.m` | **Simulation engine.** Main time-stepping loop that calls the controller and ODE solver each sample. |
| `indpensim_ode.m` | **ODE system.** Contains all 33 ordinary differential equations (mass/energy balances, morphology, etc.). |
| `fctrl_indpensim.m` | **Control system.** PID controllers for pH and temperature; sequential batch control (SBC) recipes for all feed rates. |
| `Parameter_list.m` | Assembles the 105-element parameter vector (kinetic, thermodynamic, physical constants). |
| `PIDSimple3.m` | Generic incremental PID controller with saturation limits. |
| `createBatch.m` | Initializes the batch data structure (~60 channels of time-series). |
| `createChannel.m` | Creates a single channel struct (name, units, time vector, data vector). |
| `Raman_Sim.m` | Simulates Raman spectroscopy measurements (optional, disabled in current config). |
| `Substrate_prediction.m` | PLS-based PAA prediction from simulated Raman spectra (optional). |
| `Generate_Batch_records.m` | Post-processing: strips internal states, exports batch records to `.mat` and `.csv`. |
| `IndPenSim_QbD_Figure_properties.m` | Plot styling (currently commented out in main script). |
| `csvwrite_with_headers.m` | Utility to write CSV files with header rows. |
| `PAA_PLS_model.mat` | Pre-trained PLS model coefficients for PAA prediction from Raman spectra. |
| `reference_Specra.txt` | Reference Raman spectral baseline (2200 wavenumber points). |

---

## Exact Code Flow

### 1. Campaign Configuration (`Generate_Production_Batch_data_V4.m`)

This is the entry point. It defines the production campaign:

- **`Data_generation_flag`**: `1` = generate batches for a fixed time interval, `2` = generate a fixed number of batches.
- **`Batch_run_flags`** struct configures per-batch settings:
  - `Batch_fault_order_reference` - fault code per batch (0=none, 1=aeration, 2=pressure, 3=substrate, 4=base, 5=coolant, 6=all, 7=temp sensor, 8=pH sensor)
  - `Control_strategy` - 0=recipe-driven SBC, 1=operator-controlled
  - `Batch_length` - 0=fixed at 230h, 1=variable (+/- random deviation)
  - `Raman_spec` - 0=disabled, 1=record spectra, 2=use spectra for PAA control

The main loop iterates `Batch_no = 1:Num_of_Batches`, calling `indpensim_run()` for each batch and storing results in `Raw_Batch_data.Batch_XX`. After all batches complete, it calls `Generate_Batch_records()` to export data.

**Current configuration:** 100 batches, all fault-free, recipe-driven (SBC), variable batch length, no Raman.

### 2. Single Batch Setup (`indpensim_run.m`)

Called once per batch. Performs three jobs:

#### 2a. Control Flags
Translates campaign-level flags into the `Ctrl_flags` struct consumed by the simulator:
- `Inhib = 2` (full inhibition model: DO2, T, pH, CO2, PAA, N)
- `Dis = 1` (process disturbances enabled)
- `Off_line_m = 12` (offline sampling every 12 hours)
- `Off_line_delay = 4` (4-hour analysis delay on offline measurements)
- Temperature set-point: 298 K, pH set-point: 6.5

#### 2b. Randomized Initial Conditions
Each batch gets a unique random seed derived from `Seed_ref + Batch_no + Rand_ref`. Initial conditions are drawn from normal distributions around nominal values:

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

#### 2c. Process Disturbances
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

#### 2d. Launch Simulation
Calls `Parameter_list()` to build the 105-parameter vector, then:
```matlab
[Xref] = indpensim(@fctrl_indpensim, Xinterp, x0, h, T, 2, par, Ctrl_flags);
```
Solver `2` = `ode15s` (stiff ODE solver). After simulation, calculates penicillin yield statistics.

### 3. Simulation Engine (`indpensim.m`)

The core time-stepping loop running `k = 1:N` where `N = T/h` (typically ~1150 steps).

Each time step:

1. **Get control inputs**: Calls `fctrl_indpensim(X, Xd, k, h, T, Ctrl_flags)` which returns the manipulated variable struct `u`.

2. **Assemble state vector**: Builds `x00` (33-element vector) from either initial conditions (k=1) or previous step's results.

3. **Apply disturbances**: Reads current disturbance values from `Xd` for this time step.

4. **Growth rate adaptation**: If inhibition is enabled and `k > 65`, checks if biomass growth rate has been declining for 63+ consecutive steps. If so, permanently reduces `mu_x_max` to the current value (irreversible damage from prolonged suboptimal conditions).

5. **ODE integration**: Calls `ode15s` over the interval `[t(k), t(k+1)]` with internal step size `h_ode = h/20`:
   ```matlab
   [t_sol, y_sol] = ode15s('indpensim_ode', t(k):h_ode:t(k+1), x00, [], u00, p);
   ```

6. **Numerical stability**: Clamps all state variables to a minimum of 0.001.

7. **Store results**: Saves all 33 ODE states and 12 manipulated variables into the batch struct `X`.

8. **Derived calculations**: Computes OUR (Oxygen Uptake Rate) and CER (Carbon Evolution Rate) from off-gas data.

9. **Optional Raman**: If enabled, generates simulated Raman spectra via `Raman_Sim()`.

10. **Offline measurements**: Every `Off_line_m` hours (12h), records offline measurements of NH3, viscosity, PAA, penicillin, and biomass with a 4-hour delay. All other time steps get NaN for offline channels.

Post-loop: converts internal H+ concentration back to pH scale, converts heat units to kcal.

### 4. ODE System (`indpensim_ode.m`)

Contains the 33 coupled ordinary differential equations representing the bioreactor physics. The system receives the 105-parameter vector and 26-element input vector.

#### State Variables (Y(1) through Y(33)):

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

#### Key Biological Equations:

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

### 5. Control System (`fctrl_indpensim.m`)

Called every time step to compute manipulated variables.

#### Closed-Loop PID Controllers:
- **pH control**: PID controller (`PIDSimple3`) with dead-band of +/- 0.05 around set-point (6.5). If pH drops, adds base (max 225 L/h). If pH rises, adds acid.
- **Temperature control**: PID controller with 0.05 K dead-band around set-point (298 K). Below set-point: activates heating water. Above: activates cooling water.

#### Sequential Batch Control (SBC) Recipes:
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

#### Fault Injection:
If enabled, overrides specific manipulated variables during defined time windows (e.g., aeration drops to 20 at k=100-120, pressure jumps to 2 bar at k=500-520, etc.). Sensor faults (temperature, pH) add ramp errors to measurements.

### 6. Post-Processing (`Generate_Batch_records.m`)

After all batches complete:

1. **Strip internal states**: Removes non-measurable variables (biomass regions a0-a4, vacuole densities, culture age, internal growth rates, etc.) from the output.
2. **Clean offline data**: Removes NaN entries from offline measurements (PAA, penicillin, biomass, NH3, viscosity).
3. **Unit conversions**: Converts O2 off-gas to percentage.
4. **Export formats**:
   - `.mat` file with all batch records
   - `.csv` file with all time-series data concatenated across batches
   - `_Statistics.csv` with per-batch summary (penicillin harvested during batch, at end, total yield, fault flag)

---

## Output Data

Each simulated batch produces time-series at 12-minute resolution for:

**Online measurements (continuous):** Substrate (S), dissolved O2, O2 off-gas, CO2 off-gas, dissolved CO2, penicillin (P), volume, weight, pH, temperature, heat generated, viscosity, OUR, CER, PAA, NH3.

**Manipulated variables:** Aeration rate (Fg), agitator RPM, substrate feed (Fs), oil feed (Foil), PAA feed (Fpaa), acid flow (Fa), base flow (Fb), cooling water (Fc), heating water (Fh), water injection (Fw), vessel pressure, discharge flow.

**Offline measurements (every 12h with 4h delay):** PAA, penicillin, biomass, NH3, viscosity.

**Batch statistics:** Total penicillin yield (kg), penicillin harvested during batch (via discharge), penicillin at final harvest, batch length.

---

## Running the Simulator

1. Open MATLAB
2. Navigate to the repository directory
3. Run `Generate_Production_Batch_data_V4.m`


To modify the number of batches, fault profiles, control strategies, or Raman settings, edit the `Batch_run_flags` struct in `Generate_Production_Batch_data_V4.m`.
