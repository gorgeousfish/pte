{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] _pte_prodfunc" "help _pte_prodfunc"}{...}
{vieweralsosee "[PTE] _pte_att" "help _pte_att"}{...}
{viewerjumpto "Syntax" "_pte_omega##syntax"}{...}
{viewerjumpto "Description" "_pte_omega##description"}{...}
{viewerjumpto "Options" "_pte_omega##options"}{...}
{viewerjumpto "Stored results" "_pte_omega##results"}{...}
{viewerjumpto "Examples" "_pte_omega##examples"}{...}
{viewerjumpto "References" "_pte_omega##references"}{...}
{title:Title}

{p2colset 5 20 22 2}{...}
{p2col:{cmd:_pte_omega} {hline 2}}EPIC-002: Productivity Recovery and
Evolution{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_omega}
{cmd:,} {opt treatment(name)}
[{it:options}]

{synoptset 25 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt treatment(name)}}treatment indicator variable; must be the exact
live treatment-state variable name (no abbreviation fallback){p_end}

{syntab:Evolution}
{synopt:{opt omegapoly(#)}}polynomial order for evolution (1-4, default
3){p_end}
{synopt:{opt eps0window(#)}}if positive, restrict eps0 to the # panel periods
before the observed treatment-entry year among treated cohorts that remain
active in the current estimation sample and still retain admissible untreated
evolution support, scaled by the current {cmd:xtset} {cmd:delta()};
left-censored treated firms have no identifiable observed entry year and cannot
anchor the window; default uses the full identified untreated support
({cmd:0}){p_end}
{synopt:{opt notrimeps}}disable Winsorize trimming of eps0{p_end}

{syntab:Production Function}
{synopt:{opt beta_l(#)}}labor coefficient from EPIC-001{p_end}
{synopt:{opt beta_k(#)}}capital coefficient from EPIC-001{p_end}
{synopt:{opt beta_ll(#)}}labor squared coefficient (Translog){p_end}
{synopt:{opt beta_kk(#)}}capital squared coefficient (Translog){p_end}
{synopt:{opt beta_lk(#)}}labor-capital interaction coefficient (Translog){p_end}
{synopt:{opt prodfunc(string)}}production function type ("cd" or "translog"); if
omitted, standalone recovery infers {cmd:translog} from higher-order
coefficients, otherwise the live EPIC-001 metadata {cmd:e(prodfunc)} with legacy
fallback {cmd:e(pfunc)} are used before defaulting to {cmd:cd}{p_end}
{synopt:{opt touse(name)}}active-sample indicator; the name must match an
existing numeric variable exactly, recovery uses current rows with
{cmd:touse!=0}, and lagged evolution regressors must also come from rows with
{cmd:touse!=0}{p_end}

{syntab:Display}
{synopt:{opt nodiag:nose}}suppress diagnostic output{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_omega} is the orchestrator module for EPIC-002 (Productivity Recovery
and
Evolution) in the {cmd:pte} package. It coordinates the complete workflow:

{phang2}{bf:Step 1 (US-E2-001):} Productivity recovery: omega = phi -
f(k,l;beta){p_end}
{phang2}{bf:Step 2 (US-E2-002):} Evolution regression with polynomial and
interactions{p_end}
{phang2}{bf:Step 3 (US-E2-003):} eps0 sample selection (control group
pre-treatment){p_end}
{phang2}{bf:Step 4 (US-E2-004):} Winsorize and normal approximation for
eps0{p_end}

{pstd}
This module implements the theoretical framework from Chen, Liao & Schurter
(2026)
Equation (16) for the polynomial evolution process:

{p 8 8 2}
omega_t = rho_0 + rho_1*omega_{t-1} + rho_2*omega_{t-1}^2 + rho_3*omega_{t-1}^3
        + gamma_1*omega_{t-1}*D_{t-1} + gamma_2*omega_{t-1}^2*D_{t-1} + ...
        + delta*D_{t-1} + epsilon_t

{pstd}
The evolution parameters are stored in two matrices:

{phang2}{cmd:e(rho_0)}: Control group evolution function h_bar_0 = [rho_0,
rho_1, ..., rho_p]{p_end}
{phang2}{cmd:e(rho_1)}: Treated group evolution function h_bar_1 = [rho_0+delta,
rho_1+gamma_1, ...]{p_end}

{pstd}
The evolution stage requires non-transition untreated lag support to identify
{cmd:h_bar_0}. If no such rows exist, {cmd:_pte_omega} aborts. By contrast,
when there is no non-transition lag-treated support, or when the live pooled
OLS fit omits any treated-side regressor because the treated law is not
effectively identified under the requested {cmd:omegapoly()}, the evolution
step continues with the pooled regression. In that case
{cmd:h_bar_0 remains estimable}
for eps0 recovery and ATT simulation, but the EPIC-002 state does {bf:not}
forward an identified treated evolution law: {cmd:e(rho_1)},
{cmd:e(gamma#)}, and {cmd:e(delta)} are omitted on that path.

{pstd}
After {cmd:_pte_omega} finishes, the posted EPIC-002 state keeps the live
evolution metadata required by downstream modular steps. This means you may
rerun {cmd:_pte_eps0_sample} or {cmd:_pte_winsorize} on the same dataset to
inspect alternative {cmd:eps0window()} or trimming choices without rerunning
the full EPIC-002 pipeline first.

{pstd}
The macro {cmd:e(eps0_dist)} labels the EPIC-002 normal approximation that is
estimated from the untreated innovation support; it is {bf:not} a complete
description of every downstream ATT shock law. In {cmd:_pte_att}, the
canonical trim track uses that Gaussian approximation, while the raw track
defaults to the empirical {cmd:eps0} pool via {cmd:bsample}. Official
translog replication branches preserve documented Gaussian exceptions, so the
full downstream shock-law contract should be read from {cmd:_pte_att} rather
than from {cmd:e(eps0_dist)} alone.

{pstd}
{bf:Prerequisites:} This module requires EPIC-001 to have been executed,
providing:

{phang2}- Variable {cmd:phi} (control-adjusted first-stage productivity proxy;
first-stage controls already removed){p_end}
{phang2}- Variable {cmd:_pte_mid} (package transition-period indicator;
{cmd:mid} is accepted only as a legacy fallback compatibility alias){p_end}
{phang2}- Production function coefficients (beta_l, beta_k, etc.){p_end}


{marker options}{...}
{title:Options}

{dlgtab:Required}

{phang}
{opt treatment(name)} specifies the treatment indicator variable. This variable
should equal 1 for treated observations and 0 for control observations. The
name must match an existing variable exactly. For example, if the dataset only
contains {cmd:D_shadow}, then {cmd:treatment(D)} is rejected instead of being
silently expanded to {cmd:D_shadow}.

{dlgtab:Evolution}

{phang}
{opt omegapoly(#)} specifies the polynomial order for the evolution process.
Valid values are 1, 2, 3, or 4. Default is 3, which matches the paper's baseline
specification.

{phang}
{opt eps0window(#)} restricts the eps0 pool to untreated observations observed
within {it:#} panel periods before the observed treatment-entry year among
treated cohorts
that still retain admissible untreated evolution support in the active sample.
The raw span on the underlying time variable is therefore
{it:#} × {cmd:delta()} from the current {cmd:xtset} declaration.
An anchoring cohort must keep at least one non-transition untreated row that
remains eligible for eps0 recovery before its observed entry year.
Left-censored treated firms have no identifiable
observed entry year in the sample and therefore cannot anchor the window.
The default is {cmd:eps0window(0)}, which keeps the full identified untreated
pre-treatment support among admissible cohorts, matching the general Proposition
4.3 identification
logic. When {opt touse()} is supplied, cohorts outside the active
estimation sample do not anchor the window. In particular, a cohort whose
treated observations are entirely outside {opt touse()} cannot anchor the
window merely because its pre-treatment rows remain active; for cohorts that
remain eligible, the anchor itself is still the cohort's observed
treatment-entry year from the full observed panel path. If {opt eps0window(#)}
exceeds the
available untreated time span implied by the current live evolution sample,
the same common anchor-year window contract still applies; the command does
{bf:not} revert to the default full pre-treatment support. That available span
is computed after the active-sample and lag-source restrictions, so
{opt touse()}
or a narrower live subsample can make the requested window wider than the
identified untreated span even when the raw dataset spans more calendar time.
Paper-specific replication diagnostics instead use a narrower window; in a
by-industry workflow, {cmd:eps0window(3)} matches the paper's Appendix E.3-style
three-period comparison design, which on the paper's annual data is also a
three-year comparison design, rather than the DO files' exact calendar-year
filter.

{phang}
{opt notrimeps} disables Winsorize trimming of the eps0 distribution. When
specified,
the downstream canonical Gaussian ATT track uses the untrimmed/raw standard
deviation, while the raw ATT track still defaults to the empirical {cmd:eps0}
pool (except for the documented official translog Gaussian exceptions). This is
{bf:not recommended}
per Section 6.3.3 of the paper.

{dlgtab:Production Function}

{phang}
{opt beta_l(#)}, {opt beta_k(#)}, etc. specify the production function
coefficients
from EPIC-001. These are used to recover productivity: omega = phi -
f(k,l;beta).

{phang}
{opt prodfunc(string)} specifies the production function type. Options are "cd"
(Cobb-Douglas) or "translog". When explicit production-function coefficients
are supplied and any of {opt beta_ll()}, {opt beta_kk()}, or {opt beta_lk()}
is nonzero, omitting {opt prodfunc()} makes {cmd:_pte_omega} infer
{cmd:translog}. When {cmd:_pte_omega} reuses the existing {cmd:omega} from
EPIC-001 instead of recomputing it from explicit coefficients, omitting
{opt prodfunc()} first inherits the live EPIC-001 production-function
metadata from {cmd:e(prodfunc)} with fallback to legacy {cmd:e(pfunc)}; only
if neither metadata key is available does the command default to {cmd:cd}.
An explicit {cmd:prodfunc(cd)} with nonzero higher-order coefficients is
rejected.

{phang}
{opt touse(name)} specifies an active-sample indicator for the EPIC-002
workflow. {cmd:_pte_omega} restricts productivity recovery, evolution
estimation, and eps0 sample construction to observations with
{cmd:touse!=0} and nonmissing {cmd:touse}. In the evolution stage, the lagged
state must stay inside the same active sample as well: lagged evolution
regressors must also come from rows with {cmd:touse!=0}, so the package cannot
borrow {cmd:L.omega} or {cmd:L.treatment} from sample-out rows. This keeps the
full orchestrator aligned with an upstream sample boundary such as a
post-markout estimation sample; if {opt touse()} excludes all observations,
the command aborts. Even when the current row satisfies {cmd:touse!=0}, it
still drops from the evolution regression if the lag row that would supply
{cmd:L.omega} or {cmd:L.treatment} is sample-out. The posted {cmd:e(sample)}
and {cmd:e(N)} follow the active omega-recovery sample, while {cmd:e(N_evo)}
and the downstream eps0 support counts reflect the additional lag-source
requirement in the evolution regression. The supplied name must match an
existing numeric variable exactly; `_pte_omega' rejects abbreviation fallback
such as {cmd:touse(keep)} when the data only contain {cmd:keep_shadow}, and it
rejects string sample indicators at the entry gate.

{pstd}
If {opt touse()} is omitted and the current live {cmd:e(cmd)} is an EPIC-001 or
EPIC-002 bridge ({cmd:_pte_prodfunc}, {cmd:_pte_omega_recovery},
{cmd:_pte_evolution}, {cmd:_pte_treatdep_evolution}, {cmd:_pte_omega},
{cmd:_pte_eps0_sample}, {cmd:_pte_winsorize}, or {cmd:pte}),
{cmd:_pte_omega} reuses the current active-sample boundary instead of silently
expanding back to the full dataset. It first prefers the persisted indicator
{cmd:_pte_active_sample}. On the first bridge from {cmd:_pte_prodfunc}, when
that persisted EPIC-002 indicator does not yet exist, {cmd:_pte_omega} does
{bf:not} inherit the narrower GMM {cmd:e(sample)} from EPIC-001. Instead it
rebuilds the broader recoverable omega support from nonmissing {cmd:phi},
because Theorem 3.1 uses the non-transition sample to identify {it:beta} while
omega recovery and downstream ATT objects still live on the wider active panel
support. For the remaining live bridge commands, if {cmd:_pte_active_sample} is
unavailable the fallback is usually the current {cmd:e(sample)}. The only
exception is a live {cmd:_pte_winsorize} state: there, {cmd:e(sample)} marks
the trimmed/raw eps0 shock support rather than the broader EPIC-002 active
sample, so {cmd:_pte_omega} refuses that fallback and asks the caller to
supply {opt touse()} or rebuild {cmd:_pte_active_sample}. Outside those live
bridge contexts, omitting {opt touse()} means "use the full dataset."

{dlgtab:Display}

{phang}
{opt nodiagnose} suppresses all diagnostic output.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_omega} stores the following in {cmd:e()}:

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars - Evolution Coefficients}{p_end}
{synopt:{cmd:e(rho0)}}constant term{p_end}
{synopt:{cmd:e(rho1)}}first-order omega coefficient{p_end}
{synopt:{cmd:e(rho2)}}second-order omega coefficient (if omegapoly >= 2){p_end}
{synopt:{cmd:e(rho3)}}third-order omega coefficient (if omegapoly >= 3){p_end}
{synopt:{cmd:e(rho4)}}fourth-order omega coefficient (if omegapoly >= 4){p_end}
{synopt:{cmd:e(gamma1)}}first-order interaction coefficient; posted only when
effective treated-lag support exists{p_end}
{synopt:{cmd:e(gamma2)}}second-order interaction coefficient (if omegapoly >=
2); posted only when effective treated-lag support exists{p_end}
{synopt:{cmd:e(gamma3)}}third-order interaction coefficient (if omegapoly >= 3);
posted only when effective treated-lag support exists{p_end}
{synopt:{cmd:e(gamma4)}}fourth-order interaction coefficient (if omegapoly >=
4); posted only when effective treated-lag support exists{p_end}
{synopt:{cmd:e(delta)}}treatment direct effect; posted only when effective
treated-lag support exists{p_end}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars - Sample Sizes}{p_end}
{synopt:{cmd:e(N)}}observations in the active omega-recovery sample (=
{cmd:e(N_omega)}){p_end}
{synopt:{cmd:e(N_omega)}}observations with valid omega{p_end}
{synopt:{cmd:e(N_evo)}}observations in evolution regression{p_end}
{synopt:{cmd:e(N_lag_untreated)}}non-transition evolution rows with valid
untreated lag support ({cmd:D_{t-1}=0}){p_end}
{synopt:{cmd:e(N_lag_treated)}}non-transition evolution rows with valid treated
lag support before the live OLS omission check ({cmd:D_{t-1}=1}){p_end}
{synopt:{cmd:e(N_eps0)}}observations in eps0 sample{p_end}
{synopt:{cmd:e(N_eps0_trim)}}observations after Winsorize trimming{p_end}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars - Statistics}{p_end}
{synopt:{cmd:e(omega_mean)}}mean of omega{p_end}
{synopt:{cmd:e(omega_sd)}}standard deviation of omega{p_end}
{synopt:{cmd:e(r2_evo)}}R-squared of evolution regression{p_end}
{synopt:{cmd:e(rmse_evo)}}RMSE of evolution regression{p_end}
{synopt:{cmd:e(sigma_eps)}}raw standard deviation of eps0{p_end}
{synopt:{cmd:e(sigma_eps_trim)}}trimmed standard deviation used by the canonical
Gaussian ATT track{p_end}
{synopt:{cmd:e(eps0_p1)}}1st percentile cutoff{p_end}
{synopt:{cmd:e(eps0_p99)}}99th percentile cutoff{p_end}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars - Configuration}{p_end}
{synopt:{cmd:e(omegapoly)}}polynomial order used{p_end}
{synopt:{cmd:e(eps0window)}}eps0 innovation-window width in panel periods
({cmd:0} = full identified untreated support among admissible cohorts){p_end}
{synopt:{cmd:e(lag_treated_supported)}}1 if effective lag-treated support exists
after the live OLS omission check, 0 if the pooled regression continued with
treated-lag terms unsupported{p_end}
{synopt:{cmd:e(trimeps)}}1 if Winsorize enabled, 0 otherwise{p_end}
{synopt:{cmd:e(xtdelta)}}stored panel spacing from the live EPIC-002 estimation
axis when available{p_end}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Matrices}{p_end}
{synopt:{cmd:e(rho_0)}}control group evolution parameters [rho_0, rho_1, ...,
rho_p]{p_end}
{synopt:{cmd:e(rho_1)}}treated group evolution parameters [rho_0+delta,
rho_1+gamma_1, ...]; posted only when effective treated-lag support
exists{p_end}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Macros}{p_end}
{synopt:{cmd:e(treatment)}}treatment variable name{p_end}
{synopt:{cmd:e(treatsig)}}current treatment-law signature for downstream ATT /
graph certification on the live panel axis{p_end}
{synopt:{cmd:e(pfunc)}}legacy alias for the production function type (same value
as {cmd:e(prodfunc)}){p_end}
{synopt:{cmd:e(prodfunc)}}production function type{p_end}
{synopt:{cmd:e(id)}}stored panel identifier alias for downstream bridge
workers{p_end}
{synopt:{cmd:e(time)}}stored time variable alias for downstream bridge
workers{p_end}
{synopt:{cmd:e(idvar)}}stored estimation panel identifier for downstream bridge
workers{p_end}
{synopt:{cmd:e(timevar)}}stored estimation time variable for downstream bridge
workers{p_end}
{synopt:{cmd:e(eps0_dist)}}"normal"; EPIC-002 Gaussian approximation label for
untreated innovations, while downstream ATT still distinguishes the empirical
raw track and official translog Gaussian exceptions{p_end}
{synopt:{cmd:e(cmd)}}"_pte_omega"{p_end}


{marker examples}{...}
{title:Examples}

{pstd}Basic usage after EPIC-001:{p_end}
{phang2}{cmd:. _pte_omega, treatment(D) beta_l(0.6) beta_k(0.3)}{p_end}

{pstd}With Translog production function:{p_end}
{phang2}{cmd:. _pte_omega, treatment(D) prodfunc(translog) beta_l(0.5) beta_k(0.25) beta_ll(0.1) beta_kk(0.05) beta_lk(0.08)}{p_end}

{pstd}Different polynomial order:{p_end}
{phang2}{cmd:. _pte_omega, treatment(D) omegapoly(2) beta_l(0.6) beta_k(0.3)}{p_end}

{pstd}Respect an upstream sample boundary:{p_end}
{phang2}{cmd:. _pte_omega, treatment(D) beta_l(0.6) beta_k(0.3) touse(_pte_touse)}{p_end}

{pstd}Check evolution parameters:{p_end}
{phang2}{cmd:. matrix list e(rho_0)}{p_end}
{phang2}{cmd:. matrix list e(rho_1)}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z., & Schurter, K. (2026). Productivity Treatment Effects.
{it:Working Paper}. Equation (16), Section 6.3.

{phang}
Replication code: {cmd:DOs/prodest_3rd_poly.do},
{cmd:DOs/tt_estimation_program.do}
