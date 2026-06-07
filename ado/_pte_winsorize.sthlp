{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] _pte_omega" "help _pte_omega"}{...}
{vieweralsosee "[PTE] _pte_eps0_sample" "help _pte_eps0_sample"}{...}
{vieweralsosee "[PTE] _pte_evolution" "help _pte_evolution"}{...}
{viewerjumpto "Syntax" "_pte_winsorize##syntax"}{...}
{viewerjumpto "Description" "_pte_winsorize##description"}{...}
{viewerjumpto "Options" "_pte_winsorize##options"}{...}
{viewerjumpto "Stored results" "_pte_winsorize##results"}{...}
{viewerjumpto "Examples" "_pte_winsorize##examples"}{...}
{viewerjumpto "References" "_pte_winsorize##references"}{...}
{title:Title}

{p2colset 5 24 26 2}{...}
{p2col:{cmd:_pte_winsorize} {hline 2}}Winsorize eps0 distribution and estimate sigma for the canonical Gaussian ATT track{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_winsorize}
[{cmd:,} {it:options}]

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Main}
{synopt:{opt notrimeps}}disable Winsorize trimming (not recommended){p_end}
{synopt:{opt nodiag:nose}}suppress diagnostic output{p_end}
{synopt:{opt kstest}}run the Assumption 4.3 treated-vs-control K-S diagnostic on the eps0 sample{p_end}
{synopt:{opt treatment(name)}}treated-group indicator used by {opt kstest}; when supplied explicitly, the variable name must match an existing numeric column exactly and be coded 0/1 on the live K-S support; in panel data a time-varying indicator is collapsed to firm-level ever-treated status{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_winsorize} is an internal module of the {cmd:pte} package that implements
Step 4 of EPIC-002: Winsorize treatment of the eps0 (innovation shock) distribution
and the normal approximation used by the canonical Gaussian ATT track.

{pstd}
This module:

{phang2}1. Computes the original standard deviation of eps0{p_end}
{phang2}2. Calculates 1% and 99% percentiles{p_end}
{phang2}3. Trims observations outside [P1, P99] (unless {opt notrimeps} specified){p_end}
{phang2}4. Computes trimmed standard deviation (sigma_eps_trim){p_end}
{phang2}5. Stores results for use by EPIC-003 ATT estimation{p_end}

{pstd}
The trimmed standard deviation {cmd:e(sigma_eps_trim)} is used by the canonical
Gaussian ATT track to draw innovation shocks from N(0, sigma_eps_trim^2) when
constructing counterfactual productivity paths. The raw ATT track remains the
empirical eps0 pool unless a documented official translog Gaussian exception applies.

{pstd}
If the live eps0 support contains exactly one finite observation, Stata's
sample standard deviation is undefined. {cmd:_pte_winsorize} treats that case
as a valid degenerate innovation law and reports {cmd:e(sigma_eps)=0}; after
trimming, the same singleton logic applies to {cmd:e(sigma_eps_trim)}.

{pstd}
The live implementation intentionally uses a deterministic manual 1%/99% trim
for the eps0 working sample. As a result, {cmd:e(trim_method)} reports
{cmd:"manual"} under the default path and {cmd:"none"} when {opt notrimeps} is
specified.

{pstd}
As an {cmd:eclass} worker, {cmd:_pte_winsorize} now posts the exact live shock
support in {cmd:e(sample)}. Under the default path, {cmd:e(sample)} marks the
trimmed eps0 support used to estimate {cmd:e(sigma_eps_trim)} and to run the
live {opt kstest} diagnostic. Under {opt notrimeps}, it reverts to the raw
eps0 support. The automatic Stata scalar {cmd:e(N)} therefore equals the number
of observations in that live support, while {cmd:e(N_eps0)} and
{cmd:e(N_eps0_trim)} continue to expose the raw and trimmed pool sizes
separately.

{pstd}
When {opt kstest} is specified, {cmd:_pte_winsorize} also computes the
treated-vs-control Kolmogorov-Smirnov diagnostic used as empirical evidence for
Assumption 4.3 in Appendix E.3 of Chen, Liao & Schurter (2026). This diagnostic
compares the distribution of untreated productivity innovations in the
pre-treatment eps0 sample.

