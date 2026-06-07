{smcl}
{* *! version 1.0.0  18mar2026}{...}
{vieweralsosee "pte" "help pte"}{...}
{vieweralsosee "pte_diagnose" "help pte_diagnose"}{...}
{vieweralsosee "graph combine" "help graph_combine"}{...}
{viewerjumpto "Syntax" "pte_graph##syntax"}{...}
{viewerjumpto "Description" "pte_graph##description"}{...}
{viewerjumpto "Graph families" "pte_graph##families"}{...}
{viewerjumpto "Style options" "pte_graph##style"}{...}
{viewerjumpto "Remarks" "pte_graph##remarks"}{...}
{viewerjumpto "Examples" "pte_graph##examples"}{...}
{viewerjumpto "Stored results" "pte_graph##results"}{...}
{viewerjumpto "References" "pte_graph##references"}{...}
{viewerjumpto "Authors" "pte_graph##authors"}{...}

{cmd:help pte_graph}{right:also see: {helpb pte}}
{hline}

{title:Title}

{p2colset 5 22 24 2}{...}
{p2col:{hi:pte_graph} {hline 1} Public graph router for stored PTE results}{p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:pte_graph}
[{cmd:,} {it:graph-family} {it:style-options} {it:worker-options}]

{pstd}
If no graph-family option is supplied, {cmd:pte_graph} defaults to the
standard postestimation ATT graph ({cmd:att}).

{marker description}{...}
{title:Description}

{pstd}
{cmd:pte_graph} is an {cmd:rclass} routing command. It selects one public
graph family and forwards the request to the corresponding internal graph
worker. Exactly one graph family may be chosen per call.

{pstd}
The command mainly acts as a dispatcher. Availability of a specific graph
depends on the stored {cmd:e()} results or generated {cmd:_pte_*} variables
required by the selected worker.

{pstd}
For the {cmd:compare} family, the active results must represent the full
Table 3 comparison bundle produced by {cmd:pte_compare, method(all)} with all
three specifications present. The public compare producer now enforces that
contract directly, so {cmd:pte_graph, compare} expects a complete 9-row
bundle with canonical row order {cmd:m1} through {cmd:m9} and treats any
partial or permuted compare payload as invalid state. When the active
compare result also posts {cmd:e(pte_att)}, the compare graph overlays
that reference ATT as a vertical line; otherwise it still renders the
canonical nine-row bundle without the reference line.

{marker families}{...}
{title:Graph families}

{synoptset 32 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Core graph selection}
{synopt:{opt att}}dynamic ATT graph; default when no graph family is specified;
rejects grouped {cmd:e()} states that would otherwise fall back to pooled
{cmd:e(att)}{p_end}
{synopt:{opt tt}}treatment-effect-on-treated graph{p_end}
{synopt:{opt catt}}cohort ATT graph{p_end}
{synopt:{opt compare}}comparison graph for supported comparison results{p_end}
{synopt:{opt heterogeneity}}heterogeneity graph wrapper; grouped bootstrap
replay requires exact {cmd:e(groups)} metadata and does not guess from
current-data group order{p_end}
{synopt:{opt scatter}}scatter-style PTE graph{p_end}
{synopt:{opt evolution}}productivity-evolution graph{p_end}
{synopt:{opt diagnose}}diagnostic graph wrapper{p_end}
{synopt:{opt combine}}graph-combination wrapper{p_end}

{syntab:Counterfactual and dynamic variants}
{synopt:{opt compare_cf}}counterfactual-comparison graph wrapper; rejects
grouped {cmd:e()} states that would otherwise drop grouped heterogeneity{p_end}
{synopt:{opt att_dynamic}}dynamic ATT graph variant worker; rejects grouped
{cmd:e()} states that would otherwise fall back to pooled {cmd:e(att)}{p_end}
{synopt:{opt ate_count_dynamic}}dynamic ATE-count graph variant worker; rejects
grouped {cmd:e()} states that would otherwise mix pooled dynamic objects into a
grouped result bundle{p_end}
{synopt:{opt tt_distribution}}distribution graph for stored TT objects{p_end}
{synopt:{opt eps0_diagnostic}}diagnostic graph for stored untreated-shock
objects{p_end}

{syntab:Grouping}
{synopt:{opt by(varname)}}route {cmd:tt}, {cmd:catt}, {cmd:compare},
{cmd:scatter}, {cmd:evolution}, and {cmd:diagnose} through the by-group wrapper;
{cmd:heterogeneity} handles {cmd:by()} directly; {cmd:att by(...)} is rejected
because stored {cmd:e(att)} is pooled across groups; other families reject
public {cmd:by()}; the grouping variable name must match an existing column
exactly{p_end}
{synoptline}

{marker style}{...}
{title:Style options}

{pstd}
The router accepts the following common style options and forwards them when
the selected worker understands them:

