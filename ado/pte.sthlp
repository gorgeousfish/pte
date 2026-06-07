{smcl}
{* *! version 1.0.0  17mar2026}{...}
{vieweralsosee "xtset" "help xtset"}{...}
{vieweralsosee "bootstrap" "help bootstrap"}{...}
{vieweralsosee "pte_setup" "help pte_setup"}{...}
{vieweralsosee "pte_diagnose" "help pte_diagnose"}{...}
{vieweralsosee "pte_graph" "help pte_graph"}{...}
{vieweralsosee "pte_p" "help pte_p"}{...}
{viewerjumpto "Syntax" "pte##syntax"}{...}
{viewerjumpto "Description" "pte##description"}{...}
{viewerjumpto "Options" "pte##options"}{...}
{viewerjumpto "Remarks" "pte##remarks"}{...}
{viewerjumpto "Seed management" "pte##seed"}{...}
{viewerjumpto "Replication modes" "pte##replicate"}{...}
{viewerjumpto "Stored results" "pte##results"}{...}
{viewerjumpto "Examples" "pte##examples"}{...}
{viewerjumpto "References" "pte##references"}{...}
{viewerjumpto "Authors" "pte##authors"}{...}

{cmd:help pte}{right:also see: {help pte_setup} {help pte_diagnose} {help pte_graph}}
{hline}

{title:Title}

{p2colset 5 14 21 2}{...}
{p2col:{hi:pte} {hline 1} Productivity Treatment Effects (CLK/ACF)}{p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:pte} {it:depvar}
{cmd:,}
{cmdab:free(}{it:varname}{cmd:)}
{cmdab:state(}{it:varname}{cmd:)}
{cmdab:proxy(}{it:varname}{cmd:)}
{cmdab:treat:ment(}{it:varname}{cmd:)}
[{it:options}]