{pstd}
Paper-style Appendix E.3 / Table E.3 evidence is narrower than a generic
pooled {cmd:kstest} run: it is a {bf:by-industry} diagnostic on the
three-year pre-adoption untreated innovation support. In package terms, users
who want to mirror that paper workflow should first rebuild the live eps0
support with {cmd:eps0window(3)} inside each industry sample and then run
{cmd:_pte_winsorize, kstest}. Running {cmd:kstest} on the default live eps0
support ({cmd:eps0window(0)}) is still a valid diagnostic for the current
support definition, but it is not the paper-style Appendix E.3 design unless
the upstream window and by-industry workflow have already been imposed. Under
that paper-style design, the treated-vs-control comparison is the distribution
of untreated innovations for {bf:eventually treated} firms versus controls
within the pre-treatment window; it is not a current-period {cmd:D_t}
partition on an arbitrary pooled live sample.

{pstd}
When {cmd:_pte_winsorize} is run immediately after {cmd:_pte_eps0_sample},
{cmd:_pte_omega}, the public wrapper {cmd:pte}, or another fresh
{cmd:_pte_winsorize} call in the paper/DO style EPIC-002 pipeline, it also
preserves the live evolution bridge needed by {cmd:_pte_att}: the
untreated/treated evolution matrices and key metadata are forwarded in
{cmd:e()} alongside the eps0 distribution moments. This bridge now
also preserves the evolution fit diagnostics when they are available upstream:
{cmd:e(N_evo)} plus the standardized {cmd:e(r2_evo)} / {cmd:e(rmse_evo)} pair,
with compatibility aliases in {cmd:e(r2)} / {cmd:e(rmse)}. It also preserves
the lag-support identification diagnostics from the upstream evolution state:
{cmd:e(N_lag_untreated)}, {cmd:e(N_lag_treated)}, and
{cmd:e(lag_treated_supported)}. When the upstream bridge already recorded how
the untreated innovation support was windowed, the same live state also
preserves {cmd:e(eps0window)} because winsorization only changes the shock
distribution approximation and does not redefine the eps0 support window.
The same bridge now also retains the live panel metadata keys
{cmd:e(idvar)} / {cmd:e(timevar)} (with legacy aliases {cmd:e(id)} /
{cmd:e(time)}) plus {cmd:e(xtdelta)} when they were present upstream.
These bridge results are only present when the incoming {cmd:e()} comes from
one of those EPIC-002 commands and already contains the upstream evolution
state.

{pstd}
{bf:Prerequisites:} This module requires:

{phang2}- Numeric variable {cmd:_pte_eps0} containing the innovation residuals{p_end}
{phang2}- Numeric variable {cmd:_pte_eps0_ind} indicating the eps0 sample (=1 for valid observations){p_end}

{pstd}
These variables are created by {cmd:_pte_eps0_sample} (US-E2-003).


{marker options}{...}
{title:Options}

{dlgtab:Main}

{phang}
{opt notrimeps} disables Winsorize trimming. When specified, {cmd:e(sigma_eps_trim)}
equals {cmd:e(sigma_eps)} (the raw standard deviation). This option is {bf:not recommended}
per Chen, Liao & Schurter (2026) Section 6.3.3, as the TT estimate may be sensitive
to outliers in the eps0 distribution.

{phang}
{opt nodiagnose} suppresses all diagnostic output. Useful when called from other
programs or in batch mode.

{phang}
{opt kstest} runs a treated-vs-control two-sample Kolmogorov-Smirnov test on the
effective eps0 sample. By default this is the same 1%/99% trimmed support used
for {cmd:e(sigma_eps_trim)}; with {opt notrimeps}, it reverts to the raw eps0
sample. The test is only executed when both groups have at least five
observations; otherwise the module stores an "Insufficient obs" status. To
replicate the paper-style Appendix E.3 evidence rather than a generic live
support check, rebuild the eps0 support upstream with {cmd:eps0window(3)} and
run the diagnostic within each industry sample. In that paper-style workflow,
the relevant grouping is eventually treated firms versus controls on the
pre-treatment eps0 support, not the current-period {cmd:D_t} split on an
arbitrary pooled sample.

