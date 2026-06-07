{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] pte_graph" "help pte_graph"}{...}
{viewerjumpto "Syntax" "_pte_cohort_ereturn##syntax"}{...}
{viewerjumpto "Description" "_pte_cohort_ereturn##description"}{...}
{viewerjumpto "Options" "_pte_cohort_ereturn##options"}{...}
{viewerjumpto "Stored results" "_pte_cohort_ereturn##results"}{...}
{title:Title}

{p2colset 5 36 38 2}{...}
{p2col:{bf:_pte_cohort_ereturn} {hline 2}}Store cohort ATT analysis results into e() return system{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 32 2}
{cmd:_pte_cohort_ereturn}
{cmd:,}
{opt att_cohort(matname)}
{opt att_cohort_se(matname)}
{opt att_pool(matname)}
{opt att_pool_se(matname)}
{opt cohort_list(matname)}
{opt cohort_sizes(matname)}
{opt attperiods(matname)}
{opt matchstrategy(string)}
[{it:options}]

{synoptset 28 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt att_cohort(matname)}}G x K matrix of cohort-specific ATT estimates on the exact supported event-time periods listed in {opt attperiods()}{p_end}
{synopt:{opt att_cohort_se(matname)}}G x K matrix of cohort-specific standard errors aligned with the exact supported event-time periods listed in {opt attperiods()}{p_end}
{synopt:{opt att_pool(matname)}}1 x K matrix of pooled ATT estimates aligned with the exact supported event-time periods listed in {opt attperiods()}{p_end}
{synopt:{opt att_pool_se(matname)}}1 x K matrix of pooled standard errors aligned with the exact supported event-time periods listed in {opt attperiods()}{p_end}
{synopt:{opt cohort_list(matname)}}G x 1 matrix of treatment cohort years{p_end}
{synopt:{opt cohort_sizes(matname)}}G x 1 matrix of cohort sample sizes{p_end}
{synopt:{opt attperiods(matname)}}1 x K row vector of exact supported ATT event-time periods{p_end}
{synopt:{opt matchstrategy(string)}}matching strategy: {it:notyettreated}, {it:nevertreated}, or {it:custom}{p_end}

{syntab:Optional - Heterogeneity}
{synopt:{opt het_Q(matname)}}1 x K row vector of Q test statistics aligned with the exact supported event-time periods{p_end}
{synopt:{opt het_Q_p(matname)}}1 x K row vector of Q test p-values aligned with the exact supported event-time periods{p_end}
{synopt:{opt het_I2(matname)}}1 x K row vector of I-squared heterogeneity shares aligned with the exact supported event-time periods{p_end}

