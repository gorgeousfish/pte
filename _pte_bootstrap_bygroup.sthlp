{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] _pte_bygroup_boot_single" "help _pte_bygroup_boot_single"}{...}
{vieweralsosee "[PTE] _pte_bygroup_aggregate" "help _pte_bygroup_aggregate"}{...}
{vieweralsosee "[PTE] _pte_omega" "help _pte_omega"}{...}
{vieweralsosee "[PTE] _pte_att" "help _pte_att"}{...}
{viewerjumpto "Syntax" "_pte_bootstrap_bygroup##syntax"}{...}
{viewerjumpto "Description" "_pte_bootstrap_bygroup##description"}{...}
{viewerjumpto "Options" "_pte_bootstrap_bygroup##options"}{...}
{viewerjumpto "Stored results" "_pte_bootstrap_bygroup##results"}{...}
{viewerjumpto "References" "_pte_bootstrap_bygroup##references"}{...}
{title:Title}

{p2colset 5 32 34 2}{...}
{p2col:{cmd:_pte_bootstrap_bygroup} {hline 2}}Bygroup bootstrap inference for ATT estimation{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_bootstrap_bygroup} {depvar}{cmd:,}
{opt by(varname)}
{opt treatment(varname)}
{opt free(varname)}
{opt state(varname)}
{opt proxy(varname)}
[{it:options}]

{synoptset 28 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt by(varname)}}grouping variable (e.g., industry){p_end}
{synopt:{opt treatment(varname)}}binary treatment indicator{p_end}
{synopt:{opt free(varname)}}free (flexible) input variable{p_end}
{synopt:{opt state(varname)}}state variable (e.g., capital){p_end}
{synopt:{opt proxy(varname)}}proxy variable (e.g., materials){p_end}

