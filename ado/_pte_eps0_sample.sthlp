{smcl}
{* *! version 1.0.0  23mar2026}{...}
{vieweralsosee "[PTE] _pte_omega" "help _pte_omega"}{...}
{vieweralsosee "[PTE] _pte_winsorize" "help _pte_winsorize"}{...}
{vieweralsosee "[PTE] _pte_evolution" "help _pte_evolution"}{...}
{viewerjumpto "Syntax" "_pte_eps0_sample##syntax"}{...}
{viewerjumpto "Description" "_pte_eps0_sample##description"}{...}
{viewerjumpto "Options" "_pte_eps0_sample##options"}{...}
{viewerjumpto "Stored results" "_pte_eps0_sample##results"}{...}
{viewerjumpto "Generated variables" "_pte_eps0_sample##generated"}{...}
{viewerjumpto "Examples" "_pte_eps0_sample##examples"}{...}
{viewerjumpto "References" "_pte_eps0_sample##references"}{...}

{title:Title}

{p2colset 5 26 28 2}{...}
{p2col:{cmd:_pte_eps0_sample} {hline 2}}Build the untreated innovation support for EPIC-002{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_eps0_sample}
{cmd:,} {opt treatment(name)}
[{it:options}]

{synoptset 22 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt treatment(name)}}binary treatment-state variable; must match an existing numeric variable exactly and equal the current EPIC-002 treatment state{p_end}

