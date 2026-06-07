{smcl}
{* *! version 1.0.0  01jan2026}{...}
{* *! US-E2-001: Productivity Recovery + EPIC-001 Interface Validation}{...}

{cmd:help _pte_omega_recovery}{right:PTE Package}
{hline}

{title:Title}

{p2colset 5 30 32 2}{...}
{p2col:{hi:_pte_omega_recovery} {hline 2} Productivity Recovery from First-Stage Estimates}{p_end}
{p2colreset}{...}


{title:Syntax}

{p 8 32 2}{cmd:_pte_omega_recovery}, {opt free(name)} {opt state(name)}
[{it:options}]

{p 8 32 2}{cmd:_pte_omega_recovery}, {opt beta_l(#)} {opt beta_k(#)}
[{it:options}]

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:EPIC-001 mode}
{p2coldent:* {opt free(name)}}free variable (labor, in logs){p_end}
{p2coldent:* {opt state(name)}}state variable (capital, in logs){p_end}

{syntab:Standalone mode}
{synopt:{opt beta_l(#)}}labor coefficient in standalone mode{p_end}
{synopt:{opt beta_k(#)}}capital coefficient in standalone mode{p_end}
{synopt:{opt beta_ll(#)}}labor squared coefficient in standalone Translog
mode{p_end}
{synopt:{opt beta_kk(#)}}capital squared coefficient in standalone Translog
mode{p_end}
{synopt:{opt beta_lk(#)}}labor-capital interaction coefficient in standalone
Translog mode{p_end}
{syntab:Common options}
{synopt:{opt pfunc(string)}}production function type; {cmd:cd} or
{cmd:translog}; default from {cmd:e(prodfunc)} with fallback to legacy
{cmd:e(pfunc)}, or inferred as {cmd:translog} when standalone higher-order
coefficients are nonzero{p_end}
{synopt:{opt touse(name)}}exact-name numeric sample indicator; recover
{cmd:omega} only where {cmd:touse!=0} and nonmissing{p_end}
{synopt:{opt nodiag:nose}}suppress diagnostic output{p_end}
{synopt:{opt verify}}check phi-method and direct-method equivalence{p_end}
{synopt:{opt depvar(name)}}exact-name log output variable for direct-method
verification{p_end}
{synopt:{opt time(name)}}legacy direct-method control variable; not used in the
direct subtraction when {cmd:e(beta_controls)} exists, and unnecessary in
zero-control verification{p_end}
{synopt:{opt beta_t(#)}}legacy scalar coefficient for {opt time()} in standalone
verification; omit it in zero-control verification{p_end}
{synopt:{opt debug}}display detailed equivalence diagnostics under
{opt verify}{p_end}
{synoptline}
{p 4 6 2}
{cmd:*} Choose one entry mode: either {opt free()} + {opt state()} for EPIC-001
integration, or {opt beta_l()} + {opt beta_k()} for standalone recovery.
These two entry modes are mutually exclusive; specifying both causes
{cmd:_pte_omega_recovery} to return {cmd:r(198)}.{p_end}
{p 4 6 2}
Both modes require an existing exact-name {cmd:phi} variable. Abbreviation
fallbacks such as {cmd:phi_*} are rejected. In the public PTE workflow,
{cmd:phi} is the control-adjusted first-stage productivity proxy published by
{cmd:_pte_prodfunc}, not the raw fitted value before control removal, and
{cmd:phi} must be numeric. EPIC-001
mode additionally requires prior execution of {cmd:_pte_prodfunc} so that
{cmd:e(b)} and the production-function metadata ({cmd:e(prodfunc)} with
legacy fallback {cmd:e(pfunc)}) are available.{p_end}
{p 4 6 2}
In EPIC-001 mode, {cmd:_pte_omega_recovery} also validates that the current
{cmd:e(b)} uses the exact PTE production-function coefficient layout:
{cmd:free state} for Cobb-Douglas and {cmd:free state l2 k2 l1k1} for
Translog. Foreign live estimation results with unrelated coefficient names are
rejected even when the column count happens to be 2 or 5, because EPIC-001
recovery must consume the production-function beta vector rather than an
arbitrary regression result.{p_end}
{p 4 6 2}
In standalone mode, do not specify {opt free()} and {opt state()} together with
{opt beta_l()} and {opt beta_k()}. When the standalone beta options are used,
the free/state variable names are inferred from current e()-results when
available, or from the default variables {cmd:lnl} and {cmd:lnk}. If the
inferred {cmd:e(free)} or {cmd:e(state)} names are absent from the current
dataset, or exist there but are not numeric, {cmd:_pte_omega_recovery}
discards those stale names and falls back to the live {cmd:lnl}/{cmd:lnk}
variables instead.{p_end}
{p 4 6 2}
Under {opt verify}, EPIC-001 mode reuses {cmd:e(beta_controls)} so the direct
method uses the same grouped-time / stage-1 controls as the original first-stage
regression. Each control named in {cmd:e(beta_controls)} must exist in the
current data with the exact same variable name and be numeric; abbreviation
fallbacks such as {cmd:t} binding to {cmd:t_shadow} are rejected.{p_end}


{title:Description}

{pstd}
{cmd:_pte_omega_recovery} recovers firm-level productivity (omega) from the
control-adjusted first-stage productivity proxy ({cmd:phi}) and estimated
production function parameters. First-stage controls are already removed from
phi
before this command runs. This is the first step in EPIC-002
(Productivity Recovery and Evolution) of the PTE package.

{pstd}
The command supports two entry modes:

{phang2}{bf:EPIC-001 mode:} read coefficients from {cmd:e(b)} after
{cmd:_pte_prodfunc} using {opt free()} and {opt state()}.{p_end}
{phang2}{bf:Standalone mode:} recover omega from user-supplied
{opt beta_l()} and {opt beta_k()} coefficients, with optional Translog
terms {opt beta_ll()}, {opt beta_kk()}, and {opt beta_lk()}.{p_end}

{pstd}
In both modes, the command uses the existing control-adjusted {cmd:phi}
variable and computes:

{p 8 12 2}
{bf:Cobb-Douglas:} omega = phi - beta_l * l - beta_k * k

{p 8 12 2}
{bf:Translog:} omega = phi - beta_l * l - beta_k * k - beta_ll * l^2 - beta_kk *
k^2 - beta_lk * l * k

{pstd}
The recovered productivity variable {cmd:omega} is used by subsequent modules
for evolution estimation (US-E2-002) and ATT calculation (EPIC-003).

{pstd}
When {opt touse(name)} is supplied, {cmd:_pte_omega_recovery} restricts
recovery to the active estimation sample defined by {cmd:touse!=0} and
nonmissing {cmd:touse}. Observations outside that boundary keep missing
{cmd:omega}; if {opt touse()} excludes all observations, the command aborts.
This is the intended way to keep EPIC-002 aligned with upstream sample filters
such as transition-period exclusion.


{title:Options}

{dlgtab:EPIC-001 mode}

{phang}
{opt free(name)} specifies the free variable (labor input, in logs).
The name must match an existing variable exactly; abbreviation fallback such as
{cmd:free(lnl)} binding to {cmd:lnl_shadow} is rejected. The variable must also
be numeric; string inputs are rejected at the command entry gate.

{phang}
{opt state(name)} specifies the state variable (capital input, in logs).
The name must match an existing variable exactly; abbreviation fallback such as
{cmd:state(lnk)} binding to {cmd:lnk_shadow} is rejected. The variable must
also be numeric; string inputs are rejected at the command entry gate.

{dlgtab:Standalone mode}

{phang}
{opt beta_l(#)} and {opt beta_k(#)} provide the Cobb-Douglas coefficients for
standalone mode. When these are supplied, {cmd:_pte_omega_recovery} does not
require current {cmd:e(b)} results from EPIC-001.

{phang}
{opt beta_ll(#)}, {opt beta_kk(#)}, and {opt beta_lk(#)} provide higher-order
Translog coefficients in standalone mode. If any of them is nonzero and
{opt pfunc()} is omitted, the command infers {cmd:translog}. An explicit
{cmd:pfunc(cd)} with nonzero higher-order coefficients is rejected.

{dlgtab:Common options}

{phang}
{opt pfunc(string)} specifies the production function type.  Valid values
are {cmd:cd} (Cobb-Douglas) and {cmd:translog}.  If not specified, EPIC-001
mode first reads {cmd:e(prodfunc)} and falls back to legacy {cmd:e(pfunc)}
when the normalized metadata is absent. In standalone mode, the default is
{cmd:cd} unless any of {opt beta_ll()}, {opt beta_kk()}, or {opt beta_lk()}
is nonzero, in which case {cmd:_pte_omega_recovery} infers {cmd:translog}.
When standalone inference encounters stale {cmd:e(free)} or {cmd:e(state)}
names that are absent from the current data, or present there but nonnumeric,
the command falls back to the canonical {cmd:lnl}/{cmd:lnk} variable names
before reporting an error.
In EPIC-001 mode, if live metadata such as {cmd:e(free)}, {cmd:e(state)}, or
{cmd:e(prodfunc)}/{cmd:e(pfunc)} are present, they must agree with the current
{opt free()}, {opt state()}, and {opt pfunc()} request; otherwise the command
returns {cmd:r(198)} instead of silently mixing incompatible stage-1 results.

{phang}
{opt touse(name)} specifies a sample indicator for recovery. The supplied
name must match the exact variable name of an existing numeric variable;
abbreviation fallback
such as {cmd:touse(keep)} binding to {cmd:keep_shadow} is rejected. {cmd:omega}
is generated only on observations with {cmd:touse!=0} and nonmissing
{cmd:touse}. The variable must be numeric; string sample flags are rejected
at the entry gate with {cmd:r(111)}. Observations outside that sample remain
missing. This is useful
when EPIC-002 must inherit an upstream estimation boundary.

{phang}
{opt nodiagnose} suppresses the diagnostic output tables.  By default, the
command displays validation results and omega summary statistics.

{phang}
{opt verify} checks the equivalence between the recovered
{cmd:omega = phi - f(l,k;beta)} path and the direct reconstruction
{cmd:omega = y - f(l,k;beta) - controls}. In EPIC-001 mode, the controls are
rebuilt from {cmd:e(beta_controls)} rather than a standalone {cmd:e(beta_t)}
scalar. If there are no controls in the current verification design, you may
omit both {opt time()} and {opt beta_t()}; the direct reconstruction then
reduces to {cmd:omega = y - f(l,k;beta)}. When {cmd:e(beta_controls)} is
present, the current dataset must still contain those original stage-1 control
variables with their exact names and numeric types.

{phang}
{opt depvar(name)} specifies the numeric log-output variable used by the
direct reconstruction when {opt verify} is requested. The name must match an
existing variable exactly; abbreviation fallback such as {cmd:depvar(depvar)}
binding to {cmd:depvar_shadow} is rejected, and string output variables are
rejected at the entry gate with {cmd:r(111)}.

{phang}
{opt time(name)} specifies the legacy single control variable for direct
verification. It is only used when {cmd:e(beta_controls)} is unavailable, and
the current dataset must contain that legacy control with the exact variable
name and numeric type. If the verification design has no controls, omit
{opt time()} entirely.

{phang}
{opt beta_t(#)} supplies the scalar coefficient for {opt time()} in standalone
verification. It is not required when EPIC-001 published {cmd:e(beta_controls)}.
If the verification design has no controls, omit {opt beta_t()} and the direct
reconstruction uses no extra subtraction term.

{phang}
{opt debug} prints detailed correlation and difference diagnostics for the
equivalence check.


{title:Generated variables}

{synoptset 14 tabbed}{...}
{synopt:{cmd:omega}}double; recovered productivity (log TFP){p_end}
{p2colreset}{...}

{pstd}
The variable {cmd:omega} is labeled "Recovered productivity (log TFP)".
Any existing variable named {cmd:omega} is dropped before generation.
If a post-generation recovery or {opt verify} failure occurs,
{cmd:_pte_omega_recovery} removes the generated {cmd:omega} before exiting so
downstream evolution, eps0, and ATT steps cannot consume a rejected state.


{title:Stored results}

{pstd}
{cmd:_pte_omega_recovery} stores the following in {cmd:e()}:

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:e(N)}}number of valid omega observations (same as
{cmd:e(N_omega)}){p_end}
{synopt:{cmd:e(N_omega)}}number of valid omega observations{p_end}
{synopt:{cmd:e(n_missing)}}number of missing omega due to missing inputs{p_end}
{synopt:{cmd:e(omega_mean)}}mean of omega{p_end}
{synopt:{cmd:e(omega_sd)}}standard deviation of omega{p_end}
{synopt:{cmd:e(omega_min)}}minimum of omega{p_end}
{synopt:{cmd:e(omega_max)}}maximum of omega{p_end}
{synopt:{cmd:e(omega_p50)}}median of omega{p_end}
{synopt:{cmd:e(beta_l)}}labor coefficient used in recovery{p_end}
{synopt:{cmd:e(beta_k)}}capital coefficient used in recovery{p_end}
{synopt:{cmd:e(beta_ll)}}labor squared coefficient used in Translog
recovery{p_end}
{synopt:{cmd:e(beta_kk)}}capital squared coefficient used in Translog
recovery{p_end}
{synopt:{cmd:e(beta_lk)}}labor-capital interaction coefficient used in Translog
recovery{p_end}
{synopt:{cmd:e(method_corr)}}correlation between phi-method and direct-method
omega under {opt verify}{p_end}
{synopt:{cmd:e(equiv_pass)}}1 if the equivalence check passes under
{opt verify}: with multiple valid pairs, correlation exceeds 0.9999 and
{cmd:e(max_diff)} < 1e-8 and {cmd:e(mean_diff)} < 1e-10; with exactly one valid
pair, the direct comparison alone must pass and {cmd:e(method_corr)} is
missing{p_end}
{synopt:{cmd:e(max_diff)}}maximum absolute difference under {opt verify}{p_end}
{synopt:{cmd:e(mean_diff)}}mean absolute difference under {opt verify}{p_end}

{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:e(prodfunc)}}normalized production function type used{p_end}
{synopt:{cmd:e(pfunc)}}production function type used{p_end}
{synopt:{cmd:e(free)}}free variable name{p_end}
{synopt:{cmd:e(state)}}state variable name{p_end}
{synopt:{cmd:e(cmd)}}{cmd:"_pte_omega_recovery"}{p_end}
{p2colreset}{...}


{title:Error codes}

{synoptset 10 tabbed}{...}
{synopt:{cmd:111}}specified input variable not found, or an input variable
exists but is not numeric{p_end}
{synopt:{cmd:198}}missing mode inputs, mutually exclusive mode inputs, phi not
found, e(b) not found, e(b) dimension mismatch, EPIC-001 coefficient
layout/metadata mismatch, or invalid pfunc{p_end}
{synopt:{cmd:2000}}phi has no valid observations, touse() excludes all
observations, no recoverable omega values remain in the active sample, or there
are no valid observations for verify pairing{p_end}
{synopt:{cmd:2001}}verify equivalence failed{p_end}
{synopt:{cmd:2002}}verify detected negative correlation between methods{p_end}
{p2colreset}{...}


{title:Examples}

{pstd}Setup: run EPIC-001 first{p_end}

{phang2}{cmd:. use "data/mydata.dta", clear}{p_end}
{phang2}{cmd:. xtset firm year}{p_end}
{phang2}{cmd:. _pte_prodfunc, free(lnl) proxy(lnm) state(lnk) pfunc(cd)}{p_end}

{pstd}Basic usage: recover productivity{p_end}
{phang2}{cmd:. _pte_omega_recovery, free(lnl) state(lnk)}{p_end}

{pstd}Suppress diagnostic output{p_end}
{phang2}{cmd:. _pte_omega_recovery, free(lnl) state(lnk) nodiagnose}{p_end}

{pstd}Translog production function{p_end}
{phang2}{cmd:. _pte_prodfunc, free(lnl) proxy(lnm) state(lnk) pfunc(translog)}{p_end}
{phang2}{cmd:. _pte_omega_recovery, free(lnl) state(lnk)}{p_end}

{pstd}Standalone mode with supplied coefficients{p_end}
{phang2}{cmd:. _pte_omega_recovery, beta_l(0.60) beta_k(0.30)}{p_end}

{pstd}Respect an upstream sample boundary{p_end}
{phang2}{cmd:. _pte_omega_recovery, free(lnl) state(lnk) touse(_pte_touse)}{p_end}

{pstd}Standalone Translog mode with supplied coefficients{p_end}
{phang2}{cmd:. _pte_omega_recovery, beta_l(0.55) beta_k(0.25) beta_ll(0.02) beta_kk(0.01) beta_lk(0.03)}{p_end}

{pstd}Inspect stored results{p_end}
{phang2}{cmd:. ereturn list}{p_end}

{pstd}Use omega for evolution estimation{p_end}
{phang2}{cmd:. gen double omega2 = omega^2}{p_end}
{phang2}{cmd:. gen double omega3 = omega^3}{p_end}


{title:Theoretical background}

{pstd}
The productivity recovery step is based on the production function
specification from Chen, Liao & Schurter (2026). When first-stage controls
(for example, time trends) are included upstream, the raw proxy can be written
as:

{p 8 12 2}
phi_raw = f(k, l; beta) + controls + omega

{pstd}
The released PTE workflow removes those controls before recovery, so this
command takes as input:

{p 8 12 2}
phi = phi_raw - controls

{pstd}
Productivity is recovered as the residual:

{p 8 12 2}
omega = phi - f(k, l; beta)

{pstd}
For Cobb-Douglas (Equation 14 of the paper):

{p 8 12 2}
f(k, l; beta) = beta_l * l + beta_k * k

{pstd}
For Translog (Equation 15 of the paper):

{p 8 12 2}
f(k, l; beta) = beta_l * l + beta_k * k + beta_ll * l^2 + beta_kk * k^2 +
beta_lk * l * k

{pstd}
The recovered omega is then used to estimate the productivity evolution
process (Proposition 4.1) and calculate treatment effects (Proposition 4.3).


{title:References}

{phang}
Ackerberg, D. A., Caves, K., and Frazer, G. (2015).
Identification Properties of Recent Production Function Estimators.
{it:Econometrica} 83(6): 2411-2451.
{p_end}

{phang}
Chen, X., Liao, Y., and Schurter, K. (2026).
Identifying Treatment Effects on Productivity.
{it:Working Paper}.
{p_end}


{title:Author}

{pstd}PTE Development Team{p_end}


{title:Also see}

{psee}
Online: {helpb _pte_prodfunc}, {helpb _pte_polyvar}, {helpb _pte_transition}
{p_end}
