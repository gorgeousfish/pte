{smcl}
{* *! version 1.0.0  20mar2026}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[R] estimates table" "help estimates_table"}{...}
{viewerjumpto "Syntax" "pte_esttab_att##syntax"}{...}
{viewerjumpto "Description" "pte_esttab_att##description"}{...}
{viewerjumpto "Remarks" "pte_esttab_att##remarks"}{...}
{viewerjumpto "Examples" "pte_esttab_att##examples"}{...}
{viewerjumpto "Stored results" "pte_esttab_att##results"}{...}
{viewerjumpto "Authors" "pte_esttab_att##authors"}{...}

{cmd:help pte_esttab_att}{right:also see: {helpb pte}}
{hline}

{title:Title}

{p2colset 5 28 30 2}{...}
{p2col:{cmd:pte_esttab_att} {hline 2}}Repost PTE ATT results in esttab-compatible form{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:pte_esttab_att}

{pstd}
{cmd:pte_esttab_att} takes no arguments or options. Run {cmd:pte} first, then call
{cmd:pte_esttab_att} on the active estimation results.


{marker description}{...}
{title:Description}

{pstd}
{cmd:pte_esttab_att} converts the ATT results left by {cmd:pte} into a
standard {cmd:e(b)} / {cmd:e(V)} estimation object that can be consumed by
table exporters such as {cmd:esttab}, {cmd:estout}, or Stata's built-in
{cmd:estimates table}.

{pstd}
The command is meant for postestimation reporting only. It does not re-run
the PTE estimator and it does not change the underlying ATT numbers. It
repackages the already-stored ATT path, its overall average, and any
available uncertainty information into a flat coefficient vector with a
matching variance matrix.

{pstd}
The reposted coefficient vector contains one coefficient for each stored ATT
period plus one final coefficient for the overall average ATT. Column names
follow the pattern {cmd:ATT_s0}, {cmd:ATT_s1}, ..., {cmd:ATT_avg}. When
{cmd:e(attperiods)} is present, {cmd:pte_esttab_att} uses that exact stored
integer event-time support. Sparse support such as {cmd:(0, 2)} is preserved
as {cmd:ATT_s0} and {cmd:ATT_s2}; malformed or fractional support is rejected.


{marker remarks}{...}
{title:Remarks}

{dlgtab:Preconditions}

{pstd}
{cmd:pte_esttab_att} requires active {cmd:pte} estimation results. If the
previous run used {cmd:noatt}, or otherwise did not leave ATT results in
{cmd:e()}, the command exits with an error.

{dlgtab:Bootstrap vs non-bootstrap results}

{pstd}
When bootstrap inference is available, {cmd:pte_esttab_att} uses the stored
bootstrap standard errors to build the diagonal entries of {cmd:e(V)}.
For pooled non-bootstrap results that still retain ATT uncertainty objects,
it falls back to those stored point-estimate quantities.

{pstd}
Grouped ATT results from {cmd:pte, by()} or {cmd:pte, industry()}
are not accepted. Those grouped public results keep a pooled summary in
{cmd:e(att)} alongside group-specific ATT payloads such as {cmd:e(att_by)}
or {cmd:e(att_by_point)}; grouped bootstrap reposts can also leave pooled
bootstrap summaries such as {cmd:e(att_se_pool)} / {cmd:e(att_mean_pool)}
and per-group payloads such as {cmd:e(att_boot_g#)} / {cmd:e(att_se_g#)} in
{cmd:e()}. {cmd:pte_esttab_att} only knows how to flatten one pooled ATT path
into {cmd:e(b)} / {cmd:e(V)}, so accepting grouped results would silently
drop cross-group heterogeneity. Re-run pooled {cmd:pte} results before
calling {cmd:pte_esttab_att}, or export the grouped matrices manually.

{pstd}
If {cmd:e(attperiods)} is posted as a matrix, it must be a strictly
increasing row vector of integer event times whose length matches the stored
dynamic ATT path. {cmd:pte_esttab_att} exits with {cmd:rc 198} when that
support contract is malformed.

{pstd}
The reposted {cmd:e(V)} is diagonal. {cmd:pte_esttab_att} is designed for
table display, not for downstream estimation that requires the full joint
covariance structure.

{dlgtab:Effect on active estimates}

{pstd}
After reposting, the active estimation command becomes {cmd:pte_att}. If you
need to return to the original {cmd:pte} result object, store it before
calling {cmd:pte_esttab_att} or re-run {cmd:pte}.


{marker examples}{...}
{title:Examples}

{pstd}{bf:Point-estimate ATT table}{p_end}
{phang2}{cmd:. pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D)}{p_end}
{phang2}{cmd:. pte_esttab_att}{p_end}
{phang2}{cmd:. estimates table, b se}{p_end}

{pstd}{bf:Bootstrap ATT table with esttab}{p_end}
{phang2}{cmd:. pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) bootstrap(200)}{p_end}
{phang2}{cmd:. pte_esttab_att}{p_end}
{phang2}{cmd:. esttab, se}{p_end}

{pstd}{bf:Preserve the original pte result first}{p_end}
{phang2}{cmd:. estimates store pte_main}{p_end}
{phang2}{cmd:. pte_esttab_att}{p_end}
{phang2}{cmd:. esttab, se}{p_end}
{phang2}{cmd:. estimates restore pte_main}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:pte_esttab_att} reposts an {cmd:eclass} estimation result with:

{synoptset 28 tabbed}{...}
{p2col 5 28 32 2: Matrices}{p_end}
{synopt:{cmd:e(b)}}1 x K coefficient vector with ATT-by-period coefficients and {cmd:ATT_avg}{p_end}
{synopt:{cmd:e(V)}}K x K diagonal variance matrix aligned with {cmd:e(b)}{p_end}

{p2col 5 28 32 2: Scalars}{p_end}
{synopt:{cmd:e(N)}}observation count copied from the active {cmd:pte} result, when available{p_end}

{p2col 5 28 32 2: Macros}{p_end}
{synopt:{cmd:e(cmd)}}{cmd:pte_att}{p_end}
{synopt:{cmd:e(title)}}title for the reposted ATT table object{p_end}


{marker authors}{...}
{title:Authors}

{pstd}
PTE Stata Package Development Team
{p_end}