{phang}
{opt treatment(name)} specifies the grouping variable used by {opt kstest}.
This should identify treated firms, and an explicit {opt treatment()} must
match an existing numeric variable name exactly. When supplied explicitly, the
variable must be coded {cmd:0}/{cmd:1} on the effective live eps0 support used
by the K-S diagnostic; sample-out observations outside that support do not veto
the test. Nonbinary numeric group codes that enter the live K-S support are
rejected at the entry gate because the K-S diagnostic is defined as a treated-
vs-control split rather than an arbitrary two-group partition. For example, if
the dataset
contains only {cmd:D_shadow}, then {cmd:treatment(D)} is rejected instead of
silently binding to {cmd:D_shadow}. If the data are {cmd:xtset} and the
supplied variable varies over time, {cmd:_pte_winsorize} collapses it to the
firm-level ever-treated indicator using only the live K-S support before
running the K-S test. Whenever the
dataset already contains the cohort metadata {cmd:_pte_treat_year} published by
{cmd:_pte_eps0_sample}: nonmissing {cmd:_pte_treat_year} defines the
eventually treated group and missing values define the never-treated control
group. If an explicit {opt treatment()} variable is time-varying within panel,
this cohort split takes precedence over the current-period indicator so the
Appendix E.3 treated-vs-control partition survives pure pre-treatment slices
where the live {cmd:D_t} column no longer reveals eventual treatment status.
Explicit static grouping variables are still respected as supplied. If
that cohort metadata is unavailable, or if the explicit grouping variable is
already static within panel, the command next reuses the
live EPIC-002 treatment variable stored in {cmd:e(treatment)} when that state
is available and the named variable still exists in the data. If no live
treatment bridge is available, it then looks for {cmd:treat}; if unavailable,
it falls back to {cmd:treat_post} and applies the same firm-level collapsing in
panel data. If no usable grouping variable can be found, the module skips the
K-S calculation and sets {cmd:e(ks_result)} to {cmd:"No treatment var"}.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_winsorize} stores the following in {cmd:e()}:

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars}{p_end}
{synopt:{cmd:e(N)}}observations in the live support marked by {cmd:e(sample)}; trimmed support by default, raw eps0 support under {opt notrimeps}{p_end}
{synopt:{cmd:e(sigma_eps)}}raw standard deviation of eps0{p_end}
{synopt:{cmd:e(sigma_eps_trim)}}trimmed standard deviation used by the canonical Gaussian ATT track; singleton supports are reported as 0 rather than rejected{p_end}
{synopt:{cmd:e(N_eps0)}}number of observations in eps0 sample{p_end}
{synopt:{cmd:e(N_eps0_trim)}}number of observations after trimming{p_end}
{synopt:{cmd:e(eps0_p1)}}1st percentile cutoff{p_end}
{synopt:{cmd:e(eps0_p99)}}99th percentile cutoff{p_end}
{synopt:{cmd:e(eps0_skewness)}}skewness of the live eps0 support; trimmed support by default, raw eps0 support under {opt notrimeps}{p_end}
{synopt:{cmd:e(eps0_kurtosis)}}kurtosis of the live eps0 support; trimmed support by default, raw eps0 support under {opt notrimeps}{p_end}
{synopt:{cmd:e(trimeps)}}1 if Winsorize enabled, 0 if disabled{p_end}
{synopt:{cmd:e(ks_D)}}K-S statistic for the treated-vs-control eps0 comparison (only with {opt kstest}){p_end}
{synopt:{cmd:e(ks_p)}}finite-sample corrected K-S p-value (only with {opt kstest}){p_end}
{synopt:{cmd:e(ks_p_exact)}}exact K-S p-value returned by {cmd:ksmirnov} (only with {opt kstest}){p_end}
{synopt:{cmd:e(ks_n_treat)}}treated-group observations used by the K-S diagnostic (only with {opt kstest}){p_end}
{synopt:{cmd:e(ks_n_ctrl)}}control-group observations used by the K-S diagnostic (only with {opt kstest}){p_end}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Macros}{p_end}
{synopt:{cmd:e(eps0_dist)}}"normal" (distribution assumption){p_end}
{synopt:{cmd:e(trim_method)}}"manual" by default, or "none" with {opt notrimeps}{p_end}
{synopt:{cmd:e(ks_result)}}K-S diagnostic conclusion/skip status: {cmd:"Cannot reject H0"}, {cmd:"Reject H0"}, {cmd:"Insufficient obs"}, or {cmd:"No treatment var"} (only with {opt kstest}){p_end}
{synopt:{cmd:e(cmd)}}"_pte_winsorize"{p_end}
{synopt:{cmd:e(title)}}"PTE eps0 distribution estimation"{p_end}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Conditionally Preserved Bridge Results}{p_end}
{synopt:{cmd:e(omegapoly)}}evolution-polynomial order forwarded from the upstream evolution state (only when available on entry){p_end}
{synopt:{cmd:e(rho_0)}}untreated evolution coefficients forwarded for the downstream ATT bridge (only when available on entry){p_end}
{synopt:{cmd:e(rho_1)}}treated evolution coefficients forwarded for the downstream ATT bridge (only when available on entry){p_end}
{synopt:{cmd:e(eps0window)}}untreated innovation-support window forwarded from the upstream EPIC-002 state; trimming does not alter this support definition (only when available on entry){p_end}
{synopt:{cmd:e(N_evo)}}evolution-regression sample size forwarded from the upstream evolution state (only when available on entry){p_end}
{synopt:{cmd:e(N_lag_untreated)}}untreated lag-support count forwarded from the upstream evolution state (only when available on entry){p_end}
{synopt:{cmd:e(N_lag_treated)}}treated lag-support count forwarded from the upstream evolution state (only when available on entry){p_end}
{synopt:{cmd:e(lag_treated_supported)}}treated-lag support flag forwarded from the upstream evolution state (only when available on entry){p_end}
{synopt:{cmd:e(r2_evo)}}evolution R-squared forwarded under the standardized EPIC-002 key (only when available on entry){p_end}
{synopt:{cmd:e(rmse_evo)}}evolution RMSE forwarded under the standardized EPIC-002 key (only when available on entry){p_end}
{synopt:{cmd:e(r2)}}compatibility alias for the forwarded evolution R-squared (only when available on entry){p_end}
{synopt:{cmd:e(rmse)}}compatibility alias for the forwarded evolution RMSE (only when available on entry){p_end}
{synopt:{cmd:e(treatment)}}treatment variable name forwarded from the upstream evolution state (only when available on entry){p_end}
{synopt:{cmd:e(treatsig)}}current treatment-law signature forwarded/rebuilt from the upstream EPIC-002 state for downstream ATT / graph certification (only when available on entry){p_end}
{synopt:{cmd:e(pfunc)}}legacy production-function alias forwarded from the upstream evolution state (only when available on entry){p_end}
{synopt:{cmd:e(prodfunc)}}normalized production-function metadata forwarded from the upstream evolution state (only when available on entry){p_end}
{synopt:{cmd:e(idvar)}}panel identifier forwarded from the upstream EPIC-002 state (only when available on entry){p_end}
{synopt:{cmd:e(timevar)}}time variable forwarded from the upstream EPIC-002 state (only when available on entry){p_end}
{synopt:{cmd:e(id)}}legacy alias of {cmd:e(idvar)} forwarded from the upstream EPIC-002 state (only when available on entry){p_end}
{synopt:{cmd:e(time)}}legacy alias of {cmd:e(timevar)} forwarded from the upstream EPIC-002 state (only when available on entry){p_end}
{synopt:{cmd:e(xtdelta)}}panel spacing forwarded from the upstream EPIC-002 state (only when available on entry){p_end}


