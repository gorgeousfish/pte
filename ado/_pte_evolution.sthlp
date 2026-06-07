{smcl}
{* *! version 1.0.0  22mar2026}{...}
{vieweralsosee "[PTE] _pte_omega" "help _pte_omega"}{...}
{vieweralsosee "[PTE] _pte_winsorize" "help _pte_winsorize"}{...}
{viewerjumpto "Syntax" "_pte_evolution##syntax"}{...}
{viewerjumpto "Description" "_pte_evolution##description"}{...}
{viewerjumpto "Options" "_pte_evolution##options"}{...}
{viewerjumpto "Stored results" "_pte_evolution##results"}{...}
{viewerjumpto "Examples" "_pte_evolution##examples"}{...}
{viewerjumpto "References" "_pte_evolution##references"}{...}

{title:Title}

{p2colset 5 24 26 2}{...}
{p2col:{cmd:_pte_evolution} {hline 2}}Estimate the EPIC-002 productivity
evolution law{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_evolution}
{cmd:,} {opt treatment(name)}
[{it:options}]

{synoptset 22 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt treatment(name)}}binary treatment-state variable used as
{it:D_t}{p_end}

{syntab:Optional}
{synopt:{opt omegapoly(#)}}polynomial order of the evolution law; 1, 2, 3, or 4;
default {cmd:3}{p_end}
{synopt:{opt pfunc(string)}}production-function branch metadata to forward;
{cmd:cd} or {cmd:translog}{p_end}
{synopt:{opt touse(name)}}active-sample indicator; the name must match an
existing numeric variable exactly, and current and lag rows must both satisfy
{cmd:touse!=0}{p_end}
{synopt:{opt nodiag:nose}}suppress diagnostic output{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_evolution} is the EPIC-002 step that estimates the
realized-productivity
evolution regression used by the PTE package after {cmd:omega} has been
recovered.
Under the cubic polynomial specification used in Section 6.3.2 of
Chen, Liao & Schurter (2026), it operationalizes Equation (16) on
non-transition observations to recover the untreated and treated
evolution laws. Guided by Theorem 3.1, transition periods are excluded
from this regression:

{p 8 8 2}
omega_t = rho_0 + rho_1*omega_{t-1} + rho_2*omega_{t-1}^2 + rho_3*omega_{t-1}^3
        + gamma_1*omega_{t-1}*D_{t-1} + gamma_2*omega_{t-1}^2*D_{t-1} + ...
        + delta*D_{t-1} + epsilon_t

{pstd}
Only non-transition observations are admissible in the current period. The
lagged
state must also come from the active sample. In package terms,
{cmd:_pte_evolution}
keeps rows with the exact package transition indicator {cmd:_pte_mid==0} (or
the exact legacy fallback {cmd:mid==0}) and, when {opt touse()} is supplied,
additionally requires {cmd:L.touse==1}. This prevents the evolution stage from
borrowing lagged {cmd:omega} or lagged treatment states from sample-out
observations.

{pstd}
When {cmd:_pte_evolution} is called directly after {cmd:_pte_prodfunc} and the
persisted EPIC-002 bridge sample {cmd:_pte_active_sample} is not yet available,
the helper rebuilds its active sample from the recoverable {cmd:phi} support
rather than the narrower EPIC-001 GMM {cmd:e(sample)}. That direct bridge is
only valid when the current data still contain the live EPIC-001 readiness
marker {cmd:_pte_prodfunc_ready}; stale {cmd:phi}/{cmd:omega}/{cmd:e(b)} state
from a failed rerun is rejected.

{pstd}
The untreated evolution function is stored as {cmd:e(rho_0)} and the treated
evolution function as {cmd:e(rho_1)}. The command also publishes lag-support
diagnostics:

{phang2}{cmd:e(N_lag_untreated)} counts admissible rows with
{cmd:D_{t-1}=0}.{p_end}
{phang2}{cmd:e(N_lag_treated)} counts admissible rows with
{cmd:D_{t-1}=1}.{p_end}
{phang2}{cmd:e(lag_treated_supported)} is 1 only when the treated evolution law
is identified in the live OLS fit. It is 0 both when there is no admissible
treated lag support at all and when treated-side regressors are omitted by the
live OLS fit.{p_end}

{pstd}
If there is no untreated lag support, the command aborts because {it:\bar h_0}
is not identified. If there is no treated lag support, the command still runs
the pooled non-transition OLS fit so the untreated law {it:\bar h_0} can be
used for eps0 recovery and Proposition 4.3 counterfactual simulation, but it
does {bf:not} claim that {it:\bar h_1} is identified under Theorem 3.1. The
same h_bar_0-only fallback also applies when treated-lag support exists in
principle but the live OLS fit omits one or more treated-side regressors
because the treated law is not effectively identified under the requested
{cmd:omegapoly()}. On that fallback path the worker warns that treated-lag
terms are not identified and does {bf:not} publish {cmd:e(rho_1)},
{cmd:e(gamma#)}, or {cmd:e(delta)}.

{pstd}
If the live OLS fit omits any requested untreated polynomial term, the command
aborts because the requested h_bar_0 law is not identified. This untreated-side
omission gate is separate from the treated-side fallback. The treated-side
fallback can still preserve {it:\bar h_0} for eps0 recovery and Proposition 4.3
counterfactual simulation, but an omitted untreated basis term means the
requested untreated evolution law itself was not identified on the live sample,
so the command does not silently downgrade {opt omegapoly()} or publish a
misleading {cmd:e(rho_0)} for downstream eps0 recovery or ATT simulation.


{marker options}{...}
{title:Options}

{phang}
{opt treatment(name)} specifies the binary treatment indicator. The name must
match an existing variable exactly and the variable must be coded 0/1 on the
active sample.

{phang}
{opt omegapoly(#)} sets the polynomial order of the evolution law. Valid values
are {cmd:1}, {cmd:2}, {cmd:3}, and {cmd:4}. The order applies to the evolution
equation, not to the production-function branch.

{phang}
{opt pfunc(string)} forwards the current production-function branch metadata for
downstream consumers. Valid values are {cmd:cd} and {cmd:translog}. If omitted,
the command first reuses {cmd:e(prodfunc)} and then the legacy alias
{cmd:e(pfunc)}
before defaulting to {cmd:cd}.

{phang}
{opt touse(name)} restricts the evolution regression to the current active
sample. The supplied name must match an existing numeric variable exactly;
abbreviation fallback such as {cmd:touse(keep)} when the data only contain
{cmd:keep_shadow} is rejected, and string sample indicators are rejected at
the entry gate. A row is admissible only when both the current observation and
the lag source observation satisfy {cmd:touse!=0} and are nonmissing.

{pstd}
If {opt touse()} is omitted and the current live {cmd:e(cmd)} is an EPIC-001 or
EPIC-002 bridge ({cmd:_pte_prodfunc}, {cmd:_pte_omega_recovery},
{cmd:_pte_evolution},
{cmd:_pte_treatdep_evolution}, {cmd:_pte_omega}, {cmd:_pte_eps0_sample},
{cmd:_pte_winsorize}, or {cmd:pte}), {cmd:_pte_evolution} reuses the current
active-sample boundary instead of silently expanding back to the full dataset.
It first prefers the persisted indicator {cmd:_pte_active_sample}; if that
bridge variable is unavailable it usually falls back to the current
{cmd:e(sample)}. The three exceptions are a direct live {cmd:_pte_prodfunc}
bridge, a live {cmd:_pte_winsorize} state, and a live {cmd:_pte_eps0_sample}
state. On the direct
{cmd:_pte_prodfunc} bridge, {cmd:e(sample)} is only the narrow stable GMM
criterion sample, while EPIC-002 must start from the broader recoverable
{cmd:phi} support; therefore {cmd:_pte_evolution} uses {cmd:!missing(phi)}
instead of inheriting the narrow GMM sample. On a live {cmd:_pte_winsorize}
or {cmd:_pte_eps0_sample} state, {cmd:e(sample)} marks the eps0 shock support
rather than the broader EPIC-002 active sample, so {cmd:_pte_evolution}
refuses that fallback and asks the caller to supply {opt touse()} or rebuild
{cmd:_pte_active_sample}.
Outside those live bridge contexts, omitting {opt touse()} means "use the full
dataset."

{phang}
{opt nodiagnose} suppresses the formatted regression summary.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_evolution} stores the following in {cmd:e()}:

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:e(rho0)}}constant term of the untreated evolution law{p_end}
{synopt:{cmd:e(rho1)}}linear untreated coefficient{p_end}
{synopt:{cmd:e(rho2)}}quadratic untreated coefficient if
{cmd:omegapoly>=2}{p_end}
{synopt:{cmd:e(rho3)}}cubic untreated coefficient if {cmd:omegapoly>=3}{p_end}
{synopt:{cmd:e(rho4)}}quartic untreated coefficient if {cmd:omegapoly>=4}{p_end}
{synopt:{cmd:e(gamma1)}}linear treated-minus-untreated interaction coefficient;
posted only when effective treated-lag support exists{p_end}
{synopt:{cmd:e(gamma2)}}quadratic treated-minus-untreated interaction
coefficient if {cmd:omegapoly>=2}; posted only when effective treated-lag
support exists{p_end}
{synopt:{cmd:e(gamma3)}}cubic treated-minus-untreated interaction coefficient if
{cmd:omegapoly>=3}; posted only when effective treated-lag support exists{p_end}
{synopt:{cmd:e(gamma4)}}quartic treated-minus-untreated interaction coefficient
if {cmd:omegapoly>=4}; posted only when effective treated-lag support
exists{p_end}
{synopt:{cmd:e(delta)}}direct treated intercept shift; posted only when
effective treated-lag support exists{p_end}
{synopt:{cmd:e(omegapoly)}}polynomial order used in the regression{p_end}
{synopt:{cmd:e(N)}}admissible evolution-regression observations (=
{cmd:e(N_evo)}){p_end}
{synopt:{cmd:e(N_evo)}}admissible evolution-regression observations{p_end}
{synopt:{cmd:e(N_lag_untreated)}}non-transition rows with untreated lag
support{p_end}
{synopt:{cmd:e(N_lag_treated)}}non-transition rows with treated lag support
before any OLS omission check{p_end}
{synopt:{cmd:e(lag_treated_supported)}}1 if the treated evolution law is
identified in the live OLS fit; 0 on the h_bar_0-only fallback path, whether
because treated lag support is absent or because treated-side regressors are
omitted{p_end}
{synopt:{cmd:e(r2)}}R-squared from the evolution regression{p_end}
{synopt:{cmd:e(rmse)}}RMSE from the evolution regression{p_end}
{synopt:{cmd:e(xtdelta)}}stored panel spacing from the live estimation axis when
available{p_end}

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Matrices}{p_end}
{synopt:{cmd:e(b)}}regression coefficient row vector from the live OLS fit;
coefficient labels use the DO-compatible base names {cmd:L.omega},
{cmd:L.omega2}, {cmd:L.omega3}, {cmd:L.omega_tp}, ..., rather than the internal
working-variable names. {cmd:predict, xb} is supported through a custom
prediction routine that rebuilds the fitted law directly from the live posted
coefficient vector, so the command does not need to publish user-visible helper
variables such as {cmd:omega_tp}. When Stata omits a treated-side regressor, the
omitted-term prefix is preserved in the live labels, so entries may appear as
{cmd:oL.omega_tp}, {cmd:oL.omega2_tp}, or {cmd:oL.<treatment>} using the exact
variable name supplied in {opt treatment()}; the custom predictor skips those
omitted entries but still uses any surviving treated-side coefficients so the
posted consumer path remains equal to the live OLS fit that created
{cmd:_pte_omega_hat}.{p_end}
{synopt:{cmd:e(V)}}regression covariance matrix from the live OLS fit with the
same live dimnames as {cmd:e(b)}, including any omitted-term {cmd:o.} prefixes
that Stata preserves{p_end}
{synopt:{cmd:e(rho_0)}}row vector of untreated evolution coefficients
[{cmd:rho0 rho1 ...}]{p_end}
{synopt:{cmd:e(rho_1)}}row vector of treated evolution coefficients
[{cmd:rho0+delta rho1+gamma1 ...}]; posted only when effective treated-lag
support exists{p_end}

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:e(treatment)}}treatment variable name{p_end}
{synopt:{cmd:e(treatsig)}}current treatment-law signature for downstream ATT /
graph certification on the live panel axis{p_end}
{synopt:{cmd:e(pfunc)}}legacy production-function alias{p_end}
{synopt:{cmd:e(prodfunc)}}production-function branch metadata{p_end}
{synopt:{cmd:e(id)}}stored panel identifier alias for downstream bridge
workers{p_end}
{synopt:{cmd:e(time)}}stored time variable alias for downstream bridge
workers{p_end}
{synopt:{cmd:e(idvar)}}stored estimation panel identifier for downstream bridge
workers{p_end}
{synopt:{cmd:e(timevar)}}stored estimation time variable for downstream bridge
workers{p_end}
{synopt:{cmd:e(cmd)}}{cmd:"_pte_evolution"}{p_end}


{title:Generated variables}

{synoptset 18 tabbed}{...}
{synopt:{cmd:_pte_active_sample}}byte; persisted EPIC-002 active-sample /
bridge-state indicator written after a successful live evolution fit. Downstream
reruns such as {cmd:_pte_eps0_sample}, {cmd:_pte_winsorize}, and bridge re-entry
into {cmd:_pte_evolution} reuse this variable when {opt touse()} is omitted, so
failed reruns do not silently overwrite the last successful active-sample
boundary.{p_end}
{synopt:{cmd:_pte_omega_hat}}double; fitted values from the evolution regression
on {cmd:e(sample)}. The command clears any stale copy at entry and recreates
this variable only after a successful live regression, so failed reruns do not
leave an obsolete hat behind for downstream eps0 recovery.{p_end}


{marker examples}{...}
{title:Examples}

{pstd}Basic usage after {cmd:omega} and transition indicators exist:{p_end}
{phang2}{cmd:. _pte_evolution, treatment(D)}{p_end}

{pstd}Use a second-order evolution law:{p_end}
{phang2}{cmd:. _pte_evolution, treatment(D) omegapoly(2)}{p_end}

{pstd}Restrict to an upstream estimation sample:{p_end}
{phang2}{cmd:. _pte_evolution, treatment(D) touse(_pte_esample)}{p_end}

{pstd}Inspect stored results:{p_end}
{phang2}{cmd:. ereturn list}{p_end}
{phang2}{cmd:. matrix list e(rho_0)}{p_end}
{phang2}{cmd:. matrix list e(rho_1)}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z., and Schurter, K. (2026). Productivity Treatment Effects.
{it:Working paper}. Theorem 3.1 and Proposition 4.3.

{phang}
Official replication references: {cmd:DOs/att_estimation_program.do} and
{cmd:DOs/att_estimation_program_translog.do}.
