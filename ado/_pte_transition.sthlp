{smcl}
{* *! version 1.0.0  01jan2026}{...}
{* *! US-E1-001: Transition Period Identification}{...}

{cmd:help _pte_transition}{right:PTE Package}
{hline}

{title:Title}

{p2colset 5 26 28 2}{...}
{p2col:{hi:_pte_transition} {hline 2} Transition Period Identification for PTE}{p_end}
{p2colreset}{...}


{title:Syntax}

{p 8 28 2}{cmd:_pte_transition}, {opt treat:ment(varname)} {opt id(varname)}
{opt time(varname)}
[{it:options}]

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{p2coldent:* {opt treat:ment(varname)}}binary treatment indicator variable
(0/1){p_end}
{p2coldent:* {opt id(varname)}}panel identifier variable{p_end}
{p2coldent:* {opt time(varname)}}time variable{p_end}

{syntab:Optional}
{synopt:{opt min:sample(#)}}minimum sample size for warnings; default is
{cmd:30}{p_end}
{synopt:{opt replace}}overwrite existing {cmd:_pte_mid}, {cmd:mid}, {cmd:G}, and
{cmd:mid_lag} variables{p_end}
{synopt:{opt norep:ort}}suppress the statistical report output{p_end}
{synopt:{opt touse(varname)}}exact numeric sample indicator; marks rows to
store/report while transition status still compares actual panel neighbors
{it:D_t} and {it:D_{t-1}} on the observed panel{p_end}
{synoptline}
{p 4 6 2}
Data must be {helpb xtset} as panel data before using
{cmd:_pte_transition}.{p_end}
{p 4 6 2}
{cmd:*} {opt treatment()}, {opt id()}, and {opt time()} are required.{p_end}


{title:Description}

{pstd}
{cmd:_pte_transition} identifies transition period observations in panel data
where the treatment status changes between consecutive periods
({it:D_t} {it:!=} {it:D_{t-1}}).  It generates indicator variables used by the
PTE package to exclude these observations from GMM estimation, as required by
Theorem 3.1 of Chen, Liao & Schurter (2026).

{pstd}
When {opt touse(varname)} is specified, the option marks rows to store/report.
It does {it:not} redefine the observed panel history used to compare
{it:D_t} and {it:D_{t-1}}.  The live helper still uses the actual panel
neighbors under the current {cmd:xtset} declaration and only materializes
generated variables and reported counts on the active {opt touse()} sample.

{pstd}
The command documents four related outputs.  The helper always generates
{cmd:_pte_mid}, {cmd:G}, and {cmd:mid_lag}, and it additionally creates
{cmd:mid} as a compatibility alias when that name is available:

{p 8 12 2}
{cmd:_pte_mid} {hline 2} primary transition period indicator.  {cmd:_pte_mid} =
1
if the treatment status changed from the previous period
({it:D_t != D_{t-1}}), and {cmd:_pte_mid} = 0 otherwise.  First-period
observations are set to 0.  Observations outside {opt touse()} are left
missing because their transition status is not materialized for the active
sample.

{p 8 12 2}
{cmd:mid} {hline 2} compatibility alias for {cmd:_pte_mid}.  When the name
{cmd:mid} is available, the helper creates a mirror copy for legacy scripts.
If the dataset already contains a user-owned {cmd:mid}, the helper preserves
that variable and only guarantees {cmd:_pte_mid}.

{p 8 12 2}
{cmd:G} {hline 2} treatment switch indicator (Paper Appendix C.3).
{cmd:G} = +1 if the firm enters treatment (0{it:->}1),
{cmd:G} = -1 if the firm exits treatment (1{it:->}0), and
{cmd:G} = 0 if the treatment status is unchanged.

{p 8 12 2}
{cmd:mid_lag} {hline 2} lagged transition period indicator.
{cmd:mid_lag} = {cmd:L._pte_mid} for non-first-period observations in the
active sample, and 0 for first-period observations with defined
{cmd:_pte_mid}.  This is an auxiliary variable and does not depend on whether
the legacy alias {cmd:mid} exists.

{pstd}
After generating the variables, the command verifies Assumption 3.3 (Data
Requirement) from the paper: there must exist consecutive untreated observations
({it:D_t = D_{t-1} = 0}) and consecutive treated observations
({it:D_t = D_{t-1} = 1}).  If either condition fails, the command exits with
error code 498.

{pstd}
The command supports both absorbing treatments ({it:D_t >= D_{t-1}}) and
non-absorbing treatments where firms can exit treatment ({it:D_t < D_{t-1}}),
as described in Appendix C.3 of the paper.


{title:Options}

{dlgtab:Required}

{phang}
{opt treatment(varname)} specifies the binary treatment indicator variable.
The variable must contain only values 0 and 1 (missing values are allowed
up to 10% of observations).  The name must match an existing variable
exactly; Stata abbreviation fallbacks such as {cmd:treatment(D)} matching
only {cmd:D_shadow} are rejected.

{phang}
{opt id(varname)} specifies the panel identifier variable (e.g., firm ID).
The name must match an existing variable exactly; abbreviation fallbacks such
as {cmd:id(firm)} matching only {cmd:firm_shadow} are rejected.

{phang}
{opt time(varname)} specifies the time variable (e.g., year).  The variable
must be numeric.  The name must also match an existing variable exactly;
abbreviation fallbacks such as {cmd:time(year)} matching only
{cmd:year_shadow} are rejected.

{dlgtab:Optional}

{phang}
{opt minsample(#)} sets the minimum sample size threshold for displaying
warnings about small stable observation counts.  If the number of stable
untreated or stable treated observations is below this threshold, a warning
is displayed but execution continues.  The default is {cmd:30}.  Setting
{cmd:minsample(0)} disables the warning.

{phang}
{opt replace} allows the command to overwrite existing {cmd:_pte_mid},
{cmd:mid}, {cmd:G}, and {cmd:mid_lag} variables.  Without this option, the
command exits with error 110 only if {cmd:_pte_mid}, {cmd:G}, or
{cmd:mid_lag} already exist.  A user-owned {cmd:mid} does not block the
command; in that case the helper preserves {cmd:mid} and only guarantees
{cmd:_pte_mid}.

{phang}
{opt noreport} suppresses the formatted statistical report that is displayed
by default after transition period identification.

{phang}
{opt touse(varname)} marks the active sample on which {_pte_mid}, {cmd:G},
{cmd:mid_lag}, and the reported statistics are materialized.  The command
still compares actual panel neighbors under the current {cmd:xtset}
declaration, so a sample-out observation may matter when it is the true
{it:t-1} neighbor of an active row.  The indicator must be numeric, and the
name must match an existing variable exactly; abbreviation fallbacks such as
{cmd:touse(keep)} matching only {cmd:keep_shadow} are rejected.


{title:Stored results}

{pstd}
{cmd:_pte_transition} stores the following in {cmd:r()}:

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:r(n_trans)}}number of transition period observations (excluded from
GMM){p_end}
{synopt:{cmd:r(n_trans_up)}}number of 0{it:->}1 transitions ({it:G = +1}){p_end}
{synopt:{cmd:r(n_trans_down)}}number of 1{it:->}0 transitions
({it:G = -1}){p_end}
{synopt:{cmd:r(n_stable_0)}}number of stable untreated observations
({it:D = D_{-1} = 0}){p_end}
{synopt:{cmd:r(n_stable_1)}}number of stable treated observations
({it:D = D_{-1} = 1}){p_end}
{synopt:{cmd:r(n_total)}}total number of active observations within
{opt touse()}; without {opt touse()}, this equals the full sample{p_end}
{synopt:{cmd:r(pct_excluded)}}percent of observations that are transition
periods{p_end}
{synopt:{cmd:r(n_lag_undefined)}}number of non-first observations with undefined
{it:D_{t-1}}{p_end}
{synopt:{cmd:r(n_trans_lag)}}number of lagged transition period
observations{p_end}
{p2colreset}{...}

{pstd}
The following identities hold among the stored results:

{p 8 12 2}
{cmd:r(n_trans)} = {cmd:r(n_trans_up)} + {cmd:r(n_trans_down)}

{p 8 12 2}
{cmd:r(pct_excluded)} = {cmd:r(n_trans)} / {cmd:r(n_total)} * 100

{p 8 12 2}
{cmd:r(n_lag_undefined)} counts non-first observations whose lagged treatment
status is undefined under the current {cmd:xtset} declaration (for example,
because the panel has a time gap).


{title:Generated variables}

{synoptset 14 tabbed}{...}
{synopt:{cmd:_pte_mid}}byte; primary transition period indicator (1 =
transition, 0 = stable, missing outside {opt touse()}){p_end}
{synopt:{cmd:mid}}byte; compatibility alias for {cmd:_pte_mid} when the name is
available{p_end}
{synopt:{cmd:G}}byte; switch indicator (-1 = exit, 0 = stable, +1 =
entry){p_end}
{synopt:{cmd:mid_lag}}byte; lagged transition period indicator{p_end}
{p2colreset}{...}


{title:Error codes}

{synoptset 10 tabbed}{...}
{synopt:{cmd:110}}variable {cmd:_pte_mid}, {cmd:G}, or {cmd:mid_lag} already
exists; use {opt replace}{p_end}
{synopt:{cmd:111}}specified treatment, id, time, or touse variable not found; or
time/touse is nonnumeric{p_end}
{synopt:{cmd:198}}invalid option value (e.g., negative {opt minsample()}){p_end}
{synopt:{cmd:416}}treatment variable has more than 10% missing values{p_end}
{synopt:{cmd:450}}treatment variable is not binary (0/1){p_end}
{synopt:{cmd:459}}data not {helpb xtset} as panel, or current {cmd:xtset} does
not match {opt id()} and {opt time()}{p_end}
{synopt:{cmd:498}}Assumption 3.3 violated: insufficient stable
observations{p_end}
{p2colreset}{...}


{title:Examples}

{pstd}Setup: create a simple panel dataset{p_end}

{phang2}{cmd:. clear}{p_end}
{phang2}{cmd:. input firm year D}{p_end}
{phang2}{cmd:. 1 2000 0}{p_end}
{phang2}{cmd:. 1 2001 0}{p_end}
{phang2}{cmd:. 1 2002 1}{p_end}
{phang2}{cmd:. 1 2003 1}{p_end}
{phang2}{cmd:. 2 2000 0}{p_end}
{phang2}{cmd:. 2 2001 0}{p_end}
{phang2}{cmd:. 2 2002 0}{p_end}
{phang2}{cmd:. 2 2003 1}{p_end}
{phang2}{cmd:. end}{p_end}
{phang2}{cmd:. xtset firm year}{p_end}

{pstd}Basic usage{p_end}
{phang2}{cmd:. _pte_transition, treatment(D) id(firm) time(year)}{p_end}
{phang2}{it:({stata `"clear"':clear}  {stata `"input firm year D"':setup}  {stata `"_pte_transition, treatment(D) id(firm) time(year)"':click to run})}{p_end}

{pstd}Overwrite existing variables{p_end}
{phang2}{cmd:. _pte_transition, treatment(D) id(firm) time(year) replace}{p_end}

{pstd}Custom minimum sample size warning threshold{p_end}
{phang2}{cmd:. _pte_transition, treatment(D) id(firm) time(year) replace minsample(50)}{p_end}

{pstd}Suppress the statistical report{p_end}
{phang2}{cmd:. _pte_transition, treatment(D) id(firm) time(year) replace noreport}{p_end}

{pstd}Inspect stored results{p_end}
{phang2}{cmd:. return list}{p_end}

{pstd}Use with replication data{p_end}
{phang2}{cmd:. use "data/复现数据.dta", clear}{p_end}
{phang2}{cmd:. _pte_transition, treatment(treat_post) id(firm) time(year)}{p_end}

{pstd}Verify transition period exclusion for GMM{p_end}
{phang2}{cmd:. count if _pte_mid == 1}{p_end}
{phang2}{cmd:. display "Observations excluded: " r(N)}{p_end}


{title:Theoretical background}

{pstd}
The transition period identification implements the CLK correction from
Chen, Liao & Schurter (2026).  The key insight is that when treatment status
changes ({it:D_t != D_{t-1}}), the productivity evolution depends on both
potential productivities ({it:omega^0} and {it:omega^1}), one of which is
unobservable.  Therefore, these observations cannot be used in the GMM moment
conditions (Equations 8-9 of the paper).

{pstd}
Specifically, Theorem 3.1 requires:

{p 8 12 2}
Moment condition (8):
{it:E[omega(beta) - h_0(omega_{t-1}(beta)) | Z, D_t = D_{t-1} = 0] = 0}

{p 8 12 2}
Moment condition (9):
{it:E[omega(beta) - h_1(omega_{t-1}(beta)) | Z, D_t = D_{t-1} = 1] = 0}

{pstd}
Both conditions require {it:D_t = D_{t-1}}, i.e., the exclusion of transition
periods.  Assumption 3.3 ensures that both types of stable observations exist
in the data for identification.


{title:References}

{phang}
Chen, X., Liao, Y., and Schurter, K. (2026).
Identifying Treatment Effects on Productivity.
{it:Working Paper}.
{p_end}
