{smcl}
{* *! version 1.0.1  31mar2026}{...}
{* *! Monte Carlo internals for pte}{...}
{* *! Chen, Liao & Schurter (2026)}{...}

{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] pte_diagnose" "help pte_diagnose"}{...}
{vieweralsosee "[PTE] pte_graph" "help pte_graph"}{...}
{viewerjumpto "Overview" "pte_simulate##overview"}{...}
{viewerjumpto "Availability" "pte_simulate##availability"}{...}
{viewerjumpto "Internal components" "pte_simulate##components"}{...}
{viewerjumpto "Remarks" "pte_simulate##remarks"}{...}
{viewerjumpto "References" "pte_simulate##references"}{...}
{help pte_simulate}
{hline}

{marker title}{...}
{title:Title}

{p2colset 5 34 36 2}{...}
{p2col:{hi:Monte Carlo simulation internals} {hline 2}}Internal simulation
components used by the PTE package{p_end}
{p2colreset}{...}


{marker overview}{...}
{title:Overview}

{pstd}
This help topic documents the Monte Carlo components currently shipped with
the package source tree. The live repository provides internal building blocks
for simulation and calibration, but it does {bf:not} currently ship an
executable public wrapper command for standalone Monte Carlo studies.

{pstd}
The simulation material in Chen, Liao & Schurter (2026) and the official
replication code is implemented through internal programs and .do workflows.
Users should therefore treat the objects documented below as developer-facing
infrastructure rather than as a supported front-end estimation command.


{marker availability}{...}
{title:Availability}

{pstd}
The current source tree includes the following Monte Carlo components:

{phang2}{cmd:_pte_dgp_calibrate} calibrates DGP parameter matrices from an
empirical sample.{p_end}

{phang2}{cmd:_pte_mc_dgp} generates a Monte Carlo panel by resampling and
replacing the productivity path using calibrated parameters.{p_end}

{phang2}{cmd:_pte_mc_engine} runs the outer simulation loop and reports Monte
Carlo summaries in {cmd:r()}.{p_end}

{phang2}{cmd:pte_simulate_paths()} is a developer-facing Mata utility for
untreated-path simulation. The public ATT estimator uses the Stata recursion
implemented in {cmd:_pte_att}.{p_end}

{pstd}
These components depend on the current dataset and on package-internal result
contracts. They are not a drop-in replacement for a documented public command
with a stable user-facing syntax.


{marker components}{...}
{title:Internal components}

{dlgtab:Calibration}

{phang}
{cmd:_pte_dgp_calibrate using filename, pfunc(string) order(#)}
loads an empirical sample, verifies the panel structure, and returns
calibrated {cmd:r(BETA)}, {cmd:r(RHO)}, and {cmd:r(OMEGA)} matrices for the
Monte Carlo backend.

{dlgtab:Data generation}

{phang}
{cmd:_pte_mc_dgp, betamat(...) rhomat(...) omegamat(...) ...}
implements the simulation DGP used by the internal Monte Carlo workflow. It
expects the source data layout required by the package's empirical replication
design. If the parameter matrices contain more than one row, callers must
provide {cmd:industry()} to select the exact row; otherwise the worker
fails closed instead of silently defaulting to the first row.

{dlgtab:Simulation engine}

{phang}
{cmd:_pte_mc_engine, nsim(#) betamat(...) rhomat(...) omegamat(...) ...}
orchestrates repeated DGP generation, estimation, and Monte Carlo summary
calculation. When called directly, it stores summary matrices such as
{cmd:r(ATT_true)}, {cmd:r(ATT_est)}, {cmd:r(BIAS)}, and {cmd:r(RMSE)}.
Because the engine has no industry-selection bridge of its own, it accepts
only single-row parameter matrices; callers must select one industry row
before invoking the loop.
Its bootstrap branch follows the same firm-level stratified cluster
resampling law used by the package bootstrap helpers and the official
replication {cmd:DOs/}: resample firms with treatment-status stratification
before re-estimating the full pipeline. When {cmd:nboot()>0}, {cmd:bootseed()}
is interpreted as the outer bootstrap seed base, so bootstrap draw {it:b}
uses seed {cmd:bootseed() + b - 1}.{p_end}

{dlgtab:Mata utility}

{phang}
{cmd:pte_simulate_paths()} is defined in
{browse "mata/pte_simulate.mata":mata/pte_simulate.mata}. It simulates
untreated productivity paths using the untreated evolution law h-bar-0 and a
current-period untreated innovation at each simulated event time, as in
Proposition 4.3. This standalone Mata utility draws from the same iid
untreated-innovation product law as the ATT estimator, but it is not a
row-for-row reproduction of {cmd:_pte_att}'s DO-compatible lagged-row shock
convention. The public ATT estimate is produced by {cmd:_pte_att}.


{marker remarks}{...}
{title:Remarks}

{pstd}
This topic intentionally documents the repository's {it:current} simulation
surface. It does not promise a standalone front-end simulation command beyond
the internal components listed above.

{pstd}
The official DO files remain the reference implementation for the Monte Carlo
study described in the paper. In particular, the package's internal Monte
Carlo helpers follow the same underlying design logic, but they are not yet
packaged as a stable public command with an independent syntax contract.


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z. & Schurter, K. (2026).
Productivity Treatment Effects.
{it:Working Paper}. See the simulation discussion in Section 6 and the
official replication workflows in {cmd:DOs/}. {p_end}
