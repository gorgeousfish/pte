{smcl}
{* *! version 1.0.0  01jan2026}{...}
{viewerjumpto "Syntax" "_pte_graph_att_nonabs##syntax"}{...}
{viewerjumpto "Description" "_pte_graph_att_nonabs##description"}{...}
{viewerjumpto "Options" "_pte_graph_att_nonabs##options"}{...}
{viewerjumpto "Examples" "_pte_graph_att_nonabs##examples"}{...}
{viewerjumpto "Stored results" "_pte_graph_att_nonabs##results"}{...}
{viewerjumpto "References" "_pte_graph_att_nonabs##references"}{...}
{title:Title}

{p2colset 5 35 37 2}{...}
{p2col:{cmd:_pte_graph_att_nonabs} {hline 2}}Non-absorbing dual ATT graph (internal){p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_graph_att_nonabs}
[{cmd:,} {it:options}]

{pstd}
This is an internal program called by {cmd:pte_graph} after estimation with
the {opt nonabsorbing} option. Users should call {cmd:pte_graph} rather than
this program directly.

{synoptset 32 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Graph type}
{synopt:{opt ov:erlay}}overlay ATT{sup:+} and ATT{sup:-} on same axes{p_end}
{synopt:{opt attdiff}}plot ATT{sup:+} minus ATT{sup:-} difference{p_end}
{synopt:{opt abs:orbing}}handle absorbing treatment case (ATT{sup:+} only){p_end}