{syntab:Optional}
{synopt:{opt eps0window(#)}}nonnegative common pre-treatment window; {cmd:0} keeps the full identified untreated support{p_end}
{synopt:{opt touse(name)}}exact numeric active-sample indicator; current and lag rows must both satisfy {cmd:touse!=0}{p_end}
{synopt:{opt nodiag:nose}}suppress diagnostic output{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_eps0_sample} is EPIC-002 step US-E2-003. It reconstructs the
identified support of untreated productivity innovations {it:eps0} after the
live evolution law has been estimated. The command requires a current EPIC-002
evolution state from {cmd:_pte_evolution}, the treatdependent bridge
{cmd:_pte_treatdep_evolution}, the public wrapper {cmd:pte},
{cmd:_pte_omega}, {cmd:_pte_eps0_sample}, or {cmd:_pte_winsorize}; it
refuses to run on an unrelated {cmd:e()} context.

{pstd}
When the live EPIC-002 state stores the estimation-time panel declaration in
{cmd:e(idvar)} / {cmd:e(timevar)} (with fallback to {cmd:e(id)} /
{cmd:e(time)}), {cmd:_pte_eps0_sample} temporarily restores that stored
declaration before rebuilding lagged omega, first-treatment timing, and the
windowed untreated-support indicator. This keeps eps0 reconstruction invariant
to caller-side {cmd:xtset} drift after {cmd:_pte_evolution}, {cmd:_pte_omega},
or {cmd:pte}. After reconstruction, the caller's original {cmd:xtset} is
restored.

{pstd}
For admissible evolution rows, the command:

{phang2}1. Computes each firm's observed treatment-entry year {cmd:_pte_treat_year} from the full observed treatment path; left-censored treated firms keep this metadata missing because no observed {cmd:0->1} entry is available in sample.{p_end}
{phang2}2. Marks the untreated innovation support {cmd:_pte_eps0_ind==1}.{p_end}
{phang2}3. Rebuilds the untreated fitted law {cmd:_pte_omega_hat = h_bar_0(L.omega)} from the live {cmd:e(rho_0)} coefficients.{p_end}
{phang2}4. Stores the untreated innovation residuals {cmd:_pte_eps0 = omega - _pte_omega_hat}.{p_end}

{pstd}
Under the default path, treated firms contribute only untreated observations
strictly before their own observed entry year, while never-treated firms
contribute all admissible untreated observations. This implements the
identified untreated innovation distribution used by Proposition 4.3.
Left-censored treated firms do {bf:not} enter the never-treated branch merely
because their observed entry year is missing; if such firms later appear
untreated in the sample, those rows are still excluded from the eps0 control
support.

{pstd}
When {opt eps0window(#)} is positive, the command imposes a common window on
all untreated observations in the active estimation sample. The anchor is the
observed entry year of the earliest treated cohort that remains active in the
current estimation sample and still retains admissible untreated evolution support.
Never-treated firms are restricted to that same window. Cohorts whose
live rows are only post-treatment do not qualify to anchor the window because
they contribute no identified untreated innovations under the live
{cmd:_pte_evo_sample} and {cmd:D==0} gates used to construct
{cmd:_pte_eps0_ind}.

{pstd}
The active eps0 sample is always a subset of the live evolution sample. In
particular, a row is admissible only if the current observation and the lag
source observation both remain inside the live EPIC-002 active sample. When
{opt touse()} is omitted on a rerun, {cmd:_pte_eps0_sample} inherits that
active-sample boundary from the current EPIC-002 bridge state rather than
falling back to the full dataset. It first reuses the persisted indicator
{cmd:_pte_active_sample}. If that bridge variable is unavailable, the command
aborts and asks the caller to supply {opt touse()} or rebuild
{cmd:_pte_active_sample}; it does {bf:not} fall back to the current
{cmd:e(sample)}, because live {cmd:e(sample)} objects from
{cmd:_pte_winsorize}, {cmd:_pte_eps0_sample}, {cmd:_pte_evolution}, or
{cmd:_pte_omega} are not guaranteed to equal the broader EPIC-002 active
sample.

{pstd}
The transition gate is read using the exact package variable name
{cmd:_pte_mid}. If that exact variable is absent, {cmd:_pte_eps0_sample}
falls back only to the exact legacy name {cmd:mid}. Abbreviated shadow names
such as {cmd:_pte_mid_*} are rejected because they would silently redefine the
non-transition evolution sample used to recover untreated innovations.


{marker options}{...}
{title:Options}

{phang}
{opt treatment(name)} specifies the binary treatment-state variable. The name
must match an existing numeric variable exactly; abbreviation fallback is
rejected. The supplied name must also match the live EPIC-002 treatment state
stored in {cmd:e(treatment)}; {cmd:_pte_eps0_sample} does not allow a different
treatment variable to be mixed into the current evolution context.

{phang}
{opt eps0window(#)} sets the width of the common pre-treatment support window.
{cmd:eps0window(0)} keeps the full identified untreated support. Positive
values keep untreated observations with
{cmd:anchor_year - # * delta() <= year < anchor_year}, where {cmd:anchor_year} is the
observed entry year of the earliest treated cohort that remains active in the
current estimation sample and still retains admissible untreated evolution
support. A treated cohort with no live untreated support before entry cannot
anchor the window. If {cmd:eps0window(#)}
exceeds the available untreated time span implied by the current live
evolution sample, the same common anchor-year window contract still applies;
the command does {bf:not} revert to the default full untreated support. That
available span is computed after the active-sample and lag-source restrictions,
so {opt touse()} or a narrower live subsample can make the requested window
wider than the identified untreated span even when the raw dataset spans more
calendar time. The parameter is therefore measured in panel periods, scaled by
the current {cmd:xtset} {cmd:delta()} declaration; on annual {cmd:delta(1)}
data this coincides with years.

{phang}
{opt touse(name)} restricts the active sample. The supplied name must match an
existing numeric variable exactly. The current row and the lag row that supplies {cmd:L.omega} /
{cmd:L.treatment} must both satisfy {cmd:touse!=0}; otherwise the observation
is excluded from the eps0 support. A string {opt touse()} is rejected at the
entry gate with {cmd:r(111)}. If you omit {opt touse()}, the command instead
reuses the persisted EPIC-002 active sample from the current live bridge
state. It first prefers the bridge variable {cmd:_pte_active_sample}. If that
variable is unavailable, {cmd:_pte_eps0_sample} aborts and asks the caller to
supply {opt touse()} or rebuild {cmd:_pte_active_sample}; it does {bf:not}
fall back to the current {cmd:e(sample)} because that object may describe a
trimmed/raw eps0 support or another posted estimation sample rather than the
live EPIC-002 active sample.
This keeps re-runs of
{cmd:_pte_eps0_sample} after {cmd:_pte_evolution}, {cmd:_pte_omega}, or a
compatible bridge state aligned with the original identified evolution sample
boundary.

{phang}
{opt nodiagnose} suppresses the formatted diagnostics.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_eps0_sample} stores the following in {cmd:e()}:

{pstd}
In the treated-side stored results below, "treated-lag support" means that
effective treated-lag support exists because the treated evolution law is
identified in the live OLS fit; it does {bf:not} mean merely that some treated
lag rows are present before omitted-regressor checks.

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:e(N_eps0)}}number of untreated innovation observations{p_end}
{synopt:{cmd:e(N_eps0_treated)}}untreated innovation observations from eventually treated firms{p_end}
{synopt:{cmd:e(N_eps0_control)}}untreated innovation observations from never-treated firms{p_end}
{synopt:{cmd:e(eps0_mean)}}mean of {cmd:_pte_eps0}{p_end}
{synopt:{cmd:e(eps0_sd)}}standard deviation of {cmd:_pte_eps0}{p_end}
{synopt:{cmd:e(eps0_min)}}minimum of {cmd:_pte_eps0}{p_end}
{synopt:{cmd:e(eps0_max)}}maximum of {cmd:_pte_eps0}{p_end}
{synopt:{cmd:e(eps0window)}}window width used to construct the support{p_end}
{synopt:{cmd:e(sigma_eps)}}raw standard deviation of the current untreated innovation support{p_end}
{synopt:{cmd:e(sigma_eps_trim)}}1%-99% trimmed standard deviation of the current untreated innovation support; if the live EPIC-002 bridge already has {cmd:e(trimeps)=0}, this aliases {cmd:e(sigma_eps)} on the rebuilt support{p_end}
{synopt:{cmd:e(N_eps0_trim)}}observations retained by the active trim law on the current support; equals {cmd:e(N_eps0)} when the live bridge has {cmd:e(trimeps)=0}{p_end}
{synopt:{cmd:e(eps0_p1)}}1st percentile cutoff of the current untreated innovation support when trimming is active; missing when the live bridge has {cmd:e(trimeps)=0}{p_end}
{synopt:{cmd:e(eps0_p99)}}99th percentile cutoff of the current untreated innovation support when trimming is active; missing when the live bridge has {cmd:e(trimeps)=0}{p_end}
{synopt:{cmd:e(trimeps)}}trim indicator forwarded from the live EPIC-002 bridge when available; otherwise defaults to the canonical trimmed-Gaussian path ({cmd:1}){p_end}
{synopt:{cmd:e(omegapoly)}}evolution-polynomial order forwarded from the live EPIC-002 state{p_end}
{synopt:{cmd:e(xtdelta)}}stored panel spacing forwarded from the live EPIC-002 state when available{p_end}
{synopt:{cmd:e(rho0)}}untreated evolution intercept{p_end}
{synopt:{cmd:e(rho1)}}untreated linear coefficient{p_end}
{synopt:{cmd:e(rho2)}}untreated quadratic coefficient if {cmd:omegapoly>=2}{p_end}
{synopt:{cmd:e(rho3)}}untreated cubic coefficient if {cmd:omegapoly>=3}{p_end}
{synopt:{cmd:e(rho4)}}untreated quartic coefficient if {cmd:omegapoly>=4}{p_end}
{synopt:{cmd:e(gamma1)}}treated-minus-untreated linear interaction; posted only when treated-lag support exists{p_end}
{synopt:{cmd:e(gamma2)}}treated-minus-untreated quadratic interaction if {cmd:omegapoly>=2}; posted only when treated-lag support exists{p_end}
{synopt:{cmd:e(gamma3)}}treated-minus-untreated cubic interaction if {cmd:omegapoly>=3}; posted only when treated-lag support exists{p_end}
{synopt:{cmd:e(gamma4)}}treated-minus-untreated quartic interaction if {cmd:omegapoly>=4}; posted only when treated-lag support exists{p_end}
{synopt:{cmd:e(delta)}}treated intercept shift from the live evolution state; posted only when treated-lag support exists{p_end}
{synopt:{cmd:e(N_evo)}}admissible evolution-regression observations{p_end}
{synopt:{cmd:e(N_lag_untreated)}}rows with untreated lag support, when available upstream{p_end}
{synopt:{cmd:e(N_lag_treated)}}rows with treated lag support, when available upstream{p_end}
{synopt:{cmd:e(lag_treated_supported)}}1 if the treated evolution law is identified in the live OLS fit; 0 otherwise, when available upstream{p_end}
{synopt:{cmd:e(r2)}}compatibility alias for the forwarded evolution R-squared{p_end}
{synopt:{cmd:e(rmse)}}compatibility alias for the forwarded evolution RMSE{p_end}
{synopt:{cmd:e(r2_evo)}}standardized EPIC-002 alias for the forwarded evolution R-squared{p_end}
{synopt:{cmd:e(rmse_evo)}}standardized EPIC-002 alias for the forwarded evolution RMSE{p_end}

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Matrices}{p_end}
{synopt:{cmd:e(rho_0)}}untreated evolution coefficient row vector{p_end}
{synopt:{cmd:e(rho_1)}}treated evolution coefficient row vector; posted only when treated-lag support exists{p_end}

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:e(treatment)}}treatment variable name{p_end}
{synopt:{cmd:e(pfunc)}}legacy production-function alias{p_end}
{synopt:{cmd:e(prodfunc)}}production-function branch metadata{p_end}
{synopt:{cmd:e(id)}}stored panel identifier alias forwarded from the live EPIC-002 state{p_end}
{synopt:{cmd:e(time)}}stored time variable alias forwarded from the live EPIC-002 state{p_end}
{synopt:{cmd:e(idvar)}}stored estimation panel identifier used when reconstructing eps0 support{p_end}
{synopt:{cmd:e(timevar)}}stored estimation time variable used when reconstructing eps0 support{p_end}
{synopt:{cmd:e(cmd)}}{cmd:"_pte_eps0_sample"}{p_end}
{synopt:{cmd:e(title)}}{cmd:"PTE eps0 Sample Selection"}{p_end}


{marker generated}{...}
{title:Generated variables}

{synoptset 20 tabbed}{...}
{synopt:{cmd:_pte_treat_year}}observed treatment-entry year; missing for never-treated and left-censored treated firms{p_end}
{synopt:{cmd:_pte_eps0_ind}}indicator for the identified untreated innovation support{p_end}
{synopt:{cmd:_pte_omega_hat}}untreated fitted evolution law on the selected support{p_end}
{synopt:{cmd:_pte_eps0}}untreated innovation residuals on the selected support{p_end}


{marker examples}{...}
{title:Examples}

{pstd}Default identified untreated support after running EPIC-002 evolution:{p_end}
{phang2}{cmd:. _pte_eps0_sample, treatment(D)}{p_end}

{pstd}Restrict to a three-year common pre-treatment window:{p_end}
{phang2}{cmd:. _pte_eps0_sample, treatment(D) eps0window(3)}{p_end}

{pstd}Respect an upstream active sample boundary:{p_end}
{phang2}{cmd:. _pte_eps0_sample, treatment(D) touse(_pte_esample)}{p_end}

{pstd}Bridge from the treatdependent evolution worker before rebuilding eps0:{p_end}
{phang2}{cmd:. _pte_treatdep_evolution, treatment(D) omegapoly(3)}{p_end}
{phang2}{cmd:. _pte_eps0_sample, treatment(D)}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z., and Schurter, K. (2026). Productivity Treatment Effects.
{it:Working paper}. Proposition 4.3 and Section 6.3.3.

{phang}
Official replication references:
{cmd:DOs/att_estimation_program.do} and
{cmd:DOs/att_estimation_program_translog.do}.