{syntab:Production function}
{synopt:{opt pfunc(string)}}production function type: {cmd:cd} or {cmd:translog}; default is {cmd:translog}{p_end}
{synopt:{opt poly(#)}}legacy alias for {cmd:omegapoly(#)}; default is {cmd:3}{p_end}
{synopt:{opt omegapoly(#)}}evolution polynomial order (1-4); default is {cmd:3}{p_end}
{synopt:{opt control(varlist)}}control variables (e.g., time trends){p_end}
{synopt:{opt notrimeps}}disable Winsorize trimming of eps0 residuals{p_end}

{syntab:ATT estimation}
{synopt:{opt attperiods(#)}}non-negative ATT horizon requested from the grouped bootstrap helper; default is {cmd:4}{p_end}
{synopt:{opt nsim(#)}}number of counterfactual simulation paths; default is auto ({cmd:1} if {cmd:omegapoly(1)}, else {cmd:100}){p_end}
{synopt:{opt eps0window(#)}}untreated innovation window passed to EPIC-002; default is {cmd:0} (full identified untreated pre-treatment support, scaled by the current {cmd:xtset} {cmd:delta()} declaration when windowed){p_end}

{syntab:Inference}
{synopt:{opt bootstrap(#)}}number of bootstrap replications (must be >= 2); default is {cmd:100}{p_end}
{synopt:{opt seed(#)}}group seed for bootstrap resampling; default is pfunc-based{p_end}
{synopt:{opt inner_seed(#)}}explicit inner seed override for ATT simulation; omitted {cmd:inner_seed()} preserves the live grouped RNG stream{p_end}
{synopt:{opt level(#)}}confidence level (10-99); default is {cmd:95}{p_end}
{synopt:{opt saving(filename)}}save pooled bootstrap draws in wide form ({cmd:att_raw}, {cmd:att_raw_#}, and trimmed counterparts when available){p_end}

{syntab:Replication}
{synopt:{opt replicate(mode)}}replication mode: {cmd:trlg} or {cmd:cd}{p_end}

{syntab:Parallel execution}
{synopt:{opt noparallel}}force serial execution (disable parallel detection){p_end}
{synopt:{opt processors(#)}}number of parallel processors (overrides auto-detection){p_end}

{syntab:Reporting}
{synopt:{opt nolog}}suppress progress display{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_bootstrap_bygroup} is an internal module that performs
industry-level (by-group) bootstrap inference for ATT estimation in the
{cmd:pte} package. It implements the following procedure:

{phang2}1. For each group {it:g} = 1, ..., G defined by {opt by()}, set the
group seed once and run B bootstrap iterations.{p_end}

{phang2}2. Each bootstrap iteration performs stratified cluster resampling,
then re-estimates the production function, productivity evolution, and ATT
within the group.{p_end}

{phang2}3. After all groups complete, per-group TT data are appended across
groups for each iteration to compute pooled ATT = mean(TT) by period.{p_end}

{pstd}
Grouped draws are treated as complete only when every group contributes the
required TT payload for the active track. Raw pooling requires
{cmd:_pte_nt}, {cmd:_pte_tt_raw}, and {cmd:_pte_tt}; trimmed runs also
require {cmd:_pte_tt_trim}. Incomplete sidecar files are counted as failed
draws rather than being averaged over the remaining groups.

{phang2}4. Bootstrap standard errors and percentile confidence intervals are
computed from the pooled ATT distribution.{p_end}

{pstd}
This module delegates single-iteration work to
{helpb _pte_bygroup_boot_single} and cross-group aggregation to
{helpb _pte_bygroup_aggregate}.

{pstd}
{bf:Single group:} If only one group is found in {opt by()}, the module
stays on the bygroup bootstrap path and runs serially, so the
industry-seed semantics remain unchanged.

{pstd}
{bf:Seed management:} The group seed is set once at the start of each
group's bootstrap loop (not per iteration). Default seeds are 20000 for
translog and 10000 for Cobb-Douglas, matching the replication code. The
inner ATT simulation keeps consuming that live grouped RNG stream when
{opt inner_seed()} is omitted; the worker does {bf:not} reset a per-draw
fixed seed on the grouped bootstrap path. Use {opt inner_seed()} only when
you intentionally want an explicit inner ATT reset override. The grouped
translog order-1 benchmark is the documented exception: when callers pair
{opt replicate(trlg)} with the official fixed ATT seed {cmd:10000}, the
helper records that override as benchmark replicate provenance rather than
a generic user seed.

{pstd}
{bf:Parallel execution:} When the {cmd:parallel} package is available and
{opt noparallel} is not specified, groups may be processed in parallel.
If parallel execution fails, the module falls back to serial processing.

{pstd}
{bf:Prerequisites:} Data must be {cmd:xtset} as a panel. EPIC-001 modules
({cmd:_pte_prodfunc}), EPIC-002 ({cmd:_pte_omega}), and EPIC-003
({cmd:_pte_att}) must be available.


{marker options}{...}
{title:Options}

{dlgtab:Required}

{phang}
{opt by(varname)} specifies the grouping variable (e.g., industry code).
Bootstrap is performed separately within each group, then results are
aggregated across groups.

{phang}
{opt treatment(varname)} specifies the binary treatment indicator (0/1).

{phang}
{opt free(varname)}, {opt state(varname)}, {opt proxy(varname)} specify
the production function input variables.

{dlgtab:Production function}

{phang}
{opt pfunc(string)} specifies the production function type. {cmd:cd} for
Cobb-Douglas, {cmd:translog} for translog. Default is {cmd:translog}.

{phang}
{opt poly(#)} is the legacy compatibility alias for
{opt omegapoly(#)}. This helper follows the package-wide order contract:
the first-stage proxy basis remains fixed at the benchmark cubic
specification, while {opt poly()} / {opt omegapoly()} select the
productivity-evolution order. Default is 3.

{phang}
{opt omegapoly(#)} specifies the polynomial order for the productivity
evolution process (1-4). Default is 3.

{phang}
{opt control(varlist)} specifies control variables to include in the
first-stage regression (e.g., time trends).

{phang}
{opt notrimeps} disables Winsorize trimming (1-99%) of the eps0
distribution. Not recommended per Section 6.3.3 of the paper.

{dlgtab:ATT estimation}

{phang}
{opt attperiods(#)} specifies the non-negative ATT horizon requested from
the grouped bootstrap helper. The helper itself enforces only the
non-negativity contract; any tighter public upper-bound check is handled
by the caller before entering this module. Default is 4.

{phang}
{opt nsim(#)} specifies the number of counterfactual simulation paths.
If omitted, the helper follows the main bootstrap contract:
{cmd:nsim(1)} for {cmd:omegapoly(1)} and {cmd:nsim(100)} otherwise.

{phang}
{opt eps0window(#)} specifies the untreated innovation window passed to
{cmd:_pte_omega} during each grouped bootstrap rerun. {cmd:eps0window(0)}
keeps the full identified untreated pre-treatment support; positive values
restrict the worker to the corresponding number of panel periods before the
relevant first-treatment anchor used by EPIC-002, scaled by the current
{cmd:xtset} {cmd:delta()} declaration.

{dlgtab:Inference}

{phang}
{opt bootstrap(#)} specifies the number of bootstrap replications B.
Must be at least 2. Default is 100.

{phang}
{opt seed(#)} specifies the group seed set once at the start of each
group's bootstrap loop. Default depends on production function type:
20000 for translog, 10000 for Cobb-Douglas. The {opt replicate()} option
can also set the default seed.

{phang}
{opt inner_seed(#)} specifies the inner seed for ATT simulation. Default
is -1, which means {cmd:_pte_bootstrap_bygroup} does not inject a
seed() override and the downstream ATT worker keeps consuming the live
grouped RNG stream. Callers that need a replication-specific inner seed
should pass it explicitly via {opt inner_seed()}. On the grouped translog
order-1 benchmark path, the official fixed ATT seed is {cmd:10000}; when
that benchmark override is active, the helper reports
{cmd:e(inner_seed_source)} = {cmd:replicate}.

{phang}
{opt level(#)} specifies the confidence level for percentile bootstrap
confidence intervals. Default is 95.

{dlgtab:Replication}

{phang}
{opt replicate(mode)} sets replication-compatible defaults. {cmd:trlg}
sets group seed to 20000; {cmd:cd} sets group seed to 10000. User-specified
{opt seed()} overrides the replicate default. On the grouped translog
order-1 benchmark path, callers may also pass the official fixed ATT
inner seed {cmd:10000} through {opt inner_seed()}; the helper then tags
that ATT-seed override as {cmd:replicate} provenance rather than
{cmd:user}.

{dlgtab:Parallel execution}

{phang}
{opt noparallel} forces serial execution, disabling automatic parallel
detection. Use this for debugging or when the {cmd:parallel} package
causes issues.

{phang}
{opt processors(#)} specifies the number of parallel processors. Overrides
auto-detection. Capped at the number of groups.

{dlgtab:Reporting}

{phang}
{opt nolog} suppresses all progress display including per-group iteration
dots and summary tables.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_bootstrap_bygroup} stores the following in {cmd:e()}:

{synoptset 30 tabbed}{...}
{p2col 5 30 34 2: Scalars}{p_end}
{synopt:{cmd:e(nboot)}}number of bootstrap replications{p_end}
{synopt:{cmd:e(ngroups)}}number of groups{p_end}
{synopt:{cmd:e(n_success)}}number of complete pooled bootstrap draws used for inference{p_end}
{synopt:{cmd:e(n_fail)}}number of incomplete pooled draws excluded from inference{p_end}
{synopt:{cmd:e(n_success_group)}}total complete group-level draws across all groups (ATT/TT/beta payload all present){p_end}
{synopt:{cmd:e(n_fail_group)}}total failed group-level draws across all groups{p_end}
{synopt:{cmd:e(industry_seed)}}group seed used{p_end}
{synopt:{cmd:e(inner_seed)}}ATT simulation seed override used by the helper; omitted when the grouped worker instead consumes the live grouped RNG stream{p_end}
{synopt:{cmd:e(seed_inner)}}alias of {cmd:e(inner_seed)} when an explicit grouped ATT simulation seed override is active{p_end}
{synopt:{cmd:e(level)}}confidence level{p_end}
{synopt:{cmd:e(omegapoly)}}evolution polynomial order{p_end}
{synopt:{cmd:e(attperiods)}}maximum ATT periods{p_end}
{synopt:{cmd:e(attperiods_max)}}compatibility alias for maximum ATT periods{p_end}
{synopt:{cmd:e(nsim)}}number of simulation paths{p_end}
{synopt:{cmd:e(eps0window)}}eps0 innovation window (panel periods, scaled by {cmd:xtset} {cmd:delta()}){p_end}
{synopt:{cmd:e(poly)}}resolved legacy alias value, equal to {cmd:e(omegapoly)}{p_end}
{synopt:{cmd:e(parallel_requested_nproc)}}parallel worker count requested after environment gating and user overrides{p_end}
{synopt:{cmd:e(parallel_nproc)}}parallel processors actually used in the final execution path{p_end}
{synopt:{cmd:e(parallel_fallback)}}indicator equal to 1 when a requested grouped parallel path fell back to serial, 0 otherwise{p_end}
{synopt:{cmd:e(parallel_helper_rc)}}helper return code when the grouped parallel helper aborted before returning payload; omitted otherwise{p_end}

{p2col 5 30 34 2: Macros}{p_end}
{synopt:{cmd:e(cmd)}}{cmd:_pte_bootstrap_bygroup}{p_end}
{synopt:{cmd:e(title)}}PTE Bygroup Bootstrap Inference{p_end}
{synopt:{cmd:e(by)}}grouping variable name{p_end}
{synopt:{cmd:e(groups)}}list of group values{p_end}
{synopt:{cmd:e(treatment)}}treatment variable name{p_end}
{synopt:{cmd:e(prodfunc)}}production function type{p_end}
{synopt:{cmd:e(depvar)}}dependent variable name{p_end}
{synopt:{cmd:e(free)}}free input variable{p_end}
{synopt:{cmd:e(state)}}state variable{p_end}
{synopt:{cmd:e(proxy)}}proxy variable{p_end}
{synopt:{cmd:e(control)}}control variables (if specified){p_end}
{synopt:{cmd:e(replicate)}}replicate mode (if specified){p_end}
{synopt:{cmd:e(inner_seed_source)}}{cmd:replicate} on the grouped translog order-1 benchmark path when the official fixed ATT seed {cmd:10000} is active, {cmd:user} for other explicit {opt inner_seed()} overrides, {cmd:inherited} when the grouped worker consumed the live grouped RNG stream{p_end}
{synopt:{cmd:e(parallel_requested_method)}}parallel method requested after environment gating and user overrides{p_end}
{synopt:{cmd:e(parallel_method)}}parallel method actually used in the final execution path{p_end}
{synopt:{cmd:e(parallel_fallback_reason)}}fallback reason: empty if no fallback, otherwise one of {cmd:helper_rc}, {cmd:helper_empty}, or {cmd:payload_mismatch}; the last case also covers helper returns whose TT sidecars cannot support a complete pooled draw set and therefore trigger a serial rerun{p_end}

{p2col 5 30 34 2: Matrices - Pooled results}{p_end}
{synopt:{cmd:e(att_boot_all)}}B x (1+T) pooled ATT bootstrap distribution (raw){p_end}
{synopt:{cmd:e(att_boot_trim)}}B x (1+T) pooled ATT bootstrap distribution (trimmed){p_end}
{synopt:{cmd:e(att_se_pool)}}1 x (1+T) pooled bootstrap standard errors (raw){p_end}
{synopt:{cmd:e(att_se_pool_trim)}}1 x (1+T) pooled bootstrap standard errors (trimmed){p_end}
{synopt:{cmd:e(att_ci_lower_pool)}}1 x (1+T) lower CI bounds (raw){p_end}
{synopt:{cmd:e(att_ci_upper_pool)}}1 x (1+T) upper CI bounds (raw){p_end}
{synopt:{cmd:e(att_ci_lower_trim)}}1 x (1+T) lower CI bounds (trimmed){p_end}
{synopt:{cmd:e(att_ci_upper_trim)}}1 x (1+T) upper CI bounds (trimmed){p_end}
{synopt:{cmd:e(att_mean_pool)}}1 x (1+T) pooled ATT means (raw){p_end}
{synopt:{cmd:e(att_mean_pool_trim)}}1 x (1+T) pooled ATT means (trimmed){p_end}

{p2col 5 30 34 2: Matrices - Per-group results (g = 1, ..., G)}{p_end}
{synopt:{cmd:e(att_boot_g}{it:g}{cmd:)}}B x (1+T) per-group ATT bootstrap distribution; failed or incomplete grouped draws remain missing{p_end}
{synopt:{cmd:e(att_trim_boot_g}{it:g}{cmd:)}}B x (1+T) per-group trimmed ATT distribution; failed or incomplete grouped draws remain missing{p_end}
{synopt:{cmd:e(att_se_g}{it:g}{cmd:)}}1 x (1+T) per-group bootstrap SE computed from complete group-level draws only{p_end}
{synopt:{cmd:e(beta_boot_g}{it:g}{cmd:)}}B x k per-group beta bootstrap distribution; failed or incomplete draws remain missing{p_end}
{synopt:{cmd:e(beta_se_g}{it:g}{cmd:)}}1 x k per-group beta bootstrap SE computed from complete group-level draws only{p_end}

{pstd}
Trimmed-track matrices are only stored when {opt notrimeps} is not specified.


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z., & Schurter, K. (2026). Productivity Treatment Effects.
{it:Working Paper}. Section 6, Bootstrap inference.

{phang}
Replication code: {cmd:DOs/att_estimation_industry_trlg_nonlinear.do},
{cmd:DOs/att_estimation_industry_cd_nonlinear.do}


{marker author}{...}
{title:Author}

{pstd}
PTE Package Development Team
{p_end}
{pstd}
All by-group bootstrap ATT matrices follow the official industry DO order:
columns 1..(T+1) correspond to {cmd:ATT0}, {cmd:ATT1}, ..., {cmd:ATT}{it:T},
and the final column stores the overall pooled ATT.