{marker examples}{...}
{title:Examples}

{pstd}Basic usage (after running US-E2-003):{p_end}
{phang2}{cmd:. _pte_winsorize}{p_end}

{pstd}Disable Winsorize for sensitivity analysis:{p_end}
{phang2}{cmd:. _pte_winsorize, notrimeps}{p_end}

{pstd}Silent mode:{p_end}
{phang2}{cmd:. _pte_winsorize, nodiagnose}{p_end}

{pstd}Run a generic live-support K-S diagnostic:{p_end}
{phang2}{cmd:. _pte_winsorize, kstest treatment(treat)}{p_end}

{pstd}Mirror the paper-style Appendix E.3 K-S workflow inside one industry sample:{p_end}
{phang2}{cmd:. _pte_eps0_sample, treatment(D) eps0window(3)}{p_end}
{phang2}{cmd:. _pte_winsorize, kstest treatment(treat)}{p_end}

{pstd}Check stored results:{p_end}
{phang2}{cmd:. ereturn list}{p_end}
{phang2}{cmd:. display "sigma_eps_trim = " e(sigma_eps_trim)}{p_end}
{phang2}{cmd:. display "ks_result = " e(ks_result)}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z., & Schurter, K. (2026). Productivity Treatment Effects.
{it:Working Paper}. Section 6.3.3.

{phang}
Replication code reference: {cmd:DOs/tt_estimation_program.do} L49-59,
{cmd:DOs/att_estimation_program_translog.do} L52-59.


{marker author}{...}
{title:Author}

{pstd}
PTE Package Development Team
{p_end}