{syntab:Confidence intervals}
{synopt:{opt ci(type)}}CI display: {bf:area} (default), {bf:rcap}, {bf:rspike}, or {bf:none}{p_end}
{synopt:{opt le:vel(#)}}confidence level; default is {cmd:level(95)}{p_end}

{syntab:Colors and styles}
{synopt:{opt colorp:lus(color)}}ATT{sup:+} line color; default {bf:navy}{p_end}
{synopt:{opt colorm:inus(color)}}ATT{sup:-} line color; default {bf:maroon}{p_end}
{synopt:{opt colord:iff(color)}}difference line color; default {bf:forest_green}{p_end}
{synopt:{opt lpatternp:lus(pattern)}}ATT{sup:+} line pattern; default {bf:solid}{p_end}
{synopt:{opt lpatternm:inus(pattern)}}ATT{sup:-} line pattern; default {bf:solid}{p_end}
{synopt:{opt lw:idth(#)}}line width; default {bf:0.8}{p_end}
{synopt:{opt msymbolp:lus(symbol)}}ATT{sup:+} marker symbol; default {bf:O}{p_end}
{synopt:{opt msymbolm:inus(symbol)}}ATT{sup:-} marker symbol; default {bf:D}{p_end}
{synopt:{opt ms:ize(#)}}marker size; default {bf:2.5}{p_end}

{syntab:Titles and labels}
{synopt:{opt ti:tle(string)}}graph title{p_end}
{synopt:{opt xti:tle(string)}}x-axis title; default "Periods Since Treatment (n{sub:t})"{p_end}
{synopt:{opt yti:tle(string)}}y-axis title; default "ATT"{p_end}
{synopt:{opt sub:title(string)}}graph subtitle{p_end}
{synopt:{opt note(string)}}graph note{p_end}
{synopt:{opt legend(string)}}legend specification override{p_end}
{synopt:{opt sc:heme(string)}}graph scheme; default {bf:s2color}{p_end}

{syntab:Output}
{synopt:{opt sa:ve(filename)}}save graph as {it:filename}.gph{p_end}
{synopt:{opt ex:port(format)}}export graph as png, pdf, or eps{p_end}
{synopt:{opt w:idth(#)}}export width in pixels; default {bf:800}{p_end}
{synopt:{opt h:eight(#)}}export height in pixels; default {bf:600}{p_end}
{synopt:{opt tab:le}}display numerical summary table{p_end}
{synoptline}

{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_graph_att_nonabs} generates graphs for non-absorbing treatment
effects estimated by {cmd:pte} with the {opt nonabsorbing} option. It reads
ATT{sup:+} (entry effects) and ATT{sup:-} (exit effects) from {cmd:e()}
results and produces one of three graph types:

{p 8 12 2}1. {bf:Dual panel} (default): side-by-side panels showing ATT{sup:+} and
ATT{sup:-} with aligned y-axes for direct comparison.{p_end}

{p 8 12 2}2. {bf:Overlay} ({opt overlay}): both ATT{sup:+} and ATT{sup:-} plotted on
the same axes with distinct colors and markers.{p_end}

{p 8 12 2}3. {bf:Difference} ({opt attdiff}): ATT{sup:+} minus ATT{sup:-}, testing
whether entry and exit effects are symmetric. A zero line indicates
symmetric effects.{p_end}

{pstd}
The program requires prior estimation via {cmd:pte} with the
{opt nonabsorbing} option. It expects the matrices {cmd:e(att_plus)} and
{cmd:e(att_minus)} to be available. When helper-produced bootstrap CI bounds
({cmd:e(att_plus_ci_lower/upper)} and {cmd:e(att_minus_ci_lower/upper)}) are
present, the graph reuses those stored percentile intervals directly. When the
main ATT payload also posts explicit {cmd:nt} support, those four CI matrices
must carry the same canonical {cmd:nt#} labels; support-drifting bootstrap CI
payloads now fail closed instead of being remapped by row order. If no
bootstrap CI bundle is posted but ATT standard errors are present
({cmd:e(att_plus_se)} and {cmd:e(att_minus_se)}), confidence intervals fall
back to the usual normal-approximation construction. The live consumer also
accepts helper-produced {cmd:e(cmd)=_pte_bootstrap_nonabs} result bundles when
those matrices are already posted, and it accepts the ATT standard-error
payload either as an {it:N}x1 column vector or a 1x{it:N} row vector covering
the plotted horizon. If the main ATT payload remains a pure one-column vector,
auxiliary helper/bootstrap/SE payloads may omit support labels or use only the
same fallback dense {cmd:nt0 nt1 ...} route implied by row order; orphan
drifting {cmd:nt#} sidecar labels now fail closed instead of being bridged to
the fallback dense 0,1,2,... horizon. If that one-column main payload itself
publishes nt-like rownames, they must equal the same fallback dense route
exactly; sparse or drifting main-payload rownames now fail closed instead of
being silently ignored. When {cmd:e(att_plus)} / {cmd:e(att_minus)} publish an
explicit {cmd:nt} column, the graph preserves that posted event-time support
and any side SE matrices used for normal-approximation CI must publish the
same canonical {cmd:nt#} labels on their rownames or colnames; unlabeled or
default-position side SE payloads now fail closed instead of being consumed by
position while the graph preserves the posted event-time support on the x-axis.
The main ATT payload must therefore be either a pure ATT vector (one column)
or the exact canonical four-column producer contract
{cmd:[ATT, SD, N, nt]}. The live consumer now fail-closes on partial two- or
three-column payloads, reordered four-column payloads, and orphan extra
columns. When that canonical four-column contract is used, the posted
{cmd:nt} support must also be strictly increasing, unique, and reflected in
the matrix rownames ({cmd:nt0 nt1 ...}) row by row. These malformed bundles
would otherwise silently repurpose sample counts, stale row routes, or unsorted
state as event-time support.

{pstd}
For the difference plot, bootstrap-based SE for the difference
({cmd:e(att_diff_se_boot)}) is preferred when available. The graph accepts
that payload either as an {it:N}x1 column vector or a 1x{it:N} row vector.
When {cmd:e(att_plus)} / {cmd:e(att_minus)} post canonical {cmd:nt} support,
the direct difference-SE payload must carry the same canonical {cmd:nt#}
labels on its rownames or colnames; support-drifting direct difference SE now
fails closed instead of being consumed by position.
When the helper instead exposes matched raw bootstrap draw matrices
({cmd:e(att_plus_boot)} and {cmd:e(att_minus_boot)}), the graph derives the
paired ATT{sup:+}-ATT{sup:-} bootstrap distribution directly and reuses its
percentile interval. This difference-CI path is rendered even if the live
state has no side-specific {cmd:e(att_plus_se)} / {cmd:e(att_minus_se)} or
side bootstrap CI matrices. Those helper draw matrices must be posted as a
matched pair with the same canonical {cmd:nt#} column names used by the live
{cmd:e(att_plus)} / {cmd:e(att_minus)} horizon support; malformed or support-
drifting helper draw bundles fail closed. Only when no bootstrap difference
payload is recoverable does the graph fall back to a delta-method
approximation (assuming independence).

{marker options}{...}
{title:Options}

{dlgtab:Graph type}

{phang}
{opt overlay} plots ATT{sup:+} and ATT{sup:-} on the same axes instead of
the default dual-panel layout. ATT{sup:+} uses a solid line and ATT{sup:-}
uses a dashed line by default.

{phang}
{opt attdiff} plots the difference ATT{sup:+} - ATT{sup:-} across periods.
This is useful for testing whether entry and exit effects are symmetric.
A horizontal zero line is drawn for reference.

{phang}
{opt absorbing} handles the absorbing treatment case where only ATT{sup:+}
is available. This option is set automatically by {cmd:pte_graph} when
appropriate.

{dlgtab:Confidence intervals}

{phang}
{opt ci(type)} specifies how confidence intervals are displayed.
{opt area} (the default) draws shaded regions; {opt rcap} draws capped
range bars; {opt rspike} draws spike lines; {opt none} suppresses CIs.
If no standard errors are available, CIs are suppressed regardless of
this setting.

{phang}
{opt level(#)} specifies the confidence level as a percentage.
Default is {cmd:level(95)}.

{dlgtab:Colors and styles}

{phang}
{opt colorplus(color)} sets the color for ATT{sup:+} lines, markers, and
CI regions. Default is {bf:navy}. Any valid Stata color is accepted.

{phang}
{opt colorminus(color)} sets the color for ATT{sup:-} lines, markers, and
CI regions. Default is {bf:maroon}.

{phang}
{opt colordiff(color)} sets the color for the difference line in
{opt attdiff} mode. Default is {bf:forest_green}.

{phang}
{opt lpatternplus(pattern)} and {opt lpatternminus(pattern)} set line
patterns for ATT{sup:+} and ATT{sup:-} respectively. Default is {bf:solid}
for both. In overlay mode, ATT{sup:-} automatically uses {bf:dash}.

{phang}
{opt lwidth(#)} sets the line width. Default is {bf:0.8}.

{phang}
{opt msymbolplus(symbol)} and {opt msymbolminus(symbol)} set marker symbols.
Defaults are {bf:O} (circle) for ATT{sup:+} and {bf:D} (diamond) for
ATT{sup:-}.

{phang}
{opt msize(#)} sets the marker size. Default is {bf:2.5}.

{dlgtab:Titles and labels}

{phang}
{opt title(string)} overrides the default graph title. Defaults vary by
graph type: "Non-absorbing Treatment Effects" (dual),
"ATT{sup:+} and ATT{sup:-} (Overlay)" (overlay), or
"Difference in Treatment Effects" (attdiff).

{phang}
{opt xtitle(string)} sets the x-axis title. Default is
"Periods Since Treatment (n{sub:t})".

{phang}
{opt ytitle(string)} sets the y-axis title. Default is "ATT".
In {opt attdiff} mode, the default is "ATT{sup:+} - ATT{sup:-}".

{phang}
{opt subtitle(string)}, {opt note(string)}, and {opt legend(string)}
override the respective graph elements. The {opt legend()} option
overrides the automatically generated legend in overlay mode.

{phang}
{opt scheme(string)} sets the graph scheme. Default is {bf:s2color}.

{dlgtab:Output}

{phang}
{opt save(filename)} saves the graph as {it:filename}.gph.

{phang}
{opt export(format)} exports the graph in the specified format.
Supported formats are {bf:png}, {bf:pdf}, and {bf:eps}. The filename
is taken from {opt save()} if specified, otherwise defaults to
"pte_att_nonabs".

{phang}
{opt width(#)} and {opt height(#)} set the export dimensions in pixels.
Defaults are 800 x 600. These apply only to PNG export.

{phang}
{opt table} displays a numerical summary table alongside the graph,
showing ATT estimates, standard errors, and confidence intervals for
each period. In {opt attdiff} mode, the difference and its SE are also
shown.

{marker examples}{...}
{title:Examples}

{pstd}Setup: estimate non-absorbing treatment effects{p_end}
{phang2}{cmd:. pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) nonabsorbing}{p_end}

{pstd}Default dual-panel graph{p_end}
{phang2}{cmd:. pte_graph}{p_end}

{pstd}Overlay graph with custom colors{p_end}
{phang2}{cmd:. pte_graph, overlay colorplus(blue) colorminus(red)}{p_end}

{pstd}Difference plot with numerical table{p_end}
{phang2}{cmd:. pte_graph, attdiff table}{p_end}

{pstd}Export to PNG with custom dimensions{p_end}
{phang2}{cmd:. pte_graph, save(my_graph) export(png) width(1200) height(800)}{p_end}

{pstd}Suppress confidence intervals{p_end}
{phang2}{cmd:. pte_graph, ci(none)}{p_end}

{pstd}90% confidence intervals with spike display{p_end}
{phang2}{cmd:. pte_graph, ci(rspike) level(90)}{p_end}

{pstd}Direct internal call (not recommended){p_end}
{phang2}{cmd:. _pte_graph_att_nonabs, overlay attdiff table}{p_end}

{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_graph_att_nonabs} stores the following in {cmd:r()}:

{synoptset 28 tabbed}{...}
{p2col 5 28 32 2: Scalars}{p_end}
{synopt:{cmd:r(n_periods)}}number of periods plotted{p_end}
{synopt:{cmd:r(ci_level)}}confidence level used{p_end}

{p2col 5 28 32 2: Macros}{p_end}
{synopt:{cmd:r(graph_type)}}graph type: {bf:dual}, {bf:overlay}, or {bf:att_diff}{p_end}
{synopt:{cmd:r(filename)}}saved filename (if {opt save()} specified){p_end}
{synopt:{cmd:r(diff_se_method)}}SE method for difference: {bf:bootstrap}, {bf:delta}, or {bf:none} (attdiff mode only){p_end}
{synopt:{cmd:r(diff_ci_source)}}CI source for difference: {bf:bootstrap}, {bf:normal}, or {bf:none} (attdiff mode only){p_end}

{p2col 5 28 32 2: Matrices}{p_end}
{synopt:{cmd:r(att_plus)}}ATT{sup:+} estimates vector{p_end}
{synopt:{cmd:r(att_minus)}}ATT{sup:-} estimates vector{p_end}
{synopt:{cmd:r(nt)}}event-time support used on the x-axis{p_end}
{synopt:{cmd:r(att_diff)}}ATT{sup:+} - ATT{sup:-} difference vector (attdiff mode only){p_end}
{synopt:{cmd:r(att_diff_se)}}difference SE vector (attdiff mode, if SE available){p_end}
{synopt:{cmd:r(att_diff_ci_lower)}}difference CI lower bound (attdiff mode, if CI available){p_end}
{synopt:{cmd:r(att_diff_ci_upper)}}difference CI upper bound (attdiff mode, if CI available){p_end}

{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z. & Schurter, K. (2026).
Productivity Treatment Effects.
{it:Working Paper}. Section 4.4 (Non-absorbing Treatment),
Proposition 4.3 (ATT Estimation).
{p_end}

{title:Also see}

{psee}
{space 2}Help:  {help pte_graph:pte_graph}, {help pte:pte}
{p_end}
