{smcl}
{* *! version 1.0.0  01jan2026}{...}
{* *! Assumption D.3-D.4 Tests for Counterfactual Analysis}{...}
{* *! Chen, Liao & Schurter (2026)}{...}

{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] pte_diagnose" "help pte_diagnose"}{...}
{vieweralsosee "[R] ksmirnov" "help ksmirnov"}{...}
{vieweralsosee "[R] lrtest" "help lrtest"}{...}
{viewerjumpto "Syntax" "_pte_cf_assumption_tests##syntax"}{...}
{viewerjumpto "Description" "_pte_cf_assumption_tests##description"}{...}
{viewerjumpto "Options" "_pte_cf_assumption_tests##options"}{...}
{viewerjumpto "Remarks" "_pte_cf_assumption_tests##remarks"}{...}
{viewerjumpto "Stored results" "_pte_cf_assumption_tests##results"}{...}
{viewerjumpto "References" "_pte_cf_assumption_tests##references"}{...}

{cmd:help _pte_cf_assumption_tests}{right:also see: {help pte:pte}}
{hline}

{marker title}{...}
{title:Title}

{p2colset 5 38 40 2}{...}
{p2col:{hi:_pte_cf_assumption_tests} {hline 2} Assumption D.3-D.4 diagnostic tests for counterfactual ATE estimation}{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:_pte_cf_assumption_tests},
{opt t0(#)}
{opt s(#)}
{opt targetvar(varname)}
{opt omega(varname)}
[{it:options}]

{synoptset 28 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt t0(#)}}reference time (first treatment period){p_end}
{synopt:{opt s(#)}}delay parameter (expansion time = t0 + s){p_end}
{synopt:{opt targetvar(varname)}}0/1 variable identifying the target group
G{p_end}
{synopt:{opt omega(varname)}}productivity variable{p_end}

{syntab:Optional}
{synopt:{opt omegapoly(#)}}evolution polynomial order; default is
{cmd:omegapoly(3)}{p_end}
{synopt:{opt panelvar(varname)}}panel identifier; default is {cmd:firm}{p_end}
{synopt:{opt timevar(varname)}}time variable; default is {cmd:year}{p_end}
{synopt:{opt treatvar(varname)}}ever-treated indicator; defaults to the exact
live {cmd:_pte_treat} bridge when available, else {cmd:treated}{p_end}
{synopt:{opt midvar(varname)}}transition indicator; defaults to the exact live
{cmd:_pte_mid} bridge when available, else {cmd:mid}{p_end}
{synopt:{opt cohortvar(varname)}}firm-level first treatment period {it:e_i};
defaults to the exact live {cmd:_pte_treat_year} bridge or {cmd:treat_year} when
available{p_end}
{synopt:{opt statusvar(varname)}}time-varying treatment status used only to
derive {opt cohortvar()} when no treatment-year variable exists; exact name
required when supplied{p_end}
{synopt:{opt alpha(#)}}significance level; default is {cmd:alpha(0.05)}{p_end}
{synopt:{opt overlap_threshold(#)}}minimum overlap ratio; default is
{cmd:overlap_threshold(0.8)}{p_end}
{synopt:{opt noreport}}suppress diagnostic output{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_cf_assumption_tests} performs diagnostic tests for the two key
assumptions underlying counterfactual ATE estimation in the CLK framework
(Chen, Liao & Schurter, 2026, Appendix D).

{pstd}
The command tests:

{p 4 8 2}
{bf:Assumption D.3 (Time Stability)}: The productivity evolution function
parameters (rho_0, rho_1, ...) remain stable over the sample period. This is
tested using a likelihood ratio (LR) test comparing a restricted model with
stable parameters against an unrestricted model allowing time-varying
parameters via interaction with a late-period indicator.

{p 4 8 2}
{bf:Assumption D.4 (Distributional Comparability)}: The productivity
distribution of the target group G at t0+s-1 is comparable to the
pre-treatment productivity distribution of the treated group. This is tested
using a two-sample Kolmogorov-Smirnov test.

{pstd}
Additionally, the command computes an overlap assessment measuring what
fraction of target group firms have productivity values within the support
of the treated group's pre-treatment distribution.

{pstd}
This is an internal command. Users typically access these tests through the
{opt diagnose} option of {cmd:_pte_cf_divergent} or {cmd:_pte_cf_matching}.
The helper is {cmd:rclass}: it reports diagnostics in {cmd:r()} and restores
the caller's active {cmd:e()} results after the internal D.3 regressions.


{marker options}{...}
{title:Options}

{dlgtab:Required}

{phang}
{opt t0(#)} specifies the reference time (first treatment period). This
defines the start of the treatment window.

{phang}
{opt s(#)} specifies the delay parameter. The expansion time is t0 + s, and
the target group is evaluated at t0 + s - 1.

{phang}
{opt targetvar(varname)} specifies a 0/1 variable identifying the target
group G (untreated firms that would be affected by treatment expansion).

{phang}
{opt omega(varname)} specifies the productivity variable to test.

{dlgtab:Optional}

{phang}
{opt omegapoly(#)} specifies the polynomial order for the evolution function.
The D.3 test uses this to determine the number of interaction terms. The
degrees of freedom for the LR test equal omegapoly + 1 (intercept interaction
plus slope interactions). Default is 3.

{phang}
{opt treatvar(varname)} specifies the ever-treated indicator used to identify
treated firms whose pre-treatment productivity enters the D.4 comparison. If
omitted, the command prefers {cmd:_pte_treat} from the official setup workflow
and otherwise falls back to {cmd:treated}. When {opt treatvar()} is supplied,
the variable name must match exactly; shadow abbreviations are rejected.

{phang}
{opt midvar(varname)} specifies the transition indicator excluded from the D.3
stability regressions. If omitted, the command prefers {cmd:_pte_mid} and
otherwise falls back to {cmd:mid}. When {opt midvar()} is supplied, the name
must match exactly.

{phang}
{opt cohortvar(varname)} specifies the firm-level first treatment period
{it:e_i}. This is the preferred timing source for staggered adoption and is
used to locate each treated firm's pre-treatment observation at {cmd:e_i - 1}.
If omitted, the command first looks for {cmd:_pte_treat_year} and then for
{cmd:treat_year}. When {opt cohortvar()} is supplied, the name must match
exactly.

{phang}
{opt statusvar(varname)} specifies the time-varying treatment status
({it:D_it}) used to derive {opt cohortvar()} only when no treatment-year
variable exists. If neither {opt cohortvar()} nor {opt statusvar()} is
supplied, the command falls back to existing exact {cmd:_pte_D} or {cmd:D}
variables. When {opt statusvar()} is supplied, the name must match exactly.

{phang}
{opt alpha(#)} specifies the significance level for pass/fail determination.
Default is 0.05.

{phang}
{opt overlap_threshold(#)} specifies the minimum acceptable overlap ratio.
Default is 0.8 (80%).

{phang}
{opt noreport} suppresses the diagnostic output table and method
recommendation. Results are still stored in {cmd:r()}.


{marker remarks}{...}
{title:Remarks}

{pstd}
{bf:D.3 Test Details}

{pstd}
The D.3 test splits the sample period at the midpoint and tests whether the
evolution function parameters differ between early and late periods. The
midpoint is computed as round((t0 + t0 + s) / 2). A late-period indicator
is interacted with all polynomial terms of lagged omega, and a likelihood
ratio test compares the restricted (no interactions) and unrestricted
(with interactions) models. Transition period observations (mid != 0) are
excluded from both regressions.

{pstd}
{bf:D.4 Test Details}

{pstd}
The D.4 test compares the omega distribution of the target group at t0+s-1
with the pre-treatment omega distribution of treated firms. Following the
EPIC-012 specification, each treated firm's pre-treatment period is defined
as {it:e_i - 1} via {opt cohortvar()} (supporting staggered adoption), rather
than a fixed t0-1. When {opt cohortvar()} is absent, the command derives
{it:e_i} from {opt statusvar()} or legacy {_pte_D}/{cmd:D} variables.

{pstd}
{bf:Method Recommendation Decision Tree}

{p 4 8 2}
Based on test results, the command provides method recommendations:{p_end}

{p 8 12 2}
D.3 pass, D.4 pass, Overlap OK: Use Proposition D.4 (matching method){p_end}
{p 8 12 2}
D.3 pass, D.4 fail or low overlap: Use Proposition D.3 (divergent
evolution){p_end}
{p 8 12 2}
D.3 fail, D.4 pass: Warning - robustness checks recommended{p_end}
{p 8 12 2}
Both fail: Warning - estimates may be unreliable{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_cf_assumption_tests} stores the following in {cmd:r()}:

{synoptset 32 tabbed}{...}
{p2col 5 32 36 2: Scalars}{p_end}
{synopt:{cmd:r(assumption_d3_stat)}}D.3 LR test chi-squared statistic{p_end}
{synopt:{cmd:r(assumption_d3_pval)}}D.3 LR test p-value{p_end}
{synopt:{cmd:r(assumption_d3_df)}}D.3 LR test degrees of freedom (= omegapoly +
1){p_end}
{synopt:{cmd:r(assumption_d4_stat)}}D.4 Kolmogorov-Smirnov D statistic{p_end}
{synopt:{cmd:r(assumption_d4_pval)}}D.4 Kolmogorov-Smirnov p-value{p_end}
{synopt:{cmd:r(overlap_ratio)}}fraction of target group within treated
support{p_end}
{synopt:{cmd:r(n_target)}}number of target group observations at t0+s-1{p_end}
{synopt:{cmd:r(n_treated_pre)}}number of treated pre-treatment
observations{p_end}
{synopt:{cmd:r(omega_support_min)}}minimum omega in treated pre-treatment
sample{p_end}
{synopt:{cmd:r(omega_support_max)}}maximum omega in treated pre-treatment
sample{p_end}
{synopt:{cmd:r(d3_pass)}}D.3 pass indicator (1 if p >= alpha, missing if test
failed){p_end}
{synopt:{cmd:r(d4_pass)}}D.4 pass indicator (1 if p >= alpha){p_end}
{synopt:{cmd:r(overlap_ok)}}overlap OK indicator (1 if ratio >=
threshold){p_end}

{pstd}
Note: D.3 results may be missing ({cmd:.}) if the likelihood ratio test
fails to converge. In this case, {cmd:r(d3_pass)} is also missing, and the
decision tree treats D.3 as passed (conservative approach).


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z. & Schurter, K. (2026). Productivity treatment effects
estimation with unobserved heterogeneity. {it:Working Paper}.
Appendix D: Counterfactual Treatment Effects.{p_end}

{phang}
Assumption D.3: Time stability of the productivity evolution function.
See Appendix D.3.1.{p_end}

{phang}
Assumption D.4: Distributional comparability between target and treated
groups. See Appendix D.3.3.{p_end}


{marker authors}{...}
{title:Authors}

{pstd}
pte package development team.{p_end}

{hline}