{syntab:Optional - Bootstrap}
{synopt:{opt ci_cohort_l(matname)}}G x K lower CI bounds for cohort ATT aligned with the exact supported event-time periods{p_end}
{synopt:{opt ci_cohort_u(matname)}}G x K upper CI bounds for cohort ATT aligned with the exact supported event-time periods{p_end}
{synopt:{opt ci_pool_l(matname)}}1 x K lower CI bounds for pooled ATT aligned with the exact supported event-time periods{p_end}
{synopt:{opt ci_pool_u(matname)}}1 x K upper CI bounds for pooled ATT aligned with the exact supported event-time periods{p_end}
{synopt:{opt nboot(#)}}number of bootstrap replications; default is {cmd:0}{p_end}
{synopt:{opt boot_failed(#)}}number of failed bootstrap iterations; default is {cmd:0}{p_end}
{synopt:{opt boot_mode(string)}}bootstrap mode: {it:block} or {it:wild}{p_end}

{syntab:Optional - Meta}
{synopt:{opt matchexpr(string)}}custom matching expression (when matchstrategy is {it:custom}){p_end}
{synopt:{opt cmdline(string)}}original command line for replay{p_end}
{synopt:{opt nodisplay}}suppress formatted output table{p_end}
{synoptline}


{pstd}
The heterogeneity payload is a single Q-test family. If {opt het_Q_p()},
{opt het_I2()}, {opt het_Q_df()}, or {opt het_Q_G()} is supplied, then
{opt het_Q()} must also be supplied. Orphan sidecars are rejected.{p_end}

{pstd}
If {opt het_Q()} is supplied but {opt het_Q_df()} and/or {opt het_Q_G()} is
omitted, {cmd:_pte_cohort_ereturn} derives the missing support from the live
cohort ATT surface period by period. Columns with fewer than two valid
cohort ATT/SE pairs therefore post missing {cmd:e(df_Q_period)} entries and
their observed valid-cohort counts in {cmd:e(G_Q_period)}.{p_end}

{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_cohort_ereturn} is an internal command that stores cohort-specific
ATT (Average Treatment Effect on the Treated) analysis results into Stata's
{cmd:e()} return system. It is called by {cmd:_pte_cohort.ado} after completing
the cohort analysis loop.

{pstd}
The posted {opt matchstrategy()} metadata mirrors the live cohort-control
construction implemented upstream: {it:notyettreated} uses firms with
{it:e_i > g + l}, {it:nevertreated} uses only firms with {it:e_i = infinity},
and {it:custom} records a caller-supplied control definition through
{opt matchexpr()}.

{pstd}
The command performs the following steps:

{phang2}1. Validates input matrix dimensions and values{p_end}
{phang2}2. Sets row names (cohort years) and exact-support column names from {cmd:attperiods()} (for example, {cmd:nt0 nt2 nt5}){p_end}
{phang2}3. Constructs {cmd:e(b)} and {cmd:e(V)} for {cmd:esttab}/{cmd:outreg2} compatibility{p_end}
{phang2}4. Posts estimation results via {cmd:ereturn post}{p_end}
{phang2}5. Stores all matrices, scalars, and locals{p_end}
{phang2}6. Displays a formatted output table (unless {opt nodisplay} is specified){p_end}

{pstd}
Matrix dimensions: G = number of cohorts, K = number of exact supported ATT
event-time periods listed in {cmd:attperiods()} (including {cmd:nt0} when the
instantaneous effect is supported).

{pstd}
If any CI option is supplied, {cmd:ci_cohort_l()}, {cmd:ci_cohort_u()},
{cmd:ci_pool_l()}, and {cmd:ci_pool_u()} must all be supplied together.
When the full CI family is present, the four CI matrices are posted to {cmd:e()}
even if {cmd:nboot()} metadata is omitted.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_cohort_ereturn} stores the following in {cmd:e()}:

{synoptset 24 tabbed}{...}
{p2col 5 24 28 2: Matrices}{p_end}
{synopt:{cmd:e(b)}}1 x K pooled ATT vector (colnames follow {cmd:e(attperiods)}, e.g. {cmd:ATT_0 ATT_2}){p_end}
{synopt:{cmd:e(V)}}K x K diagonal variance matrix (SE^2 on diagonal; dimnames follow the same exact-support ATT labels as {cmd:e(b)}){p_end}
{synopt:{cmd:e(att_cohort)}}G x K cohort-specific ATT estimates aligned with the exact supported event-time periods in {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(att_cohort_se)}}G x K cohort-specific standard errors aligned with the exact supported event-time periods in {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(att_pool)}}1 x K pooled ATT estimates aligned with the exact supported event-time periods in {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(att_pool_se)}}1 x K pooled standard errors aligned with the exact supported event-time periods in {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(cohort_list)}}G x 1 treatment cohort years{p_end}
{synopt:{cmd:e(cohort_sizes)}}G x 1 cohort sample sizes{p_end}
{synopt:{cmd:e(cohort_het_Q)}}1 x K Q heterogeneity test statistics aligned with {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(cohort_het_p)}}1 x K Q test p-values aligned with {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(cohort_het_I2)}}1 x K I-squared heterogeneity shares aligned with {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(df_Q_period)}}1 x K period-specific Q-test degrees of freedom aligned with {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(G_Q_period)}}1 x K period-specific valid cohort counts for the Q test aligned with {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(attperiods)}}1 x K row vector of exact supported ATT event-time periods{p_end}
{synopt:{cmd:e(att_cohort_ci_l)}}G x K lower CI bounds when a full CI family is supplied, aligned with {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(att_cohort_ci_u)}}G x K upper CI bounds when a full CI family is supplied, aligned with {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(att_pool_ci_l)}}1 x K pooled lower CI bounds when a full CI family is supplied, aligned with {cmd:e(attperiods)}{p_end}
{synopt:{cmd:e(att_pool_ci_u)}}1 x K pooled upper CI bounds when a full CI family is supplied, aligned with {cmd:e(attperiods)}{p_end}

{p2col 5 24 28 2: Scalars}{p_end}
{synopt:{cmd:e(n_cohorts)}}number of treatment cohorts (G){p_end}
{synopt:{cmd:e(df_Q)}}scalar Q-test degrees of freedom when constant across periods; missing otherwise{p_end}
{synopt:{cmd:e(G_Q)}}scalar valid cohort count for the Q test when constant across periods; missing otherwise{p_end}
{synopt:{cmd:e(nboot)}}number of bootstrap replications (bootstrap only){p_end}
{synopt:{cmd:e(boot_failed)}}number of failed bootstrap iterations (bootstrap only){p_end}

{p2col 5 24 28 2: Macros}{p_end}
{synopt:{cmd:e(cmd)}}{cmd:pte}{p_end}
{synopt:{cmd:e(cmdline)}}original command line{p_end}
{synopt:{cmd:e(matchstrategy)}}matching strategy used{p_end}
{synopt:{cmd:e(matchexpr)}}custom matching expression (if applicable){p_end}
{synopt:{cmd:e(boot_mode)}}bootstrap mode (bootstrap only){p_end}


{title:Error codes}

{synoptset 12 tabbed}{...}
{synopt:E-3011}No ATT estimates available (empty matrix){p_end}
{synopt:E-3013}Matrix dimension mismatch between input matrices{p_end}
{synopt:E-3015}All bootstrap iterations failed{p_end}
{synopt:E-3016}Negative standard error values detected{p_end}


{title:References}

{pstd}
Chen, X., Liao, Z. and Schurter, K. (2026). Productivity Treatment Effects.
{it:Working Paper}.

{pstd}
Section 4.3 (ATT definition), Appendix C.2 (Q heterogeneity test).
{p_end}
