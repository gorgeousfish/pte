{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] _pte_bygroup" "help _pte_bygroup"}{...}
{viewerjumpto "Syntax" "_pte_switch_indicator##syntax"}{...}
{viewerjumpto "Description" "_pte_switch_indicator##description"}{...}
{viewerjumpto "Options" "_pte_switch_indicator##options"}{...}
{viewerjumpto "Generated variables" "_pte_switch_indicator##generated"}{...}
{viewerjumpto "Stored results" "_pte_switch_indicator##results"}{...}
{viewerjumpto "Examples" "_pte_switch_indicator##examples"}{...}
{viewerjumpto "References" "_pte_switch_indicator##references"}{...}
{title:Title}

{p2colset 5 38 40 2}{...}
{p2col:{cmd:_pte_switch_indicator} {hline 2}}Generate treatment switch indicators for non-absorbing treatment{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 35 2}
{cmd:_pte_switch_indicator}
{cmd:,}
{cmdab:treat:ment(}{varname}{cmd:)}
{cmdab:id(}{varname}{cmd:)}
{cmdab:time(}{varname}{cmd:)}
[{it:options}]

{synoptset 25 tabbed}{...}
{synopthdr}
{synoptline}
{p2coldent:* {opt treat:ment(varname)}}binary treatment variable on observed rows (0/1); missing values are allowed and yield locally undefined switch states; the supplied name must match an existing variable exactly{p_end}
{p2coldent:* {opt id(varname)}}panel identifier variable; the supplied name must match an existing variable exactly{p_end}
{p2coldent:* {opt time(varname)}}numeric time variable; the supplied name must match an existing variable exactly{p_end}
{synopt:{opt replace}}replace existing generated variables{p_end}
{synopt:{opt noreport}}suppress the statistics report{p_end}
{synoptline}
{p 4 6 2}* Required options.{p_end}
{p 4 6 2}Data must be {cmd:xtset} before calling this command, and the current {cmd:xtset} declaration must match the exact names supplied in {opt id()} and {opt time()}.{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_switch_indicator} generates treatment switch indicators for
non-absorbing treatment settings as defined in Appendix C.3 of
Chen, Liao & Schurter (2026). The command identifies treatment entry
events (0 to 1 transitions), exit events (1 to 0 transitions), and
computes relative time measures needed for ATT+ and ATT- estimation.

{pstd}
The core switch indicator is defined as:

{p 8 8 2}
G_it = sign(D_it - D_{it-1})

{pstd}
where G = +1 indicates treatment entry, G = -1 indicates treatment exit,
and G = 0 indicates no change. The true first {cmd:xtset} row of each
panel unit is set to G = 0. If the true adjacent-period
lag D_{t-1} is undefined under the current {cmd:xtset} declaration
(for example, because of a panel gap), the row has an undefined D_{t-1}
and G will remain missing rather than being coerced to 0.

{pstd}
For absorbing treatments (where treatment is never reversed), this command
produces results equivalent to the standard {cmd:mid} transition indicator
used in EPIC-001.


{marker options}{...}
{title:Options}

{phang}
{opt treatment(varname)} specifies the binary treatment variable. Nonmissing
values must be 0 or 1, and the supplied name must match an existing
variable exactly. Missing treatment values are allowed; any row whose
current treatment or true adjacent lagged treatment is undefined simply
receives missing switch-state outputs instead of forcing the whole command
to fail. Abbreviation fallback such as {cmd:treatment(D)} matching only
{cmd:D_shadow} is rejected.

{phang}
{opt id(varname)} specifies the panel identifier variable. The supplied
name must match an existing variable exactly.

{phang}
{opt time(varname)} specifies the numeric time variable. The supplied name
must match an existing variable exactly.

{phang}
{opt replace} allows the command to replace existing variables named
{cmd:G}, {cmd:_last_entry_yr}, {cmd:_last_exit_yr}, {cmd:nt_plus},
{cmd:nt_minus}, and {cmd:n_switch}.

{phang}
{opt noreport} suppresses the switch event statistics report.


{marker generated}{...}
{title:Generated variables}

{synoptset 20 tabbed}{...}
{synopt:{cmd:G}}switch indicator: +1 = entry, -1 = exit, 0 = stay; remains missing when the current row or true adjacent lag D_{t-1} is undefined{p_end}
{synopt:{cmd:_last_entry_yr}}most recent treatment entry year; remains missing until an observed entry occurs and resets to missing when a later row breaks the observed treated path{p_end}
{synopt:{cmd:_last_exit_yr}}most recent treatment exit year; remains missing until an observed exit occurs and resets to missing when a later row breaks the observed untreated path{p_end}
{synopt:{cmd:nt_plus}}relative time since last entry (for ATT+); defined only when D=1 and an observed uninterrupted treated history exists since that entry{p_end}
{synopt:{cmd:nt_minus}}relative time since last exit (for ATT-); defined only when D=0 and an observed uninterrupted untreated history exists since that exit{p_end}
{synopt:{cmd:n_switch}}cumulative number of treatment switches{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_switch_indicator} stores the following in {cmd:r()}:

{synoptset 25 tabbed}{...}
{p2col 5 25 29 2: Scalars}{p_end}
{synopt:{cmd:r(n_entry)}}number of entry events (G = +1){p_end}
{synopt:{cmd:r(n_exit)}}number of exit events (G = -1){p_end}
{synopt:{cmd:r(n_stay)}}number of stay events (G = 0){p_end}
{synopt:{cmd:r(n_firms_entry)}}number of firms with at least one entry{p_end}
{synopt:{cmd:r(n_firms_exit)}}number of firms with at least one exit{p_end}
{synopt:{cmd:r(n_multi_switch)}}number of firms with multiple switches{p_end}
{synopt:{cmd:r(max_switches)}}maximum number of switches across all firms{p_end}
{synopt:{cmd:r(n_consecutive)}}number of consecutive switch events{p_end}


{marker examples}{...}
{title:Examples}

{pstd}Setup: absorbing treatment{p_end}
{phang2}{cmd:. webuse nlswork, clear}{p_end}
{phang2}{cmd:. xtset idcode year}{p_end}
{phang2}{cmd:. gen byte D = (year >= 80)}{p_end}
{phang2}{cmd:. _pte_switch_indicator, treatment(D) id(idcode) time(year)}{p_end}

{pstd}Setup: non-absorbing treatment{p_end}
{phang2}{cmd:. clear}{p_end}
{phang2}{cmd:. input fid year D}{p_end}
{phang2}{cmd:. 1 2000 0}{p_end}
{phang2}{cmd:. 1 2001 1}{p_end}
{phang2}{cmd:. 1 2002 0}{p_end}
{phang2}{cmd:. 1 2003 1}{p_end}
{phang2}{cmd:. end}{p_end}
{phang2}{cmd:. xtset fid year}{p_end}
{phang2}{cmd:. _pte_switch_indicator, treatment(D) id(fid) time(year)}{p_end}
{phang2}{cmd:. list fid year D G nt_plus nt_minus n_switch}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z. & Schurter, K. (2026).
Productivity Treatment Effects.
{it:Working Paper}, Appendix C.3, Lines 847-883.
{p_end}
{smcl}