{p 8 17 2}
{cmd:pte}
[{cmd:,} {opt level(#)} {opt nolog}]

{pstd}
The data must either be {cmd:xtset} before calling {cmd:pte}, or carry a
complete stored setup contract written by {helpb pte_setup}. When the caller
returns to a no-{cmd:xtset} ambient state after {cmd:pte_setup}, {cmd:pte}
materializes the stored panel/time/{cmd:delta()} contract at entry. If the
stored setup treatment law no longer matches the current data, {cmd:pte}
fails closed and asks you to rerun {cmd:pte_setup}.

{pstd}
That setup-backed entry path is atomic. If only part of the stored
{cmd:pte_setup} bundle remains, if the stored panel/time variables no longer
exist in the current dataset, or if {opt treatment()} names a different
treatment variable than the one audited by the stored setup contract,
{cmd:pte} stops with a fail-closed setup-contract error instead of guessing a
replacement law from the ambient session state.

{pstd}
Use exact variable names for {it:depvar}, {opt treatment()}, {opt free()},
{opt state()}, {opt proxy()}, and every variable listed in {opt control()}.
When using grouped estimation, {opt by()} and {opt industry()} must also name
the exact existing grouping variable. The public command rejects abbreviation
fallback for these inputs so the estimation state cannot silently bind to
shadow columns.

{pstd}
After estimation, a bare {cmd:pte} replays the last {cmd:pte} results from
{cmd:e()}. Replay accepts display-only options such as {opt level()} and
{opt nolog}. On replay, {opt nolog} is accepted for syntax compatibility but
does not suppress the final results summary because replay has no progress log.
On benchmark-by results, replay also requires the grouped routing metadata
{cmd:e(by)} together with the grouped replay payload family; if grouped ATT or
grouped stage-1/2 matrices remain active after {cmd:e(by)} has drifted away,
bare replay fails closed
instead of silently collapsing the output onto the pooled ATT display path.
When replayed bootstrap ATT results already store confidence intervals at a
different estimation-time level, {opt level()} recalculates the displayed ATT
intervals from the stored standard errors rather than reusing the old bounds.

{marker options}{...}
{title:Options}

{synoptset 28 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt treat:ment(varname)}}binary treatment indicator {it:D_it}; the variable name must be exact{p_end}
{synopt:{opt free(varname)}}free (flexible) input, e.g. labor; the current public estimator supports one free variable, and the variable name must be exact{p_end}
{synopt:{opt state(varname)}}state input, e.g. capital; the current public estimator supports one state variable, and the variable name must be exact{p_end}
{synopt:{opt proxy(varname)}}proxy input, e.g. materials/investment; the current public estimator supports one proxy variable, and the variable name must be exact{p_end}

{syntab:Production function}
{synopt:{opt pfunc(string)}}{cmd:cd} or {cmd:translog}; default is {cmd:translog}{p_end}
{synopt:{opt translog}}alias for {cmd:pfunc(translog)}{p_end}
{synopt:{opt control(varlist)}}controls partialled out from the first-stage regression and removed from the stored first-stage productivity proxy before omega recovery (e.g., time trends); each control variable must be named exactly; not available with {cmd:treatdependent}, which uses its internal time-trend control only{p_end}
{synopt:{opt omegapoly(#)}}order of the productivity evolution polynomial; default is {cmd:3}; allowed: 1..4{p_end}
{synopt:{opt poly(#)}}alias for {cmd:omegapoly(#)}; if both are specified, they must agree{p_end}

{syntab:ATT estimation}
{synopt:{opt attp:eriods(#)}}maximum event time; estimates the window {cmd:0..#}; default is {cmd:4}{p_end}
{synopt:{opt nsim(#)}}number of Monte Carlo paths; default is auto (100 if {cmd:omegapoly>=2}, else 1){p_end}
{synopt:{opt eps0window(#)}}nonnegative window (panel periods, scaled by {cmd:xtset} {cmd:delta()}) for constructing the untreated pre-treatment {cmd:eps0} sample; default is {cmd:0}; {cmd:0} uses all available untreated pre-treatment support{p_end}
{synopt:{opt notrimeps}}disable 1%/99% Winsorization of {cmd:eps0}{p_end}
{synopt:{opt noatt}}skip ATT estimation (production-function and omega only); incompatible with {cmd:bootstrap()>0}/{cmd:reps()>0} and {cmd:attnorm}; also allowed on the grouped {cmd:by()/industry()} path, where the command reposts grouped stage-1/2 objects only{p_end}

{syntab:Inference}
{synopt:{opt bootstrap(#)}}number of bootstrap replications; default {cmd:0}; must be {cmd:0} or {cmd:>=2}{p_end}
{synopt:{opt reps(#)}}alias for {cmd:bootstrap(#)}; any explicit mixed pair must agree exactly, so {cmd:reps(0)} conflicts with nonzero {cmd:bootstrap(#)} and explicit {cmd:bootstrap(0)} conflicts with nonzero {cmd:reps(#)}{p_end}
{synopt:{opt saving(filename)}}save bootstrap draws; requires {cmd:bootstrap()>=2}; the alias gate is identical, so {cmd:reps()>=2} is also required when {cmd:bootstrap()} is omitted{p_end}
{synopt:{opt level(#)}}confidence level for bootstrap intervals; default is Stata's {cmd:c(level)}{p_end}
{synopt:{opt noparallel}}on grouped bootstrap only, force the helper to stay on the serial path; requires {cmd:bootstrap()>=2}, equivalently {cmd:reps()>=2} when {cmd:bootstrap()} is omitted{p_end}
{synopt:{opt processors(#)}}on grouped bootstrap only, request a positive parallel worker count for the helper; requires {cmd:bootstrap()>=2}, equivalently {cmd:reps()>=2} when {cmd:bootstrap()} is omitted{p_end}

{syntab:Grouping (benchmark-by)}
{synopt:{opt by(varname)}}run the benchmark-by path (group-specific estimation); requires the exact grouping variable name, currently requires a single {cmd:proxy()} variable and at most one {cmd:control()} variable, and supports either the baseline ATT workflow or grouped {cmd:noatt}{p_end}
{synopt:{opt industry(varname)}}alias for {cmd:by()} used by paper scripts; also requires the exact grouping variable name. If both {cmd:by()} and {cmd:industry()} are supplied, they must spell the same exact grouping variable name{p_end}
{synopt:{opt byindustry}}mark {cmd:by()/industry()} as an industry split in the returned metadata; requires {cmd:by()} or {cmd:industry()}{p_end}

{syntab:Replication and reporting}
{synopt:{opt rep:licate(mode)}}benchmark configuration preset; see {help pte##replicate:Replication modes}{p_end}
{synopt:{opt seed(#)}}positive integer seed when specified; the option name must be spelled exactly as {cmd:seed()} (unsupported abbreviations such as {cmd:see()} are rejected at entry), requires an ATT/bootstrap RNG stage, and is therefore incompatible with {cmd:noatt}. Bootstrap uses it as the outer seed start, while omitted {cmd:seed()} on the serial bootstrap path starts at {cmd:1}. Serial point ATT simulation uses {cmd:123456} by default, keeps {cmd:123456} for {cmd:replicate(order3)} under {cmd:pfunc(cd)}, and uses {cmd:10000} for the translog benchmark modes {cmd:order3}, {cmd:table1}, {cmd:table5}, and {cmd:table_e4}; see {help pte##seed:Seed management}{p_end}
{synopt:{opt nodiag:nose}}skip diagnostics that are not required for estimation{p_end}
{synopt:{opt nolog}}suppress progress output during estimation; replay still shows the final results summary{p_end}
{synopt:{opt verbose}}show verbose parameter-conflict detail and Mata initialization output{p_end}

{syntab:Extension flags (validated; not all workflows are public)}
{synopt:{opt treatdep:endent}}enable treatment-dependent production-function path{p_end}
{synopt:{opt normalize(string)}}normalization method for {cmd:treatdependent}; any explicit {cmd:normalize()} requires {cmd:treatdependent}: {cmd:indexing}, {cmd:benchmark}, or {cmd:none}; the grouped {cmd:by()/industry()} path rejects it at entry{p_end}
{synopt:{opt attnorm}}on {cmd:treatdependent+normalize(indexing)}: also compute normalized ATT objects over the full requested {cmd:attperiods()} horizon and repost them as {cmd:e(att_norm_computed)} plus {cmd:e(att_norm_#)}; incompatible with {cmd:noatt}; the grouped {cmd:by()/industry()} path rejects it at entry{p_end}
{synopt:{opt nonabs:orbing}}request non-absorbing treatment analysis; currently degrades to baseline or errors (see Remarks){p_end}
{synopt:{opt persistp:eriods(#)}}nonnegative minimum consecutive treated periods for the nonabsorbing path; positive values require {cmd:nonabsorbing}{p_end}
{synopt:{opt switchdir:ection(string)}}nonabsorbing switch direction: {cmd:on}, {cmd:off}, or {cmd:both}; requires {cmd:nonabsorbing}{p_end}
{synopt:{opt counterfactual}}reserved flag for internal counterfactual pipelines; the public {cmd:pte} command rejects it and requires a dedicated counterfactual worker instead; the grouped {cmd:by()/industry()} path rejects it at the grouped unsupported-option gate{p_end}
{synopt:{opt targetgr:oup(name)}}reserved target-group option name for internal counterfactual workers; on the public {cmd:pte} path this option name is reserved, the command rejects the counterfactual branch at entry, and only reports bare {cmd:targetgroup()} misuse; the grouped {cmd:by()/industry()} path rejects it at the grouped unsupported-option gate{p_end}
{synopt:{opt cohort(varname numeric)}}reserved numeric design-check variable name (for example, treatment year); on the current public baseline/{cmd:noatt} path {cmd:pte} accepts the syntax, enforces only the public variable-name / numeric-input contract, and does not dispatch a cohort-analysis worker, invoke the internal multi-cohort validator, or post cohort-specific {cmd:e()} results; on the grouped {cmd:by()/industry()} path, {cmd:pte} still enforces the exact {cmd:cohort()} variable name first, so explicit abbreviations fail with the cohort exact-name error before the grouped unsupported-option gate rejects the grouped cohort branch; nonexistent or malformed {cmd:cohort()} names are still rejected earlier by Stata's syntax-level variable validation{p_end}
{synopt:{opt lagp:eriods(#)}}nonnegative extended-moment horizon; {cmd:lagperiods(0)} is the only accepted public value because {cmd:lagperiods()>0} is not implemented in the current {cmd:pte} main-command path; the grouped {cmd:by()/industry()} path rejects {cmd:lagperiods()>0} at the grouped unsupported-option gate{p_end}
{synoptline}

{marker description}{...}
{title:Description}

{pstd}
{cmd:pte} implements the baseline Productivity Treatment Effects (PTE)
estimator of Chen, Liao, and Schurter (2026). The workflow combines
ACF-style production function estimation with the CLK correction for
treatment transitions, recovers firm productivity, and estimates
{it:ATT} by Monte Carlo simulation of counterfactual productivity paths.

{pstd}
The baseline (absorbing-treatment) pipeline has four stages:

{phang}1. {bf:Production function estimation (Theorem 3.1).} A first-stage
regression produces {it:phi_it}; transition observations ({it:D_it != D_{i,t-1}})
are excluded from the CLK/ACF GMM step to estimate production-function
parameters.{p_end}

{phang}2. {bf:Productivity recovery and evolution.} Productivity is recovered
after the first-stage control adjustment, an untreated evolution law
{it:h_bar_0} and a treated evolution law are estimated on non-transition
observations, and untreated innovations {it:eps0_it} are summarized into
simulation scales. By default, {it:eps0} is Winsorized at the 1st and
99th percentiles before the canonical simulation scale is computed.{p_end}

{phang}3. {bf:ATT estimation (Proposition 4.3).} For treated firms, the
counterfactual path is simulated under the untreated evolution law
{it:h_bar_0}. In the current public estimator, the canonical ATT track
uses Gaussian draws with standard deviation {cmd:e(sigma_eps_trim)};
the raw track usually resamples the empirical {cmd:eps0} pool without
trimming, while the official translog benchmark exceptions that replace
that raw law with Gaussian draws are preserved explicitly in the
implementation.
The resulting treatment effect {it:TT_it} and event-time
ATT are computed. Proposition 4.1 / C.1 still identify the deterministic
conditional-mean onset benchmark {it:omega_ie_i - h_bar_0(omega_ie_i-1)},
but the main simulation worker follows the official DO-style untreated
path and consumes the treatment-onset innovation draw already at
{cmd:nt=0}. The deterministic benchmark is available separately through
{cmd:_pte_cohort_att_instant}; {cmd:e(att_0)} in the main estimator
belongs to the simulation path returned with the dynamic ATT sequence.{p_end}

{phang}4. {bf:Bootstrap inference.} If {cmd:bootstrap()>=2}, the full estimator
is rerun on stratified cluster bootstrap resamples to produce standard
errors and confidence intervals.{p_end}

{marker remarks}{...}
{title:Remarks}

{dlgtab:Transition observations (CLK correction)}

{pstd}
The CLK correction excludes observations where the treatment status
changes between {it:t-1} and {it:t} (i.e., {it:D_it != D_{i,t-1}}) from the
GMM moments. These transition observations are still kept in the dataset
for other steps, but they do not contribute to the moment conditions.
The first observed period for a firm, where the lagged treatment status is
missing, is treated as a non-transition observation ({it:mid = 0}).

{dlgtab:Stored setup contract at entry}

{pstd}
When {helpb pte_setup} has published a complete dataset-scoped panel/time/
treatment contract, {cmd:pte} uses that audited axis at entry even if the
caller is currently back in a no-{cmd:xtset} ambient state. The contract is
accepted only as a complete five-field bundle:
{cmd:_dta[_pte_setup_panelvar]}, {cmd:_dta[_pte_setup_timevar]},
{cmd:_dta[_pte_setup_treatment]}, {cmd:_dta[_pte_setup_treatsig]}, and
{cmd:_dta[_pte_setup_xtdelta]}. Partial fragments, missing stored panel/time
variables, a current-data treatment law that no longer matches the stored
{cmd:treatsig}, or a {opt treatment()} request that differs from the audited
setup treatment all fail closed before estimation starts.

{dlgtab:Postestimation contract after pte_setup}

{pstd}
After a successful run, {helpb pte_p:predict} reuses that audited
{cmd:pte_setup} contract. On the standard postestimation branches
({cmd:omega}, {cmd:phi}, {cmd:exponential}, {cmd:tt}, {cmd:att}, and
{cmd:parameters}), the live {cmd:pte} result must certify the same panel/time
axis through {cmd:e(idvar)} / {cmd:e(timevar)} (or the legacy aliases
{cmd:e(id)} / {cmd:e(time)}), the same treatment law through
{cmd:e(treatsig)}, and the same panel spacing through {cmd:e(xtdelta)}.
That treatment-side certification is law-first: once {cmd:e(treatsig)}
matches the stored setup contract, {cmd:e(treatment)} may be absent, but if it
is present and names a different treatment variable the postestimation path
still fails closed. The legacy {cmd:predict, residuals} fallback remains
slightly narrower: it may rebuild lagged omega from the setup-stored
{cmd:_dta[_pte_setup_xtdelta]} when an older live result does not yet publish
{cmd:e(xtdelta)}. See {helpb pte_p} for the full branch-by-branch contract.

{dlgtab:control() and the first-stage proxy}

{pstd}
If {opt control()} is specified, those controls are partialled out from the
first-stage regression and then removed from the stored productivity proxy
before omega is recovered. The package does {bf:not} subtract free, state,
or proxy inputs at this control-adjustment step.

{dlgtab:Trimming eps0 (Winsorization)}

{pstd}
By default, the estimator trims the innovation sample {it:eps0} at the 1st
and 99th percentiles before constructing the canonical Gaussian simulation
scale. Use {opt notrimeps}
to disable trimming. The public command no longer requires the
{cmd:winsor2} SSC package at entry because the live trim worker uses a
built-in deterministic 1%/99% trimming path; {cmd:winsor2} remains optional
only for running the official DO replication scripts directly.

{dlgtab:eps0window()}

{pstd}
By default, {cmd:pte} uses {cmd:eps0window(0)} and keeps the full untreated
pre-treatment support when estimating the innovation distribution for
Proposition 4.3 / ATT simulation in the current package implementation.
For the paper's empirical application, however, Section 6.3.3 (together with
the comparison-group discussion in Section 6.3.1) describes a three-year
pre-adoption innovation window, and Appendix E.3 reports diagnostics for
that same window. On the paper's annual {cmd:delta(1)} data, that is the same
as a three-period window. Use {cmd:eps0window(3)} when you want to mirror that
paper-specific specification.

{pstd}
When {opt eps0window()} is positive, the untreated {it:eps0} sample is
restricted to the common window, measured in panel periods, ending just before
the observed
 treatment-entry year among active treated cohorts in the current estimation
sample. The live-sample filter determines which treated cohorts are eligible to
anchor the window, but the anchor itself remains each cohort's observed
treatment-entry year from the full observed panel path. This excludes
left-censored treated firms, which have no identifiable observed entry year and
therefore cannot anchor the window. A cohort can still anchor the window even
if its own untreated support is exhausted; untreated-support admissibility is
applied separately when the package rebuilds the identified eps0 support. This
window is therefore tied to the
current estimation boundary, not separately at each treated firm's own entry
date. With annual data this coincides with calendar years; with
{cmd:xtset ..., delta(2)} it means two-year steps, and so on.

{dlgtab:Benchmark-by estimation (by()/industry())}

{pstd}
When {opt by()} (or {opt industry()}) is specified, {cmd:pte} routes the run
through group-specific workers so the production function, shock pool, and
ATT are computed within each group. With {opt noatt}, the grouped public path
stops after the production-function and evolution stages and reposts grouped
objects such as {cmd:e(b_by)}, {cmd:e(rho_by)}, {cmd:e(sigma_by)},
{cmd:e(N_by)}, and {cmd:e(N_firms_by)} without fabricating ATT output. In the
current public release, this benchmark-by path rejects grouped extension flags
beyond that grouped baseline / grouped-noatt contract, including
{cmd:treatdependent}, {cmd:normalize()}, {cmd:attnorm},
{cmd:nonabsorbing}, {cmd:counterfactual}, {cmd:targetgroup()},
{cmd:lagperiods()>0}, {cmd:persistperiods()>0},
{cmd:switchdirection()}, and {cmd:cohort()}.
It also currently
requires exactly one {cmd:proxy()} variable and at most one
{cmd:control()} variable, matching the grouped public {cmd:beta_t}
contract. When {cmd:bootstrap()>=2},
{opt saving()} saves the pooled by-group bootstrap draws in the same wide ATT
format used by the serial bootstrap path. Those grouped bootstrap public
reposts also keep the group-specific evolution metadata needed by replay:
{cmd:e(rho_by)}, {cmd:e(sigma_by)}, {cmd:e(N_by)}, and
{cmd:e(N_firms_by)}. On the grouped bootstrap postestimation path,
{cmd:predict, residuals} rebuilds untreated shocks from {cmd:e(rho_by)}
together with the grouped routing metadata {cmd:e(by)} and {cmd:e(groups)}.
Group-specific ATT mapping after grouped bootstrap remains available through
{cmd:e(att_by_point)} together with the same grouped routing metadata.

{marker seed}{...}
{title:Seed management}

{pstd}
Seed behavior depends on whether bootstrap inference is requested:

{pstd}
When {opt seed()} is specified, it must be a positive integer, and the option
name must be spelled exactly as {cmd:seed()} (unsupported abbreviations such as
{cmd:see()} are rejected by the public parser). The run must also execute an
ATT/bootstrap RNG stage, so {opt seed()} is incompatible with {opt noatt}. Omit {opt seed()}
to request the documented default behavior; negative sentinel values are not
part of the public interface.

{phang}1. If {cmd:bootstrap()=0} (default), the serial point-estimate ATT
path fixes the Monte Carlo inner simulation seed at {cmd:123456} on the
standard main-command path. {cmd:replicate(order3)} keeps that
{cmd:123456} default under {cmd:pfunc(cd)} to match the official
Cobb-Douglas order-3 DO, while the translog benchmark replicate modes
{cmd:order3}, {cmd:table1}, {cmd:table5}, and {cmd:table_e4} use
{cmd:10000} to match the official translog replication DO files.{p_end}

{phang}2. If {cmd:bootstrap()>=2}, the standard serial bootstrap path uses
{opt seed()} as the starting outer seed and advances by one each replication.
If {opt seed()} is omitted on that serial bootstrap path, the outer seed
starts at {cmd:1}, matching the official DO loop {cmd:set seed b}. The inner
ATT simulation seed is fixed at {cmd:123456} for every bootstrap draw.
Benchmark-by bootstrap ({cmd:by()}/{cmd:industry()}) follows
the official industry bootstrap DOs instead: the grouped bootstrap seed is
{cmd:10000} under {cmd:pfunc(cd)} and {cmd:20000} under
{cmd:pfunc(translog)}, and after that one-shot grouped seed is set the ATT
simulation draws consume the live grouped RNG stream with no per-draw inner
seed reset on the standard grouped path. The grouped benchmark exception is
{cmd:replicate(order1)} under {cmd:pfunc(translog)}, where {cmd:pte}
explicitly passes {cmd:inner_seed(10000)} to mirror the official translog
bootstrap DO. Because that grouped path does not advance an outer
{cmd:seed()+b-1} sequence, any positive Stata-valid {opt seed()} is admissible
there; the serial outer-seed upper-bound rule applies only to the non-grouped
bootstrap path.{p_end}

{pstd}
When {opt seed()} is omitted on the benchmark-by path, {cmd:pte} mirrors the
industry DO defaults instead of the serial wrapper default: the by-group point
estimation / bootstrap handoff uses {cmd:10000}, and the grouped bootstrap seed
uses {cmd:10000} under {cmd:pfunc(cd)} and {cmd:20000} under
{cmd:pfunc(translog)}. In the public {cmd:e()} results, grouped bootstrap also
stores that realized group-level seed in {cmd:e(industry_seed)}, while the
serial bootstrap path records its outer-seed advancement rule in
{cmd:e(seed_outer_strategy)}.
On the standard grouped path, {cmd:e(inner_seed)} is omitted because no fixed
per-draw ATT seed exists after the grouped seed is set; it appears only when
an explicit grouped {opt inner_seed()} override is active.

{pstd}
When grouped bootstrap runs ({cmd:by()}/{cmd:industry()} with
{cmd:bootstrap()>=2}), {opt noparallel} and {opt processors(#)} forward the
execution-control request to {helpb _pte_bootstrap_bygroup}. Use
{opt noparallel} when you need a forced serial benchmark, or
{opt processors(#)} to request a specific grouped helper worker count.
Outside the grouped bootstrap path, those options are rejected at entry.

{pstd}
On grouped bootstrap runs ({cmd:by()}/{cmd:industry()} with
{cmd:bootstrap()>=2}), {opt noparallel} and {opt processors(#)} forward the
execution-control request to {helpb _pte_bootstrap_bygroup}. Use
{opt noparallel} when you need a forced serial benchmark, or
{opt processors(#)} to request a specific grouped helper worker count.
Outside the grouped bootstrap path, those options are rejected at entry.

{pstd}
If {opt replicate()} is used and {opt seed()} is omitted, {cmd:pte} replaces
the package default with the benchmark seed implied by the chosen mode.
On the benchmark-by path ({cmd:by()}/{cmd:industry()}), omitting
{opt seed()} continues to use the official industry DO defaults described
above even when {opt replicate()} is specified. On the benchmark-by
point-estimate ATT path, the official DO contract stays fixed at
{cmd:10000} even when {opt seed()} is specified; {opt seed()} only affects
the grouped bootstrap seed metadata and grouped bootstrap worker seed.
The pooled paper ATT table modes {cmd:table1} and {cmd:table5} are the
documented exception: they cannot be combined with {opt by()} or
{opt industry()} because the grouped path follows the separate industry
benchmark chain rather than the pooled paper-table chain.

{marker replicate}{...}
{title:Replication modes}

{pstd}
{cmd:replicate()} pins a benchmark configuration (polynomial order, {cmd:nsim},
default seed, trimming mode, and, for the paper table modes, the
paper-specific {cmd:eps0window(3)} setting) intended for paper replication
scripts. The currently
supported modes are:
{cmd:order1}, {cmd:order2}, {cmd:order3}, {cmd:order4}, {cmd:table1},
{cmd:table5}, {cmd:table_e4}, {cmd:pool_trlg}, and
{cmd:pooled_translog}.

{pstd}
All supported replicate modes force the trimmed-{cmd:eps0} path. An explicit
{opt notrimeps} request therefore conflicts with {cmd:replicate()} and is
rejected at entry rather than silently rewritten. In addition, {cmd:table1}, {cmd:table5}, and
{cmd:table_e4} are defined only for {cmd:pfunc(translog)} and are rejected
under {cmd:pfunc(cd)}. Those three table-style modes also pin
{cmd:eps0window(3)} to mirror the paper's three-year untreated innovation
window, so an explicit conflicting {opt eps0window()} setting is rejected at
entry. To match the paper's dynamic ATT table exactly, {cmd:replicate(table1)}
also pins {cmd:attperiods(3)}; a conflicting explicit {opt attperiods()}
request is rejected at entry. Legal disambiguating spellings such as {cmd:attp()} and {cmd:attpe()} count as explicit {cmd:attperiods()} requests for this gate, so they are rejected as well when they request a different horizon. {cmd:replicate(table5)} leaves the live
{opt attperiods()} contract unchanged
and therefore keeps the caller/default ATT horizon instead of pinning
{opt attperiods()}. Because {cmd:table1} and {cmd:table5} are ATT
benchmarks, they also require the public ATT path and are rejected with
{opt noatt}. They are also pooled ATT benchmarks and therefore cannot be
combined with {opt by()} or {opt industry()}. {cmd:table_e4} is the
production-function benchmark and therefore requires {opt noatt} on the
public path; the grouped production-function benchmark remains available
through {opt by()}/{opt industry()} together with {opt noatt}.
{cmd:replicate(pool_trlg)} and {cmd:replicate(pooled_translog)} reproduce the
historical pooled translog DO branch {cmd:att_estimation_pool_trlg.do}: they
pin {cmd:pfunc(translog)}, cubic productivity evolution, {cmd:nsim(100)},
{cmd:attperiods(3)}, the benchmark seed {cmd:10000}, the detected {cmd:t1-t6}
time-trend controls, and the DO's untreated innovation support
{cmd:year<=2010 & treatment==0}. This legacy support is for direct DO
comparison and is intentionally distinct from the paper-window
{cmd:eps0window(3)} modes; therefore explicit {opt eps0window()} conflicts
with {cmd:replicate(pool_trlg)}.
The generic {cmd:order3} mode is available under both
{cmd:pfunc(cd)} and {cmd:pfunc(translog)}; it keeps the official
Cobb-Douglas point-estimation default seed {cmd:123456} on the CD path and
switches to {cmd:10000} on the translog path. On the serial bootstrap path,
omitting {opt seed()} still uses the official outer-seed start {cmd:1}.

{pstd}
Because {cmd:replicate()} is a strict benchmark preset, conflicting explicit
{opt omegapoly()}, {opt poly()}, numeric {opt nsim()}, {opt eps0window()} (for the
table-style modes), {opt attperiods()} (for {cmd:table1}), and {opt notrimeps}
settings are rejected rather than silently rewritten. The automatic sentinel
{opt nsim(-1)} is the documented exception: it requests the benchmark mode's own
automatic simulation count instead of expressing a conflicting numeric
preference. {opt seed()} remains the documented exception only on paths that
actually consume the caller-specified seed: the serial bootstrap outer-seed
path and the benchmark-by ({cmd:by()}/{cmd:industry()}) bootstrap
path. On both the serial point-estimate ATT path and the benchmark-by
point-estimate ATT path, {cmd:pte} continues to use the fixed benchmark ATT
simulation seed recorded in {cmd:e(point_seed)}.

{dlgtab:Extension flags (current public behavior)}

{pstd}
The main {cmd:pte} command currently parses several extension flags for
forward compatibility and runs design checks, but not all extension
estimators are exposed as a complete public workflow in version {cmd:1.0.0}.
In particular:

{phang}1. {opt nonabsorbing} triggers boundary-condition checks and then
{bf:errors out} unless the realized treatment path is absorbing, in which
case {cmd:pte} degrades to the baseline absorbing-treatment pipeline.
That degraded public fallback now {bf:rejects} {opt persistperiods()>0},
because the absorbing route cannot honor the Appendix C.3
persistent-switch filter.{p_end}

{pstd}
{bf:Planned feature:} The full non-absorbing treatment workflow
(Appendix C.3 of Chen, Liao, and Schurter 2026) is planned for a future
release of {cmd:pte}. In version {cmd:1.0.0}, specifying {opt nonabsorbing}
will degrade to the standard absorbing treatment estimation framework when
the realized treatment path is absorbing, or error out otherwise. The
auxiliary options {opt persistperiods()} and {opt switchdirection()} are
parsed and validated but do not activate a dedicated non-absorbing estimator.
Full support for reversible treatments, persistence filters, and
direction-specific switch analysis will be available in a subsequent
version.{p_end}

{phang}2. {opt persistperiods()} must be a nonnegative integer. Positive values and all
{opt switchdirection()} settings are auxiliary filters for the
{opt nonabsorbing} path only. The baseline absorbing-treatment workflow
rejects them if {opt nonabsorbing} is not specified. The grouped
{opt by()/industry()} path rejects {opt persistperiods()>0} and any
{opt switchdirection()} request at the grouped unsupported-option gate.
If {opt nonabsorbing} is requested but the realized treatment path has no
exit events, the degraded public fallback also rejects {opt persistperiods()>0}
instead of silently routing it through the absorbing ATT workflow.{p_end}

{phang}3. {opt counterfactual} and {opt targetgroup()} are reserved for
internal Appendix D style pipelines. The baseline public {cmd:pte} workflow
rejects the {opt counterfactual} branch at entry before any deeper timing,
bootstrap, or target-group validation is reached. In those dedicated workers,
{opt targetgroup()} is a binary indicator variable rather than a free-form
name token. The grouped {opt by()/industry()} path rejects either option
at the grouped unsupported-option gate before the baseline
counterfactual/target-group validator can fire. Use the dedicated
counterfactual workers for ATE^count style summaries.{p_end}

{phang}4. {opt cohort()} remains a separate reserved design-check option in the
public main-command path; it is not part of the Appendix D counterfactual
gate described above, and the current public baseline estimator does not use
it to switch into a cohort-ATT estimation branch. On the grouped
{opt by()/industry()} path, {cmd:pte} still enforces the exact
{opt cohort()} variable name first, so explicit abbreviations fail with the
cohort exact-name error before the grouped unsupported-option gate rejects
the grouped cohort branch. Nonexistent or malformed {opt cohort()} names are
still rejected earlier by Stata's syntax-level variable validation. Exact
existing numeric {opt cohort()} variables then fail closed at that grouped
unsupported-option gate.{p_end}

{phang}5. {opt treatdependent} is supported in the public pipeline (it affects
production-function estimation and optional normalization output), but the
core ATT definition remains the absorbing-treatment ATT unless you run the
dedicated treat-dependent counterfactual tooling. On the public {cmd:pte}
path, {cmd:treatdependent} also rejects explicit {cmd:control()} and always
uses the internal time-trend control that matches the official DO workflow.{p_end}

{marker examples}{...}
{title:Examples}

{pstd}{bf:Baseline translog PTE with ATT}{p_end}
{phang2}{cmd:. xtset firm year}{p_end}
{phang2}{cmd:. pte lny, treatment(D) free(lnl) state(lnk) proxy(lnm)}{p_end}

{pstd}{bf:Cobb-Douglas production function}{p_end}
{phang2}{cmd:. pte lny, treatment(D) free(lnl) state(lnk) proxy(lnm) pfunc(cd)}{p_end}

{pstd}{bf:Bootstrap inference}{p_end}
{phang2}{cmd:. pte lny, treatment(D) free(lnl) state(lnk) proxy(lnm) bootstrap(200)}{p_end}

{pstd}{bf:Disable eps0 trimming}{p_end}
{phang2}{cmd:. pte lny, treatment(D) free(lnl) state(lnk) proxy(lnm) notrimeps}{p_end}

{marker results}{...}
{title:Stored results}

{pstd}
{cmd:pte} is an {cmd:eclass} command. The returned bundle includes:

{phang}1. On the serial public path, production-function coefficients in {cmd:e(b)} and key scalars
{cmd:e(beta_l)}, {cmd:e(beta_k)}, optimizer diagnostics such as
{cmd:e(fval)}, {cmd:e(converged)}, and {cmd:e(iterations)}
(and translog interaction terms when used). When stage-1 controls are
estimated, {cmd:e(beta_controls)} stores the exact control-name row vector of
control coefficients; with a single {cmd:control()} variable, the legacy
scalar {cmd:e(beta_t)} is reposted as its first-column alias.{p_end}

{phang}2. On the serial public path, evolution-law parameters for the untreated law in
{cmd:e(rho0)}..{cmd:e(rho4)} and {cmd:e(rho_0)}. When treated-lag support is
available ({cmd:e(lag_treated_supported)}={cmd:1}), the treated-side bridge is
also posted in {cmd:e(rho_1)}, {cmd:e(gamma1)} (and, when implied by
{cmd:omegapoly()}, {cmd:e(gamma2)}, {cmd:e(gamma3)}, and {cmd:e(gamma4)}),
and {cmd:e(delta)}. Raw and trimmed innovation scales
{cmd:e(sigma_eps)} and {cmd:e(sigma_eps_trim)}, evolution-fit diagnostics
{cmd:e(r2_evo)} and {cmd:e(rmse_evo)}, lag-support diagnostics
{cmd:e(N_lag_untreated)}, {cmd:e(N_lag_treated)}, and
{cmd:e(lag_treated_supported)}, and support counts such as {cmd:e(N_omega)},
{cmd:e(N_evo)}, {cmd:e(N_eps0)}, {cmd:e(N_eps0_trim)}, cutoff scalars
{cmd:e(eps0_p1)} and {cmd:e(eps0_p99)} for the public eps0 trimming contract,
the stored untreated-innovation support window {cmd:e(eps0window)} used by
the main command and by {cmd:predict, residuals} safety checks,
and {cmd:e(N_trans)}. Replay/sample-summary scalars are also posted in
{cmd:e(N)}, {cmd:e(N_g)}, {cmd:e(N_clust)}, {cmd:e(tmin)}, {cmd:e(tmean)},
{cmd:e(tmax)}, {cmd:e(N_treated)}, {cmd:e(N_control)}, and
{cmd:e(N_trans)}. On the benchmark-by public paths, the grouped matrices
{cmd:e(b_by)}, {cmd:e(rho_by)}, {cmd:e(sigma_by)}, {cmd:e(N_by)}, and
{cmd:e(N_firms_by)} are posted alongside the replay/sample-summary scalars.
On those grouped results, {cmd:e(tmin)}, {cmd:e(tmean)}, and {cmd:e(tmax)}
follow the grouped display contract and summarize observations per group
(derived from {cmd:e(N_by)}), not panel length per firm.{p_end}

{phang}3. ATT objects when ATT is computed: {cmd:e(ATT_avg)} plus event-time
effects {cmd:e(att_0)}, {cmd:e(att_1)}, and the remaining numeric
event-time scalars for the exact realized support listed in
{cmd:e(attperiods)},
and matrices such as {cmd:e(att)},
{cmd:e(att_trim)}, {cmd:e(attperiods)}, and the point-path ATT dispersion/support
objects {cmd:e(att_sd)} and {cmd:e(N_by_period)}, plus the scalar
support count {cmd:e(att_N)} for the total number of treated firm-period
observations contributing to ATT across all nonnegative event times
({cmd:sum(e(N_by_period))}, not the number of unique treated firms). When the default trimmed path is active, the
overall trimmed summary is also stored in {cmd:e(ATT_avg_trim)}.
The public status flag {cmd:e(noatt)} is 1 if ATT estimation was skipped
(for example on a {opt noatt} run) and 0 otherwise.
On the benchmark-by point-estimate path, the grouped ATT surface is posted in
{cmd:e(att_by)} with the pooled grouped summary in {cmd:e(att_pool)}, and
the corresponding grouped dispersion/support matrices remain available in
{cmd:e(att_sd)} and {cmd:e(att_N)}. When that grouped point path republishes
the canonical trimmed track through {cmd:e(att_trim)} and {cmd:e(ATT_avg_trim)},
it also keeps the per-period trim scalar aliases {cmd:e(att_trim_0)},
{cmd:e(att_trim_1)}, and so on aligned with the same pooled trimmed path. In the
current replay/display contract, grouped output reads the exact integer
support counts from the canonical row vector {cmd:e(N_by_period)}, rebuilt
from the grouped support matrix {cmd:e(att_N)}. The grouped support matrix
itself stays aligned with that same grouped point support rather than with
bootstrap-draw success counts or a last-worker ATT sample. Sparse support is
still displayed in the exact order published in
{cmd:e(attperiods)} when that matrix is available.{p_end}

{pstd}In the
baseline path,
{cmd:e(att_0)} is the simulation-path onset effect produced by the
official DO-style untreated recursion; the deterministic Proposition 4.1
/ C.1 benchmark is available separately through
{cmd:_pte_cohort_att_instant}.{p_end}

{phang}4. Bootstrap objects when {cmd:bootstrap()>=2}: canonical replication-count
scalar {cmd:e(bootstrap)}, bootstrap-draw matrices {cmd:e(bs_raw)} and
{cmd:e(bs_betas)}. The coefficient-draw payload includes the published
production-function slope/trend contract: pooled Cobb-Douglas stores
{cmd:beta_l beta_k beta_t}, and pooled translog stores
{cmd:beta_l beta_k beta_ll beta_kk beta_lk beta_t} when the stage-1 path has a
single {cmd:control()} variable; the legacy {cmd:beta_t} column is used on that
single-control path. When the stage-1 path has multiple {cmd:control()}
variables, {cmd:e(bs_betas)} appends the exact control names after the
production-function coefficients. In other words, with a single
{cmd:control()} variable, the legacy {cmd:beta_t} column is used; with
multiple {cmd:control()} variables, {cmd:e(bs_betas)} appends the exact
control names as separate columns in the stored bootstrap coefficient-draw
payload. Event-time standard errors and confidence bounds
in {cmd:e(att_se)}, {cmd:e(att_ci_lower)}, and {cmd:e(att_ci_upper)}.
Equivalently: single control() variable, the legacy beta_t column is used;
multiple control() variables, e(bs_betas) appends the exact control names.
When a stochastic ATT/bootstrap stage is executed, seed metadata are also
stored in objects such as {cmd:e(seed)}, {cmd:e(seed_outer)}, and
{cmd:e(seed_source)}. Replay/display metadata also
include {cmd:e(level)}, the estimation-time confidence level used by bare
replay and by ATT confidence-interval recalculation when {cmd:pte, level()}
is requested. On any point-estimate ATT path
({cmd:bootstrap(0)} with ATT computed), {cmd:e(point_seed)} records the ATT
simulation seed actually used. On the serial point-estimate path, that is the
fixed inner ATT simulation seed; on the benchmark-by point-estimate ATT path,
it records the fixed official grouped point ATT simulation seed
{cmd:10000} passed to the grouped worker.
On that same benchmark-by point-estimate ATT path, {cmd:e(seed)} may preserve
wrapper seed metadata, including caller-specified {cmd:seed()} when present;
it is not the realized ATT simulation seed. The actual stochastic path uses
the fixed official grouped point ATT simulation seed {cmd:10000}, recorded in
{cmd:e(point_seed)}.
On the serial bootstrap path,
{cmd:e(point_seed)} records the fixed inner ATT simulation seed, and the
public wrapper also reposts the same realized value through
{cmd:e(inner_seed)} and {cmd:e(seed_inner)} so helper-level bootstrap replay
and top-level {cmd:e()} inspection stay aligned. The serial bootstrap path
also reposts {cmd:e(inner_seed_source)} and {cmd:e(seed_outer_strategy)} from
the live helper contract. On the
benchmark-by bootstrap path, {cmd:pte} follows the grouped DO seed contract
instead of publishing a reusable point-estimate inner seed, so
{cmd:e(point_seed)} is intentionally omitted there even when the translog
{cmd:replicate(order1)} benchmark injects the fixed DO seed internally.
On grouped bootstrap ATT runs, {cmd:e(seed)} and {cmd:e(seed_outer)} record the grouped bootstrap seed actually used. On the standard grouped live-stream path, {cmd:e(inner_seed)} is omitted while {cmd:e(inner_seed_source)} remains {cmd:inherited} to show that the grouped worker consumed the live grouped RNG stream instead of resetting a fixed ATT seed. When the grouped bootstrap path activates a fixed ATT inner seed (currently the translog {cmd:replicate(order1)} benchmark path), {cmd:e(inner_seed)} and {cmd:e(seed_inner)} repost that realized fixed ATT simulation seed while {cmd:e(point_seed)} remains intentionally omitted. The grouped bootstrap path does not publish {cmd:e(seed_outer_strategy)}; that outer-seed advancement rule belongs only to the serial bootstrap path. On {opt noatt} runs, the serial path omits {cmd:e(seed)}, {cmd:e(seed_source)}, {cmd:e(point_seed)}, {cmd:e(inner_seed)}, {cmd:e(seed_inner)}, {cmd:e(inner_seed_source)}, {cmd:e(seed_outer)}, and {cmd:e(seed_outer_strategy)}, while the grouped path omits {cmd:e(seed)}, {cmd:e(seed_source)}, {cmd:e(point_seed)}, {cmd:e(inner_seed)}, {cmd:e(seed_inner)}, {cmd:e(inner_seed_source)}, and {cmd:e(seed_outer)} because no ATT/bootstrap RNG stage is executed.
Because {opt noatt} is incompatible with {cmd:bootstrap()>0},
{cmd:e(seed_outer)} is not posted on {opt noatt} runs. The serial bootstrap path also stores
{cmd:e(seed_outer_strategy)} to identify how the outer bootstrap seeds advance
across replications (currently the main command uses the
{cmd:start_plus_index} rule), while the benchmark-by bootstrap path stores
the realized grouped bootstrap seed in {cmd:e(industry_seed)} and, when the
grouped wrapper requests parallel execution, the requested-vs-realized fallback
audit metadata in {cmd:e(parallel_method)}, {cmd:e(parallel_nproc)},
{cmd:e(parallel_requested_method)}, {cmd:e(parallel_requested_nproc)},
{cmd:e(parallel_fallback)}, {cmd:e(parallel_helper_rc)}, and
{cmd:e(parallel_fallback_reason)}.
Grouped bootstrap replay also preserves the grouped point support objects
{cmd:e(N_by_period)} and grouped support matrix {cmd:e(att_N)} so
replay/display show treated support counts instead of bootstrap-draw success
counts.{p_end}
{cmd:e(parallel_method)} / {cmd:e(parallel_nproc)} describe the realized
grouped execution branch after any fallback, while
{cmd:e(parallel_requested_method)} / {cmd:e(parallel_requested_nproc)}
preserve the originally requested launch contract.
{cmd:e(parallel_fallback_reason)} is omitted unless a grouped fallback occurs.
{cmd:e(parallel_helper_rc)} is omitted unless the grouped parallel helper
actually aborts before returning a payload. If the helper returns but its TT
sidecars cannot produce a complete pooled draw set, the grouped worker still
reposts the requested parallel audit fields and marks the final serial rerun
as a fallback instead of erasing that provenance; the public fallback-reason
token for that late helper-mismatch case is {cmd:payload_mismatch}.
Grouped bootstrap public results also repost the helper draw-accounting
scalars {cmd:e(nboot)}, {cmd:e(n_success)}, {cmd:e(n_fail)},
{cmd:e(n_success_group)}, and {cmd:e(n_fail_group)}. These count,
respectively, the requested grouped bootstrap replications, the complete
pooled draws used for inference, the incomplete pooled draws excluded from
inference, and the total successful/failed group-level draw attempts across
all groups.
When grouped bootstrap runs with default trimming active, the canonical public
ATT bundle ({cmd:e(att)}, {cmd:e(att_se)}, {cmd:e(att_ci_lower)},
{cmd:e(att_ci_upper)}) follows the trimmed pooled track.
{cmd:e(att_boot_all)} and {cmd:e(att_boot_trim)} store the grouped bootstrap
draw matrices (replication distributions) for the raw and trimmed tracks,
respectively. The grouped bootstrap repost
also preserves the worker-layout pooled bootstrap mean/SE/CI matrices behind
that public bundle, including
{cmd:e(att_mean_pool)}, {cmd:e(att_mean_pool_trim)},
{cmd:e(att_se_pool)}, {cmd:e(att_se_pool_trim)},
{cmd:e(att_ci_lower_pool)}, {cmd:e(att_ci_upper_pool)},
{cmd:e(att_ci_lower_trim)}, and {cmd:e(att_ci_upper_trim)}.
When {opt notrimeps} is active on the grouped bootstrap path, the canonical
public trim summaries ({cmd:e(att_trim)}, {cmd:e(ATT_avg_trim)},
{cmd:e(bs_se_trim)}, and the corresponding CI scalars) collapse to the raw
grouped bootstrap payload, but the worker-layout trim draw/mean/SE/CI matrices
remain omitted because the grouped helper does not generate a separate trimmed
draw family in that raw-only mode.
The public raw pooled point track remains available through
{cmd:e(att_raw)} /
{cmd:e(ATT_avg_raw)} keep the raw pooled track available alongside that
trimmed canonical bundle. Grouped bootstrap reposts also preserve the grouped
point-estimate ATT matrix in {cmd:e(att_by_point)} so {cmd:predict, att} can
still map group-specific ATT paths back to observations after bootstrap.
On those grouped {cmd:predict, att} paths, the current data must still
contain the exact grouping variable name stored in {cmd:e(by)}.
Prefix-abbreviation matches are not accepted, and a renamed or shadow
variable cannot be used to recover the grouped ATT row mapping.
The same grouped routing metadata are also required for bare {cmd:pte}
replay: if grouped ATT or grouped stage-1/2 replay payloads remain active but
{cmd:e(by)} is missing, replay fails closed rather than reusing pooled ATT or
serial evolution objects.
On the benchmark-by point-estimate path, grouped production-function
coefficients are stored in {cmd:e(b_by)}; {cmd:predict, parameters}
uses that matrix to display one coefficient vector per group. For a
single explicit {cmd:control()} variable, the grouped coefficient
surface keeps the legacy {cmd:beta_t} slot; with multiple explicit
controls, {cmd:e(b_by)}, {cmd:e(beta_boot_g#)}, and {cmd:e(beta_se_g#)}
append the exact control names after the structural coefficients.
On both the benchmark-by point-estimate path and grouped bootstrap public
reposts, evolution metadata needed by replay and {cmd:predict, residuals}
remain group-specific: the public result keeps {cmd:e(rho_by)} and
{cmd:e(sigma_by)} rather than relying on a serial {cmd:e(rho_0)} /
{cmd:e(rho_1)} bundle. Grouped support counts for those public results are
likewise stored in {cmd:e(N_by)} and {cmd:e(N_firms_by)}.
Grouped routing metadata are also posted in {cmd:e(by)} and, when
{opt industry()} is used, in {cmd:e(industry)}. If both {cmd:by()} and
{cmd:industry()} are supplied, they must spell the same exact grouping
variable name; different exact names fail closed rather than guessing which
grouped law should drive {cmd:e(by)}. When {opt industry()} or {opt byindustry} is active, the grouped repost also sets
{cmd:e(byindustry)}. The live group labels are stored in {cmd:e(groups)},
with grouped point-estimate results posting {cmd:e(n_groups)} and grouped
bootstrap reposts keeping the legacy alias {cmd:e(ngroups)}.
The resolved production-function polynomial order is stored as {cmd:e(poly)}
on both the serial and grouped public paths.
When {opt replicate()} is specified, the resolved public mode is preserved in
{cmd:e(replicate)} across both the serial and grouped public paths. The
trimming-status flag {cmd:e(notrimeps)} is posted when {opt notrimeps}
disables eps0 Winsorization. When the treatment-dependent production-function
path is active, {cmd:e(treatdependent)} is set to 1, and {cmd:e(normalize)}
stores the requested normalization mode when one is applied. When
normalization succeeds, the public result also preserves the normalization
worker metadata in {cmd:e(normalize_method)} and {cmd:e(omega_norm)}. When
the indexing-number {opt attnorm} path is used successfully, the public
result also preserves {cmd:e(att_norm_computed_flag)}, scalar
{cmd:e(att_norm_computed)}, and the full normalized ATT horizon
{cmd:e(att_norm_0)} through {cmd:e(att_norm_L)} where {cmd:L = e(attperiods_max)}. The
stored panel metadata keep {cmd:e(panelvar)}, {cmd:e(idvar)}, and the legacy
alias {cmd:e(id)} for the panel identifier, plus {cmd:e(timevar)} and the
legacy alias {cmd:e(time)} for the time variable, for postestimation
helpers. When the public result republishes the exact data-side aliases
{cmd:phi} and {cmd:omega} from the stored internal state, it overwrites only
those exact names; same-prefix caller variables such as {cmd:phi_shadow} or
{cmd:omega_shadow} are preserved rather than treated as abbreviations for the
canonical aliases. The same public result also stores the treatment-law certificate
{cmd:e(treatsig)} and, when panel spacing is identified, {cmd:e(xtdelta)}.
Those two fields are consumed by {helpb pte_p:predict} after
{helpb pte_setup}: the standard prediction/reporting branches require both
the live treatment-law certificate and the live spacing certificate to match
the stored setup contract, while the legacy {cmd:predict, residuals} fallback
may still use the setup-stored spacing only when a historical live result
does not yet publish {cmd:e(xtdelta)}.{p_end}

{pstd}
For the full list, run {cmd:ereturn list} after estimation.

{pstd}
After a successful run, typing {cmd:pte} without estimation syntax replays
the stored results using the current {cmd:e()} bundle.

{marker references}{...}
{title:References}

{phang}
Chen, Z., Liao, M., and Schurter, K. (2026).
Identifying Treatment Effects on Productivity.
{it:Working Paper}.
{p_end}

{marker authors}{...}
{title:Authors}

{pstd}
Zhiyuan Chen, Moyu Liao, and Karl Schurter
{p_end}

{pstd}
Wenli Xu, City University of Macau ({browse "mailto:wlxu@cityu.edu.mo":wlxu@cityu.edu.mo})
{p_end}

{pstd}
PTE Stata Package Development Team
{p_end}