{synoptset 32 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt preset(string)}}style preset name{p_end}
{synopt:{opt scheme(string)}}graph scheme{p_end}
{synopt:{opt lcolor(string)}}line color{p_end}
{synopt:{opt lwidth(string)}}line width{p_end}
{synopt:{opt lpattern(string)}}line pattern{p_end}
{synopt:{opt msymbol(string)}}marker symbol{p_end}
{synopt:{opt msize(string)}}marker size{p_end}
{synopt:{opt mcolor(string)}}marker color{p_end}
{synopt:{opt mfcolor(string)}}marker fill color{p_end}
{synopt:{opt title(string)}}graph title{p_end}
{synopt:{opt xtitle(string)}}x-axis title{p_end}
{synopt:{opt ytitle(string)}}y-axis title{p_end}
{synopt:{opt subtitle(string)}}graph subtitle{p_end}
{synopt:{opt note(string)}}graph note{p_end}
{synopt:{opt legend(string)}}legend options passed as a string payload{p_end}
{synopt:{opt legendpos(#)}}legend position override; public range is
{cmd:0..12}{p_end}
{synopt:{opt legendcols(#)}}legend column override{p_end}
{synopt:{opt legendring(#)}}legend ring override{p_end}
{synopt:{opt nolegend}}suppress legend when supported by the worker{p_end}
{synopt:{opt xline(string)}}x-axis reference-line specification{p_end}
{synopt:{opt yline(string)}}y-axis reference-line specification{p_end}
{synopt:{opt refline(#)}}numeric reference line forwarded whenever
{cmd:refline()} is explicitly supplied{p_end}
{synopt:{opt norefline}}suppress the forwarded reference line when
supported{p_end}
{synopt:{opt bgcolor(string)}}background color{p_end}
{synopt:{opt grid}}request grid display when supported{p_end}
{synopt:{opt nogrid}}request no-grid display when supported{p_end}
{synopt:{opt gridstyle(string)}}grid style{p_end}
{synopt:{opt alpha(#)}}alpha level / opacity style parameter; public range is
{cmd:0..100}; router default is {cmd:100}{p_end}
{synoptline}

{pstd}
Additional worker-specific options are passed through in the free-form
{it:worker-options} position. Whether a given option is valid depends on
the selected graph worker.

{pstd}
For backward compatibility, the router also accepts legacy
{cmd:type(family)} calls for still-supported graph families such as
{cmd:type(att)} and {cmd:type(evolution)}. The legacy {cmd:saving()}
alias is normalized to the worker-level {cmd:save()} option, and bare
{cmd:ci} is accepted as an ATT-family compatibility flag.

{pstd}
The public router rejects contradictory common style requests at entry.
In particular, {cmd:grid} cannot be combined with {cmd:nogrid},
{cmd:refline()} cannot be combined with {cmd:norefline}, and
{cmd:legend()} cannot be combined with {cmd:nolegend}. These conflicts are
reported as public parameter errors ({cmd:rc=198}) rather than being left to
worker-specific graph code.

{pstd}
The same public conflict handling applies to {cmd:save()} versus the legacy
{cmd:saving()} alias: supply at most one of them in a single call.

{pstd}
For {cmd:diagnose}, the current public worker recognizes
{cmd:type(cdf|kdensity|eps0_byyear|diff_omega0|eps0_treat_control|placebo|omega_density)}.
When {cmd:type(placebo)} is used, both {cmd:coef(varname)} and
{cmd:refval(#)} are required. Common
worker options for the newer diagnose subtypes include
{cmd:coef(varname)}, {cmd:nt(numlist)}, {cmd:years(numlist)},
{cmd:refyear(numlist)}, {cmd:winsor(numlist)}, {cmd:bins(#)},
{cmd:save(filename)}, {cmd:export(filename)},
{cmd:width(#)}, and {cmd:height(#)}.

For {cmd:type(eps0_byyear)} and {cmd:type(eps0_treat_control)},
industry-level breakdowns should use the public grouping contract
{cmd:by(industry_var) combine}. Those subtypes do {bf:not} accept
worker-level {cmd:industry()}.

{pstd}
On the default diagnostic-{cmd:_pte_eps0} path, the released graph workers
honor the exact untreated-innovation support indicator {cmd:_pte_eps0_ind}
when it is available. When the current dataset still carries a certified live
{cmd:pte} result or a stored {cmd:pte_setup} contract {it:and} retains the
released EPIC-002 support-state markers (for example {cmd:_pte_active_sample}
or {cmd:_pte_eps0_trim}), that indicator is now required: if
{cmd:_pte_eps0_ind} is missing while {cmd:_pte_eps0} survives, the worker
stops with {cmd:rc=111} instead of silently treating every nonmissing
{cmd:_pte_eps0} value as certified untreated-shock support. Pure ad hoc graph
fixtures without a live/setup claim may still use the legacy standalone
fallback.
That missing-indicator gate is itself fail-closed: when those markers still
claim setup-backed or live provenance, the worker first re-certifies the
current treatment law and returns {cmd:rc=459} on stale setup/live contracts
before it can report missing {cmd:_pte_eps0_ind}.

{pstd}
For {cmd:type(eps0_treat_control)}, when the current dataset still carries
the panel time variable from {cmd:xtset} or stored {cmd:pte} metadata, the
live worker mirrors the paper's Appendix E.3 comparison window: treated
observations use the last three pre-treatment periods tracked by the exact
{cmd:_pte_nt}, and control observations are restricted to the same
calendar window before the K-S comparison and density plot are built.
Like the other time-window diagnose subtypes, a complete stored
{cmd:pte_setup} contract can certify that calendar window when live
{cmd:e(xtdelta)} is missing; only genuine setup/live {cmd:xtdelta} drift
still stops with {cmd:rc=459}.

{pstd}
For {cmd:type(eps0_byyear)} and {cmd:type(diff_omega0)}, the router now reads
only the exact canonical state objects used by the current diagnostics law.
Shadow leftovers such as {cmd:_pte_eps0_shadow}, {cmd:_pte_year_shadow}, or
{cmd:_pte_firm_shadow} no longer satisfy those contracts through Stata's
abbreviation binding. The narrow pure-legacy fallback still exists, but only
for the exact legacy bridges {cmd:_pte_year} and {cmd:_pte_firm}. These
time-only / panel-id-only diagnose subtypes also use the same narrow
setup-backed bridge as {cmd:pte_diagnose}: when a complete stored
{cmd:pte_setup} contract is present, the active live {cmd:pte} result must
still publish {cmd:e(idvar)} / {cmd:e(timevar)} or the legacy aliases
{cmd:e(id)} / {cmd:e(time)} so the graph can certify the current panel axis.
That setup-backed path may bridge a missing live {cmd:e(xtdelta)}, but it
does {bf:not} bridge missing live panel/time metadata, and any true
setup/live {cmd:xtdelta} conflict still stops with {cmd:rc=459}. Public
{cmd:by()} requests for the panel-aware diagnose subtypes are now certified
once on the full dataset before subgrouping, and the subgroup workers reuse
that certified axis instead of re-certifying the full-sample live law
against each preserved subsample. For
{cmd:type(diff_omega0)}, the exact canonical worker state must also remain
certified: {cmd:_pte_omega} and {cmd:_pte_tt} must stay numeric,
{cmd:_pte_treat} must stay binary, and {cmd:_pte_nt} must stay
integer-valued. Otherwise the worker fails closed with the same
internal-state errors used by the other graph consumers instead of silently
dropping corrupted treated rows or falling through to a late type mismatch.
Even without a stored {cmd:pte_setup} contract, a complete live
{cmd:e(idvar/timevar/treatment/treatsig)} bundle is now re-certified against
the current dataset before these panel/event-time consumers run, so stale
live-only graph calls also stop with {cmd:rc=459} instead of silently using
old treatment timing objects.

{pstd}
For {cmd:type(omega_density)}, omitting {cmd:industry()} draws the full-sample
control, treated, and all-sample density curves. Supplying
{cmd:industry(varname)} switches the worker to an industry-level breakdown:
the graph is split by distinct values of {cmd:industry()}, each industry panel
plots only the control and treated density curves for that subsample, and the
panels are combined into one exported graph. The worker also requires the
exact canonical {cmd:_pte_omega} to remain a numeric productivity variable and
the exact canonical {cmd:_pte_D} to remain binary; malformed internal state
now stops with {cmd:rc=111} before any {cmd:kdensity} call is attempted. When
the dataset still carries a stored {cmd:pte_setup} contract or an active live
{cmd:pte} result, this subtype also re-certifies the current treatment law
before grouping on {cmd:_pte_D}; stale setup/live contracts now fail closed
with {cmd:rc=459} on both the full-sample and {cmd:industry()} routes.

{pstd}
For {cmd:evolution}, the worker reads the exact canonical
{cmd:_pte_omega}, {cmd:_pte_nt}, and the canonical firm-level ever-treated
bridge {cmd:_pte_treat}. The productivity bridge must remain numeric, and the
treated-support bridge must remain binary and constant within each panel unit;
if the dataset only carries a current-period treatment path, the worker stops
with {cmd:rc=450} instead of silently moving pre-treatment observations from
the treated trajectory into the control path. Malformed exact
{cmd:_pte_omega} state now stops with {cmd:rc=111} before the graph tries to
collapse group means.

{pstd}
For {cmd:tt_distribution}, the worker reads the exact canonical
{cmd:_pte_tt}, {cmd:_pte_treat}, and {cmd:_pte_nt} variables from the
current dataset and requires the live estimation state to contain
{cmd:e(attperiods)}. The treated-mask bridge {cmd:_pte_treat} must remain
binary because TT is defined only for treated observations; control rows and
stale nonbinary states are rejected rather than silently graphed. The stored
support determines which event-time periods are graphed, so residual
{cmd:_pte_nt} values outside the identified ATT horizon are ignored rather
than treated as additional graphable periods. Supported TT periods cannot be
empty: if any event time declared in {cmd:e(attperiods)} lacks nonmissing
treated {cmd:_pte_tt} observations, the worker stops with {cmd:rc=198}
instead of silently shrinking {cmd:r(periods)} or exporting a partial graph.
It accepts worker options such
as {cmd:save()}, {cmd:export()}, {cmd:width()}, {cmd:height()}, and
{cmd:nolegend}.

{pstd}
For {cmd:att}, the worker reads the pooled ATT path {cmd:e(att)} against the
exact stored support in {cmd:e(attperiods)} and consumes the stored ATT
confidence-interval object from either {cmd:e(att_lb)}/{cmd:e(att_ub)} or the
legacy bootstrap alias pair {cmd:e(att_ci_lower)}/{cmd:e(att_ci_upper)}.
Those bounds are one interval object, not independent optional matrices: each
pair must arrive together, and if both naming families are posted they must
agree on the full ATT support. A stored bootstrap count without a matched ATT
CI pair still stops with {cmd:rc=198} instead of silently downgrading to a
point-only graph. Those supported CI cells must also remain nonmissing on
every listed dynamic period. Likewise, every dynamic period listed in
{cmd:e(attperiods)} must have a nonmissing ATT point estimate in
{cmd:e(att)}; the worker rejects certified support with point-estimate
holes via {cmd:rc=198} rather than drawing a broken ATT path. Because the
optional support-count sidecar {cmd:e(N_by_period)} is consumed on the same
exact event-time support, its dynamic column identities must also match
{cmd:e(attperiods)}; sparse-support drift such as {cmd:nt0 nt1} under
{cmd:e(attperiods)=(0,2)} now stops with {cmd:rc=198} instead of silently
publishing the wrong period counts in the graph note and {cmd:r(n_#)}.
Because the
default {cmd:att} graph also draws the pooled {cmd:ATT_avg} summary point,
that default path additionally requires the last column of {cmd:e(att)} and
the pooled ATT CI cells (when CIs are present) to be nonmissing. Use
{cmd:noaverage} to graph only the dynamic path when the stored pooled summary
is intentionally absent.

{pstd}
For {cmd:ate_count_dynamic}, the worker reads {cmd:e(ate_count)} and, when
{cmd:overlay_att} is specified, overlays the stored {cmd:e(att)} path as an
additional ATT line. The overlay is line-only: {cmd:overlay_att} adds the ATT
line only; it does not draw ATT confidence bands. Dynamic ATT and
ATE-count graphs fail closed when only one CI bound survives in
{cmd:e()}: {cmd:e(att_lb)} and {cmd:e(att_ub)} must arrive together,
the bootstrap alias pair {cmd:e(att_ci_lower)} / {cmd:e(att_ci_upper)}
must also arrive together, and {cmd:e(ate_count_lb)} /
{cmd:e(ate_count_ub)} must remain paired. Both dynamic families also
fail closed when both ATT CI naming families are posted but disagree on
the graphed dynamic-period support: {cmd:e(att_lb)}/{cmd:e(att_ub)} and
{cmd:e(att_ci_lower)}/{cmd:e(att_ci_upper)} must represent the same
dynamic ATT interval object rather than competing values. They also
require the exact stored event-time support in {cmd:e(attperiods)}:
the graph workers do not infer a contiguous 0..L horizon from matrix
width, and they reject missing or drifting support with {cmd:rc=198}.
Whenever ATT confidence intervals are posted on those dynamic workers,
every listed dynamic period must also carry nonmissing ATT lower and
upper bounds rather than a supported CI hole. For
{cmd:ate_count_dynamic}, the same exact-support law also applies to the
ATE-count payload itself: every listed dynamic period must carry a
nonmissing {cmd:e(ate_count)} point estimate and, when ATE-count
confidence intervals are posted, nonmissing
{cmd:e(ate_count_lb)}/{cmd:e(ate_count_ub)} bounds. A direct Appendix D
divergent result can therefore be graphed on this route once the worker
publishes the graph-facing aliases {cmd:e(ate_count)} and
{cmd:e(attperiods)} in addition to its internal
{cmd:e(ate_counterfactual)} payload.

{pstd}
When {cmd:overlay_att} is requested, {cmd:ate_count_dynamic} also consumes
the shared ATT path directly. The overlay therefore follows the same exact
stored support in {cmd:e(attperiods)}: every graphed dynamic period must
carry a nonmissing {cmd:e(att)} value, or the worker stops with
{cmd:rc=198} instead of drawing a broken ATT overlay that disagrees with
{cmd:compare_cf} or {cmd:att_dynamic}.

{pstd}
For {cmd:compare_cf}, the worker reads the pooled comparison bundle
{cmd:e(att)} and {cmd:e(ate_count)} against the exact stored support in
{cmd:e(attperiods)}. Sparse support is consumed as posted; the worker does
not relabel dynamic columns to an inferred contiguous 0..L horizon. When
any dynamic period listed in {cmd:e(attperiods)} has a missing ATT or
ATE-count point estimate, the graph fails closed with {cmd:rc=198}
instead of silently drawing a supported period with a hole. When
the stored dynamic matrices keep the same width but permute their dynamic
column identities away from the declared {cmd:e(attperiods)} order, the
worker also fails closed with {cmd:rc=198} instead of silently binding the
wrong event time to a plotted value. When
bootstrap confidence intervals are present, the ATT pair
{cmd:e(att_lb)}/{cmd:e(att_ub)} and the ATE-count pair
{cmd:e(ate_count_lb)}/{cmd:e(ate_count_ub)} must each remain complete, and
if the ATT bootstrap alias pair {cmd:e(att_ci_lower)}/{cmd:e(att_ci_upper)}
is also posted, it must agree with {cmd:e(att_lb)}/{cmd:e(att_ub)} on the
graphed dynamic support. Those supported CI cells must also remain
nonmissing on every listed dynamic period. Otherwise the stored ATT interval
object is
ambiguous and the graph fails closed with {cmd:rc=198}. The worker also
rejects partial comparison bundles with {cmd:rc=198} instead of
downgrading to a misleading point-estimate-only graph. When the caller
uses the default graph note, the displayed bootstrap replication count is
resolved from {cmd:e(bootstrap)}, then {cmd:e(breps)}, and finally
{cmd:e(nboot)} so the note remains stable across both counterfactual
producers and replay paths.

{pstd}
For {cmd:eps0_diagnostic}, the worker reads {cmd:_pte_eps0}. When the
current dataset also carries the canonical treatment-timing bridge
({cmd:_pte_treat}, {cmd:_pte_nt}, and the certified panel contract from
{cmd:pte_setup} or live {cmd:pte}), the grouped CDF panel now reuses the
same law as {cmd:pte_diagnose, cdf}: exact-support filtering,
1--99 trimming, treated firms restricted to the last three
pre-treatment periods, and controls matched to the treated calendar
window. It accepts {cmd:qqonly} or {cmd:cdfonly} to restrict output to one
panel, plus {cmd:save()}, {cmd:export()}, {cmd:width()},
{cmd:height()}, and {cmd:nolegend}. The mode selectors {cmd:qqonly}
and {cmd:cdfonly} are mutually exclusive and cannot be combined in the
same call. As on the released {cmd:pte_diagnose, cdf} path, a complete
stored setup contract can certify the calendar window when live
{cmd:e(xtdelta)} is missing; only real setup/live {cmd:xtdelta} drift
continues to fail closed. The same default trimmed untreated-shock
support is now reused by the Q-Q panel and by the no-treatment CDF
fallback, so {cmd:qqonly} and the combined graph fail closed with
{cmd:rc=198} whenever trimming collapses the support to zero variance.
When the package-owned default {cmd:_pte_eps0} still claims setup-backed
or live {cmd:pte} provenance, the shared support helper now re-certifies
that treatment law before honoring {cmd:_pte_eps0_ind}; stale
setup/live law therefore stops with {cmd:rc=459} even when the support
indicator is still present.

{pstd}
As with {cmd:pte_graph, diagnose type(cdf)}, a pure compatibility stub that
stores only {cmd:e(cmd)="pte"} or only the bare treatment name
{cmd:e(treatment)} is {it:not} treated as an active live panel claim. In
that narrow legacy state, the grouped CDF panel may still fall back to the
materialized calendar variable {cmd:_pte_year}. Once any live panel payload
or {cmd:e(predict)} payload is present, however, the worker fails closed on
the shared setup/live panel contract instead of silently reviving the legacy
fallback.

{pstd}
The same full-sample certification rule also now applies to
{cmd:pte_graph, evolution by(...)}: once the wrapper has certified the
current live/setup law on the full dataset, the preserved subgroup workers
reuse that axis rather than comparing the full-sample live
{cmd:e(treatsig)} to each subgroup-specific treatment path.

{marker remarks}{...}
{title:Remarks}

{dlgtab:One graph family per call}

{pstd}
The router counts family selectors and exits with an error if more than one
is supplied in the same call. An exception applies to the {cmd:by()} layout
route: when {cmd:by()} and {cmd:combine} are supplied together and the
selected family is one of {cmd:tt}, {cmd:catt}, {cmd:compare},
{cmd:scatter}, {cmd:evolution}, or {cmd:diagnose},
{cmd:combine} is treated as a layout request rather than a second family
selector.

{dlgtab:Default ATT behavior}

{pstd}
If no graph family is specified, {cmd:pte_graph} chooses {cmd:att}. For
non-absorbing estimation results, the router inspects stored treatment-type
metadata in {cmd:e()} and redirects the {cmd:att} request to the dedicated
non-absorbing ATT graph worker. Helper-produced
{cmd:e(cmd)=_pte_bootstrap_nonabs} result bundles with live
{cmd:e(att_plus)} / {cmd:e(att_minus)} payloads are treated as the same
non-absorbing ATT family even when explicit treatment-type metadata were not
posted. When those payloads also expose an explicit {cmd:nt} column, the
non-absorbing worker preserves that event-time support on the x-axis and in
{cmd:r(nt)} instead of re-indexing rows. When the helper also posts
{cmd:e(att_plus_ci_lower/upper)} and {cmd:e(att_minus_ci_lower/upper)}, the
non-absorbing ATT worker now reuses those stored bootstrap CI bounds directly
only when they carry the same canonical {cmd:nt#} support labels as the live
{cmd:e(att_plus)} / {cmd:e(att_minus)} payload; support-drifting CI bundles
now fail closed with {cmd:rc=198} instead of being silently consumed by row
order. Otherwise it falls back to recomputing normal-approximation intervals
from
{cmd:e(att_plus_se)} / {cmd:e(att_minus_se)}.
When the main non-absorbing ATT payload uses the canonical four-column
{cmd:[ATT, SD, N, nt]} contract, those side SE matrices must also publish the
same canonical {cmd:nt#} labels on their rownames or colnames; unlabeled side
SE bundles now fail closed instead of being consumed by row position.
For the main non-absorbing ATT payload itself, the live consumer accepts only
either a pure ATT vector or the exact canonical four-column
{cmd:[ATT, SD, N, nt]} producer contract. Partial two- or three-column helper
payloads, reordered four-column payloads, and orphan extra columns now fail
closed with {cmd:rc=198} instead of being silently re-indexed or consumed as
fake event-time support. When the canonical four-column path is used, the
posted {cmd:nt} support must also be strictly increasing, unique, and matched
by the matrix rownames ({cmd:nt#}) row by row.
If a helper-produced non-absorbing bundle exposes only one side
({cmd:e(att_plus)} without {cmd:e(att_minus)}, or vice versa), the public
router now fail-closes with {cmd:rc=198} and an explicit one-sided-bundle
message instead of falling through to the absorbing {cmd:e(att)} worker.
For {cmd:attdiff}, direct {cmd:e(att_diff_se_boot)} payload is preferred when
available. It may be posted as either an {it:N}x1 column vector or a
1x{it:N} row vector, but when the main non-absorbing ATT payload posts
canonical {cmd:nt} support, the direct difference-SE payload must publish the
same canonical {cmd:nt#} labels on its rownames or colnames. Support-drifting
direct difference-SE bundles now fail closed instead of being consumed by row
position. If explicit {cmd:e(att_diff_se_boot)} is absent but the helper
still exposes matched raw draw matrices
{cmd:e(att_plus_boot)} / {cmd:e(att_minus_boot)}, the worker derives the
paired bootstrap difference distribution directly and fail-closes malformed
draw bundles instead of silently degrading to delta-method uncertainty. The
raw helper draw matrices must share the same canonical {cmd:nt#} column names
and align with the live non-absorbing {cmd:e(att_plus)} / {cmd:e(att_minus)}
support. If the main non-absorbing ATT payload is only a one-column vector,
auxiliary helper / bootstrap / SE payloads may omit support labels or use only
the fallback dense {cmd:nt0 nt1 ...} route implied by row order; drifting
orphan {cmd:nt#} sidecar labels now fail closed instead of being bridged to
the fallback dense 0..N-1 horizon. If that one-column main payload itself uses
nt-like rownames, they must equal the same fallback dense route exactly;
sparse or drifting main-payload rownames now fail closed instead of being
silently ignored. The attdiff graph renders that difference CI even when side
ATT+ /
ATT- SE or side CI objects are absent, because the difference uncertainty is
consumed on its own contract.

{pstd}
When the live {cmd:e()} bundle still contains grouped ATT payloads from
{cmd:pte, by(...)} or {cmd:pte, industry(...)}, the pooled-only families
{cmd:att}, {cmd:compare_cf}, {cmd:att_dynamic}, and
{cmd:ate_count_dynamic} now reject the request with {cmd:rc=198}. This
matches the export contract: those families consume pooled dynamic objects,
so silently drawing {cmd:e(att)} from a grouped state would discard the
group-specific ATT paths that remain active in {cmd:e(att_by)},
{cmd:e(att_by_point)}, {cmd:e(att_pool)}, or grouped bootstrap payloads such
as {cmd:e(att_mean_pool)}, {cmd:e(att_se_pool)}, {cmd:e(att_boot_g#)}, and
{cmd:e(att_se_g#)}. Use {cmd:pte_graph, heterogeneity by(...)} for grouped
displays, or re-run a pooled {cmd:pte} estimation before graphing pooled
dynamic effects.

{dlgtab:by()}

{pstd}
When {opt by()} is supplied, the router delegates only the following
families to the public by-group graph wrapper: {cmd:tt}, {cmd:catt},
{cmd:compare}, {cmd:scatter}, {cmd:evolution}, and {cmd:diagnose}. That
wrapper generates one graph per group and may combine them. If {cmd:by()} and
{cmd:combine} are supplied together for these families, the router forwards
{cmd:combine} as a layout request to the by-group wrapper. The
{cmd:heterogeneity} family handles {cmd:by()} through its own worker
contract. The router rejects public {cmd:by()} for {cmd:att}, {cmd:combine},
{cmd:compare_cf}, {cmd:att_dynamic}, {cmd:ate_count_dynamic},
{cmd:tt_distribution}, and {cmd:eps0_diagnostic}; for {cmd:combine}, use
the worker's grouping options such as {cmd:byperiod}, {cmd:byindustry}, or
{cmd:bygroup()} instead. Because stored {cmd:e(att)} is a pooled dynamic ATT
path, {cmd:pte_graph, att by(...)} would otherwise repeat the same full-sample
ATT graph for every subgroup. Since the router's no-family default is
{cmd:att}, callers should name a supported family explicitly when using
{cmd:by()}.

{pstd}
For the {cmd:heterogeneity} family, the live worker aggregates only the
treated TT support on the exact stored event-time support in
{cmd:e(attperiods)}: observations must satisfy the requested event-time filter,
have nonmissing {cmd:_pte_tt}, and satisfy the exact canonical treated-support
bridge {cmd:_pte_treat==1}. If the exact {cmd:_pte_treat} bridge is missing or
malformed, the worker fails closed instead of treating all nonmissing TT rows
as treated support. Leftover {cmd:_pte_nt} rows outside {cmd:e(attperiods)} are
ignored rather than silently entering the Table 2 graph totals.
Any observation on that exact supported treated TT sample must also carry a
nonmissing {cmd:by()} label. If supported treated TT rows have missing
subgroup labels, {cmd:pte_graph, heterogeneity} exits with {cmd:rc=198}
instead of shrinking the graph totals or replay bundle to the labeled subset.

{pstd}
When {cmd:heterogeneity} is used with {cmd:nt(#)} and grouped bootstrap
metadata are active, the worker now requires live period-specific grouped
bootstrap draws ({cmd:e(att_boot_g#)} or {cmd:e(att_trim_boot_g#)}) together
with exact {cmd:e(attperiods)} support. A pooled {cmd:pte_heterogeneity}
repost that keeps only {cmd:e(att_boot_bygroup)} or {cmd:e(boot_att_by)}
is valid only for the default pooled Table 2 graph; it is rejected for
{cmd:nt(#)} because those sidecars summarize the overall ATT rather than a
specific event-time ATT_{it}.

{pstd}
For the default pooled {cmd:heterogeneity} graph, grouped bootstrap standard
errors remain indexed by the estimation-time grouped route. The live worker
therefore requires both {cmd:e(by)} and {cmd:e(groups)} to remain present and
to agree with the public {cmd:by()} request. This same fail-close rule also
applies to pooled {cmd:pte_heterogeneity} reposts: once the repost has already
collapsed the grouped route to its surviving Table 2 support, {cmd:e(groups)}
must match that live grouped support exactly in both count and token order.
Across both live grouped runs and pooled reposts, {cmd:e(groups)} must also
stay unique token by token; duplicate route tokens are rejected because they
destroy the one-to-one map between grouped bootstrap draw columns and group
support labels. If grouped bootstrap ATT draws are active but that route
metadata are missing, duplicated, or mismatched, the worker exits with
{cmd:rc=198} instead of remapping grouped bootstrap columns by the current
dataset order.
For pooled reposts that survive only through {cmd:e(att_boot_bygroup)}, the
pooled sidecar must remain synchronized with that same route contract: exactly
one column per token in {cmd:e(groups)}, and canonical grouped replay column
names in order ({cmd:g1 ... gG}, with the legacy fixture alias
{cmd:group1 ... groupG} also accepted). Reordered, renamed, or extra pooled
grouped-bootstrap columns are rejected with {cmd:rc=198} rather than silently
trimming or consuming them by position.
When replay falls back further to the older summary-shell {cmd:e(boot_att_by)},
its retained rows are now remapped in that same exact live grouped-route
order; same-count legacy summary shells no longer escape reordering merely
because they already have the expected row count.
For the older summary-shell fallback {cmd:e(boot_att_by)}, the same
{cmd:e(groups)} route still governs replay order: if the live grouped support
remaps to a same-count permutation such as {cmd:keep(2 1)}, the worker now
reorders the summary rows to that exact live route instead of consuming a
same-sized shell by its stored row order.
That legacy remap now applies only to subgroup rows. The pooled Total-row SE
is recovered separately: first from the live {cmd:e(att_se)} ATT_avg bundle
when it exists, otherwise from the trailing Total row of {cmd:e(boot_att_by)}
when that row is present, and only then from the reduced-context
{cmd:sd/sqrt(N)} fallback. The graph no longer reuses the last remapped
subgroup SE as the pooled Total-row SE.
For the pooled Total row, the graph first reuses the live {cmd:e(att_se)}
bundle exposed by {cmd:pte}: the default pooled graph requires
{cmd:e(att_se)[1,colsof(e(att_se))]} (= {cmd:ATT_avg}) and the
{cmd:nt(#)} route requires the supported-period cell corresponding to that
stored event time. If the live {cmd:e(att_se)} matrix is posted but the
required cell is missing, {cmd:pte_graph, heterogeneity} exits with
{cmd:rc=198} instead of reconstructing a new Total-row SE from the current
TT sample. The pooled {cmd:sd/sqrt(N)} fallback is reserved only for reduced
helper contexts where no live {cmd:e(att_se)} bundle exists.

{pstd}
On the by-wrapper path, a single {cmd:save()} or {cmd:export()} target is
defined only when the wrapper produces one public graph artifact: either a
single plotted group or a {cmd:combine} layout. If {cmd:by()} yields multiple
subgroup graphs and {cmd:combine} is not requested, the wrapper rejects
{cmd:save()} and {cmd:export()} with {cmd:rc=198} rather than silently mapping
multiple subgroup graphs onto one filename. Use {cmd:combine} for one combined
artifact, or {cmd:saveall()} for per-group {cmd:.gph} files.

{pstd}
The public router requires an exact existing grouping variable name in
{cmd:by()}. Abbreviation-style bindings such as {cmd:by(ind)} are rejected
when the data contain only a column like {cmd:industry_shadow}; this avoids
silently plotting groups defined by the wrong variable.

{pstd}
After the wrapper accepts the public group levels, each requested subgroup
must generate its own worker graph. If any subgroup worker fails (for example
because the subgroup has no valid placebo or scatter support), the by-wrapper
now exits with that subgroup error code instead of silently dropping the
failed subgroup and returning a partial combined artifact.

{pstd}
For {cmd:evolution}, the by-group wrapper checks the canonical
ever-treated bridge before slicing the dataset into subgroup panels. A
time-varying {cmd:by()} variable therefore cannot launder a current-period
{cmd:_pte_treat} mask into subgroup-constant slices.

{pstd}
For graph families that do {bf:not} support public {cmd:by()}, the router
rejects {cmd:by()} at the family gate before checking whether the supplied
token matches a live dataset column. This keeps the unsupported-{cmd:by()}
contract from changing with dataset state.

{dlgtab:Router contract vs worker contract}

{pstd}
{cmd:pte_graph} documents only the public routing contract. Subworkers have
their own prerequisites and option syntax. In practice, this means a style
option accepted by the router may still be ignored or rejected downstream if
the chosen worker does not implement it.

{pstd}
This prerequisite point matters for the newer graph families. In the
current public implementation, {cmd:tt_distribution} requires the exact
canonical {cmd:_pte_tt} and {cmd:_pte_nt} variables in the active dataset and
the exact stored support matrix {cmd:e(attperiods)}; {cmd:eps0_diagnostic}
requires {cmd:_pte_eps0} and can use {cmd:_pte_treat} when present; and
{cmd:diagnose} subtype requirements vary with {cmd:type(...)}. These
families are therefore not guaranteed to work from stored {cmd:e()}
results alone.

{pstd}
The same worker-specific rule applies to file-output options such as
{cmd:save()} and {cmd:export()}, diagnostic subtypes such as
{cmd:type(...)}, and family-specific payloads. These are accepted through the
free-form worker-options position, not standardized by the router itself.

{pstd}
For {cmd:catt}, the Figure 5-style normalization now follows the same narrow
state-object rule as the other graph workers: industry normalization uses only
the exact canonical {cmd:_pte_industry} bridge. If that exact industry bridge
is absent, the worker falls back to the no-industry normalization law instead
of silently binding to leftovers such as {cmd:_pte_industry_shadow} through
Stata abbreviation matching. Because the worker only needs the firm identifier
to carry the pre-treatment bin forward within each panel, a complete stored
{cmd:pte_setup} contract may now bridge a missing live {cmd:e(xtdelta)} as
long as the active live {cmd:pte} result still certifies the same panel/time
and treatment law via {cmd:e(idvar)}/{cmd:e(timevar)} (or the legacy aliases)
plus {cmd:e(treatsig)}. A narrow live {cmd:e(cmd)="pte"} stub that publishes
the full current-law bundle may still use that stored panel id even when
{cmd:e(xtdelta)} is absent. But once a live {cmd:e(cmd)="pte"} claimant
publishes any panel/time fragment, it must still satisfy the shared helper's
law contract instead of reviving a panel-only fallback. Pure compatibility
stubs that publish only {cmd:e(cmd)="pte"} or only a bare {cmd:e(treatment)}
name may still use the legacy exact {cmd:_pte_firm} bridge. Incomplete
live panel claimants therefore fail closed with {cmd:rc=459} rather than
silently plotting CATT bins on stale event-time objects. Genuine
setup/live {cmd:xtdelta} conflicts still fail closed with {cmd:rc=459}.
Public {cmd:by()} CATT calls are also law-first: the wrapper certifies the
current panel/treatment law once on the full dataset, then forwards an
internal {cmd:currentlawchecked} flag so subgroup workers reuse that
certified axis instead of rehashing the full-sample {cmd:e(treatsig)} inside
each preserved subgroup.

{pstd}
For {cmd:scatter}, the worker now follows the same narrow claimant rule used
elsewhere in the graph family: a certified {cmd:pte}/{cmd:pte_setup}
panel-time contract is preferred whenever setup metadata, live panel
metadata, or {cmd:e(predict)} is present, while a pure compatibility stub
that advertises only {cmd:e(cmd)="pte"} or only the bare treatment name
{cmd:e(treatment)} may still fall back to the legacy
{cmd:_pte_firm}/{cmd:_pte_year} bridge together with the current
{cmd:xtset}-published delta spacing. When a complete stored {cmd:pte_setup}
contract is present, that setup-selected panel spacing may also bridge a
missing live {cmd:e(xtdelta)} on the certified setup/live path; only genuine
setup/live {cmd:xtdelta} drift still fails closed with {cmd:rc=459}. The
live-only path is now stricter about incomplete claimants: if a live
{cmd:e(cmd)="pte"} result publishes any panel/time or law fragment beyond a
bare {cmd:e(treatment)} name—such as {cmd:e(idvar)}, {cmd:e(timevar)},
{cmd:e(treatsig)}, {cmd:e(xtdelta)}, or {cmd:e(predict)}—then it must also
publish the matching {cmd:e(treatment)} + {cmd:e(treatsig)} + panel/time
bundle. A treatsig-only claimant is therefore incomplete and fails closed
with {cmd:rc=459}, because the shared helper cannot recompute the current
signature from data without {cmd:e(treatment)}. A stale or partial live
claimant no longer falls back to
{cmd:xtset} or the legacy bridge. The
scatter sample itself is now
treated-only: the worker consumes only rows with the canonical TT bridge
{cmd:_pte_tt} on treated observations ({cmd:_pte_treat==1}) at the requested
event time {cmd:_pte_nt}. Control-side rows are ignored even if stale
nonmissing {cmd:_pte_tt} values survive in the dataset. A direct
{cmd:scatter} call is also law-first: when a stale live {cmd:e(treatsig)}
no longer matches the current dataset, both direct and {cmd:by()} scatter
routes now fail closed with {cmd:rc=459} instead of reusing stale
{cmd:_pte_tt}/{cmd:_pte_nt} timing objects. Public {cmd:by()} scatter now
re-certifies the current panel/treatment law once on the full dataset before
subgrouping, then reuses that certified axis inside each preserved subgroup.
This prevents subgroup-local rehashing of the full-sample live
{cmd:e(treatsig)} from falsely failing current-law calls with {cmd:rc=459}
while keeping stale live/setup law drift fail-closed at the wrapper entry. A
direct
{cmd:scatter} call now also requires the exact canonical productivity bridge
{cmd:_pte_omega}; shadow leftovers such as {cmd:_pte_omega_shadow} no longer
satisfy that contract through Stata abbreviation binding. Industry
normalization likewise uses only the exact canonical {cmd:_pte_industry}
variable. If that exact industry bridge is absent, the graph falls back to
the no-industry normalization law and the optional regstat FE replay reports
that the year-and-industry regression is unavailable instead of silently
binding to {cmd:_pte_industry_shadow}. A direct
{cmd:scatter} call also fails
closed when none of the requested {cmd:nt()} periods have any valid lagged
omega support; the worker must not report success with {cmd:r(nobs)=0} and no
current graph, because the by-wrapper would otherwise inherit a stale or
missing graph artifact for that subgroup. Public {cmd:by()} scatter now
re-certifies the current panel/treatment law once on the full dataset before
subgrouping, then reuses that certified axis inside each preserved subgroup.
This prevents subgroup-local rehashing of the full-sample live
{cmd:e(treatsig)} from falsely failing current-law calls with {cmd:rc=459}
while keeping stale live/setup law drift fail-closed at the wrapper entry.

{pstd}
For the shared {cmd:type(cdf)} and {cmd:type(kdensity)} diagnose path,
{cmd:_pte_treat} must remain binary and {cmd:_pte_nt} must remain an integer
event-time index. The worker now fails closed when either internal state
object is malformed, rather than silently rebuilding the treated/control
comparison window on corrupted state. A complete stored {cmd:pte_setup}
contract can also certify that calendar window when live {cmd:e(xtdelta)}
is missing; only true setup/live {cmd:xtdelta} drift still fails closed
with {cmd:rc=459}. The exact treated pre-treatment window and its matched
control calendar window must both be nonempty; if either side is empty, the
graph fails closed with {cmd:rc=2000} instead of drawing a one-sided
descriptive curve.

{pstd}
For {cmd:type(diff_omega0)}, the worker now keeps the graph on the treated
counterfactual path only. Residual control rows that still carry stale
{cmd:_pte_tt} or {cmd:_pte_nt} values are ignored rather than added as extra
event-time support, so {cmd:r(periods)} and {cmd:r(nobs)} reflect treated
observations only. The worker also now consumes the exact stored support in
{cmd:e(attperiods)}: default plotting uses only those certified event times,
{cmd:nt()} values outside that support fail closed with {cmd:rc=198}, and any
supported period with no live treated counterfactual path observations now
fails closed instead of warning and silently shrinking {cmd:r(periods)}.

{pstd}
For {cmd:tt}, the worker also consumes the exact stored support in
{cmd:e(attperiods)} rather than whichever treated rows happen to remain in
the dataset. If any requested or default supported event time has no
nonmissing treated {cmd:_pte_tt} observations, the graph now fails closed
with {cmd:rc=198} instead of warning, shrinking {cmd:r(periods)}, or
exporting a partial TT path.

{dlgtab:Diagnose subtype returns}

{pstd}
When the selected family is {cmd:diagnose}, returned fields depend on the
diagnostic subtype. For the shared {cmd:type(cdf)} and {cmd:type(kdensity)}
path, the worker returns {cmd:r(graph_type)} as {cmd:cdf_diagnose} or
{cmd:kdensity_diagnose}, plus {cmd:r(type)}, K-S summary fields
({cmd:r(ks_D)}, {cmd:r(ks_p)}), and group/sample summaries such as
{cmd:r(nobs_treated)} and {cmd:r(nobs_control)}. When {cmd:save()} is used,
the shared path also returns {cmd:r(filename)}; when {cmd:export()} is used,
it returns {cmd:r(export_file)}. For newer diagnose
subtypes, inspect {cmd:return list} for subtype-specific returns.

{pstd}
For {cmd:compare_cf}, the worker returns at least
{cmd:r(graph_type)=compare_cf}, {cmd:r(n_periods)}, and
{cmd:r(has_ci)}; file-output requests add {cmd:r(filename)} for
{cmd:save()} and {cmd:r(export_file)} for {cmd:export()}.

{pstd}
For {cmd:tt_distribution}, the worker returns at least
{cmd:r(type)=tt_distribution}, {cmd:r(graph_type)=tt_distribution}, and
{cmd:r(n_periods)}, together with the exact graphed support in
{cmd:r(periods)}; file-output requests add {cmd:r(filename)} and, for
exports, {cmd:r(export_file)}. For {cmd:eps0_diagnostic}, the worker
returns {cmd:r(graph_type)=eps0_diagnostic}, {cmd:r(has_treat)}, and file
paths when {cmd:save()} or {cmd:export()} is used.

{marker examples}{...}
{title:Examples}

{pstd}{bf:Default dynamic ATT graph after pte}{p_end}
{phang2}{cmd:. pte_graph}{p_end}

{pstd}{bf:Explicit ATT graph with custom titles}{p_end}
{phang2}{cmd:. pte_graph, att title("Dynamic ATT") xtitle("Event time") ytitle("ATT")}{p_end}

{pstd}{bf:Diagnostic graph route}{p_end}
{phang2}{cmd:. pte_graph, diagnose type(cdf)}{p_end}

{pstd}{bf:Placebo distribution diagnostic (requires reference value)}{p_end}
{phang2}{cmd:. pte_graph, diagnose type(placebo) coef(placebo_att) refval(0.12)}{p_end}

{pstd}{bf:By-group TT routing}{p_end}
{phang2}{cmd:. pte_graph, tt by(industry)}{p_end}

{pstd}{bf:TT distribution route}{p_end}
{phang2}{cmd:. pte_graph, tt_distribution}{p_end}

{pstd}{bf:Epsilon-zero diagnostic, Q-Q panel only}{p_end}
{phang2}{cmd:. pte_graph, eps0_diagnostic qqonly}{p_end}

{marker results}{...}
{title:Stored results}

{pstd}
{cmd:pte_graph} is an {cmd:rclass} wrapper. It usually forwards the selected
worker's {cmd:r()} results via {cmd:return add}. The exact returned fields
therefore depend on the graph family.

{pstd}
When {cmd:by()} routes to the by-group wrapper, the returned results also
include {cmd:r(by_var)}, {cmd:r(n_groups)}, {cmd:r(groups)},
{cmd:r(n_combined)}, {cmd:r(groups_plotted)}, and {cmd:r(graph_type)}. If a
combined graph is created, {cmd:r(cols)} and {cmd:r(rows)} are added, and
{cmd:r(save_file)} is reported when {cmd:save()} is used;
{cmd:r(export_file)} is reported when {cmd:export()} is used; and
{cmd:r(saveall_prefix)} is reported when {cmd:saveall()} is used. When the
underlying worker exposes one stable subtype identity across the generated
subgraphs, the by-group wrapper also preserves it in {cmd:r(type)}. For
example, {cmd:pte_graph, diagnose by(group) combine type(cdf)} returns
{cmd:r(graph_type)=diagnose} and {cmd:r(type)=cdf}.

{pstd}
For the {cmd:heterogeneity} family, the router additionally republishes
selected metadata when available:

{synoptset 28 tabbed}{...}
{p2col 5 28 32 2: Macros}{p_end}
{synopt:{cmd:r(graph_type)}}graph type reported by the heterogeneity
worker{p_end}
{synopt:{cmd:r(type)}}type reported by the heterogeneity worker{p_end}
{synopt:{cmd:r(filename)}}saved filename reported by the heterogeneity
worker{p_end}
{synopt:{cmd:r(by)}}grouping variable reported by the heterogeneity
worker{p_end}
{synopt:{cmd:r(group_labels)}}group-label payload reported by the heterogeneity
worker{p_end}
{p2col 5 28 32 2: Matrices}{p_end}
{synopt:{cmd:r(att_by)}}heterogeneity result matrix with columns
{cmd:ATT SE Contribution N}, matching the live Table 2 contract from
{helpb pte_heterogeneity}{p_end}

{pstd}
For all other families, inspect {cmd:return list} immediately after the
graph command to see the selected worker's published results.

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
PTE Stata Package Development Team
{p_end}
