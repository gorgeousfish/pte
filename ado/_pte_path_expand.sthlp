{smcl}
{* *! version 1.0.0  01jan2026}{...}
{* *! US-E3-001: Path Expansion for Monte Carlo Simulation}{...}

{vieweralsosee "" "--"}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] _pte_att" "help _pte_att"}{...}
{vieweralsosee "[PTE] _pte_omega_recovery" "help _pte_omega_recovery"}{...}
{viewerjumpto "Syntax" "_pte_path_expand##syntax"}{...}
{viewerjumpto "Description" "_pte_path_expand##description"}{...}
{viewerjumpto "Options" "_pte_path_expand##options"}{...}
{viewerjumpto "Generated variables" "_pte_path_expand##generated"}{...}
{viewerjumpto "Stored results" "_pte_path_expand##results"}{...}
{viewerjumpto "Examples" "_pte_path_expand##examples"}{...}
{viewerjumpto "References" "_pte_path_expand##references"}{...}

{cmd:help _pte_path_expand}{right:PTE Package}
{hline}

{title:Title}

{p2colset 5 28 30 2}{...}
{p2col:{hi:_pte_path_expand} {hline 2} Path Expansion for Monte Carlo Simulation}{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 32 2}{cmd:_pte_path_expand}, {opt firm(varname)} {opt nt(varname)}
[{it:options}]

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{p2coldent:* {opt firm(varname)}}firm identifier variable{p_end}
{p2coldent:* {opt nt(varname)}}time variable (relative to treatment year){p_end}

{syntab:Optional}
{synopt:{opt nsim(#)}}number of simulation paths; default determined by
{opt omegapoly()}{p_end}
{synopt:{opt omegapoly(#)}}omega evolution polynomial order; default from
{cmd:e(omegapoly)} or 3{p_end}
{synopt:{opt treatment(varname)}}treatment indicator used to identify
ever-treated ATT firms; if omitted, the helper auto-detects
{cmd:_pte_treat_group}, {cmd:treat_post}, {cmd:treat}, or {cmd:D} before
assuming the current data are already treated-only{p_end}
{synoptline}
{p 4 6 2}
{cmd:*} {opt firm()} and {opt nt()} are required.{p_end}
{p 4 6 2}
{opt omegapoly()} may be supplied explicitly. If it is omitted,
{cmd:_pte_path_expand} first tries {cmd:e(omegapoly)} from the current
estimation results and otherwise falls back to 3. Prior EPIC-002 output is
therefore a typical upstream source of metadata, not a hard prerequisite for
running the helper itself.{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_path_expand} expands panel data into multiple Monte Carlo simulation
paths for counterfactual productivity estimation.  In the Proposition 4.3 ATT
workflow, only the treated ATT sample should be replicated: treated firms
receive {it:nsim} counterfactual paths, while untreated/control observations
remain single-copy because they identify the untreated innovation law rather
than receiving simulated post-treatment paths themselves. The helper therefore
replicates ever-treated firms only when a treatment indicator is supplied or
auto-detected; if no treatment variable can be found, it assumes the current
data are already restricted to the treated ATT sample.

{pstd}
The command performs the following steps:

{phang2}1. Determines {opt nsim} using the smart default rule based on
{opt omegapoly}, or uses the user-specified value.{p_end}

{phang2}2. Expands the treated ATT rows using Stata's {cmd:expand} command,
leaving untreated/control rows at one copy.{p_end}

{phang2}3. Generates {cmd:copy_id} (path index within each firm-time cell)
and {cmd:firm_sim_id} (globally unique path identifier).{p_end}

{phang2}4. Re-issues {cmd:tsset firm_sim_id {it:nt}} so that lag operators
(e.g., {cmd:L.omega}) operate correctly within each simulation path.{p_end}

{phang2}5. Validates the expansion: observation count, {cmd:copy_id} range,
panel uniqueness, and omega consistency across copies.{p_end}

{pstd}
{bf:nsim smart default rule:}

{p 8 12 2}
{cmd:omegapoly = 1} (linear evolution): {cmd:nsim = 1}.  The current public
estimator still follows the official single-path DO-style simulation contract;
the helper therefore keeps one path by default rather than describing
{cmd:omegapoly = 1} as a separate draw-free closed-form worker.

{p 8 12 2}
{cmd:omegapoly >= 2} (nonlinear evolution): {cmd:nsim = 100}.  Monte Carlo
simulation is required to integrate over the innovation distribution.

{p 8 12 2}
A user-specified {opt nsim()} always overrides the default.


{marker options}{...}
{title:Options}

{dlgtab:Required}

{phang}
{opt firm(varname)} specifies the firm identifier variable.  This is used
to group observations for generating {cmd:copy_id} within each firm-time
cell and for constructing {cmd:firm_sim_id}.

{phang}
{opt nt(varname)} specifies the time variable, measured relative to the
 treatment year in panel periods (i.e., typically
 {cmd:(time - treat_year) / delta()} under the active {cmd:xtset}). After
expansion, the panel is
re-{cmd:tsset} with {cmd:firm_sim_id} as the panel variable and {it:nt}
as the time variable.

{dlgtab:Optional}

{phang}
{opt nsim(#)} specifies the number of simulation paths per firm.  Must be
>= 1.  If not specified, the default is determined by {opt omegapoly()}:
1 for linear evolution ({cmd:omegapoly = 1}) and 100 for nonlinear
evolution ({cmd:omegapoly >= 2}).  A warning is issued if {cmd:nsim > 10000}.

{phang}
{opt omegapoly(#)} specifies the polynomial order of the omega evolution
process.  If not specified, the value is taken from {cmd:e(omegapoly)}
set by prior estimation.  If {cmd:e(omegapoly)} is not available, the
default is 3.  This option controls the smart {opt nsim} default.

{phang}
{opt treatment(varname)} specifies the numeric binary treatment indicator used
to
identify the ever-treated ATT firms whose event-time paths should be
replicated. The helper collapses this indicator to the firm level via the
firm-wise maximum, so treated firms keep {it:nsim} copies even for their
pre-treatment rows (such as {cmd:nt=-1}), while never-treated controls stay
single-copy. If omitted, {cmd:_pte_path_expand} first tries
{cmd:_pte_treat_group}, then {cmd:treat_post}, {cmd:treat}, and {cmd:D}. When
none of these variables exists, the helper assumes the current data are
already the treated ATT sample and expands all rows. String indicators are
rejected at the helper entry gate; valid treatment variables must be numeric
and take values in {cmd:{0,1}}.


{marker generated}{...}
{title:Generated variables}

{synoptset 18 tabbed}{...}
{synopt:{cmd:copy_id}}int; path copy identifier within each (firm, nt) cell;
treated ATT rows range from 1 to {it:nsim}, while untreated/control rows stay
at 1{p_end}
{synopt:{cmd:firm_sim_id}}long; globally unique path identifier, constructed
as {cmd:group(firm copy_id)}{p_end}
{p2colreset}{...}

{pstd}
Any pre-existing variables named {cmd:copy_id} or {cmd:firm_sim_id} are
dropped before generation.  After expansion, the panel is set to
{cmd:tsset firm_sim_id {it:nt}}, ensuring that lag operators work within
each simulation path.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_path_expand} stores the following as global scalars and caller-local
macros (via {cmd:c_local}):

{synoptset 24 tabbed}{...}
{p2col 5 24 28 2: Scalars}{p_end}
{synopt:{cmd:_pte_nsim}}number of simulation paths used{p_end}
{synopt:{cmd:_pte_N_original}}number of observations before expansion{p_end}
{synopt:{cmd:_pte_N_treated_original}}number of treated ATT observations before
expansion{p_end}
{synopt:{cmd:_pte_N_control_original}}number of untreated/control observations
kept single-copy{p_end}
{synopt:{cmd:_pte_N_expanded}}number of observations after expansion{p_end}
{synopt:{cmd:_pte_omegapoly}}omega evolution polynomial order used{p_end}

{p2col 5 24 28 2: Caller locals (c_local)}{p_end}
{synopt:{cmd:nsim}}number of simulation paths used{p_end}
{synopt:{cmd:N_original}}number of observations before expansion{p_end}
{synopt:{cmd:N_treated_original}}number of treated ATT observations before
expansion{p_end}
{synopt:{cmd:N_control_original}}number of untreated/control observations kept
single-copy{p_end}
{synopt:{cmd:N_expanded}}number of observations after expansion{p_end}
{synopt:{cmd:omegapoly}}omega evolution polynomial order used{p_end}
{p2colreset}{...}

{pstd}
{bf:Important:} This command does {it:not} use {cmd:ereturn} or
{cmd:return} to avoid destroying upstream {cmd:e()} results from
EPIC-001/002.  Results are accessible as {cmd:scalar(_pte_nsim)} etc.
and as local macros in the calling program.


{title:Error codes}

{synoptset 10 tabbed}{...}
{synopt:{cmd:198}}nsim < 1 (invalid simulation count){p_end}
{synopt:{cmd:459}}post-expansion validation failure: observation count
mismatch, copy_id range error, or (firm_sim_id, nt) not unique{p_end}
{synoptline}


{marker examples}{...}
{title:Examples}

{pstd}Typical ATT workflow setup (lets the helper inherit
{cmd:e(omegapoly)}){p_end}

{phang2}{cmd:. use "data/mydata.dta", clear}{p_end}
{phang2}{cmd:. xtset firm year}{p_end}
{phang2}{cmd:. _pte_prodfunc, free(lnl) proxy(lnm) state(lnk) pfunc(cd)}{p_end}
{phang2}{cmd:. _pte_omega_recovery, free(lnl) state(lnk)}{p_end}

{pstd}Basic usage with smart nsim default (omegapoly from e()){p_end}
{phang2}{cmd:. _pte_path_expand, firm(firm) nt(nt) treatment(treat_post)}{p_end}

{pstd}Standalone usage with explicit {cmd:omegapoly()} (no live EPIC-002 state
required){p_end}
{phang2}{cmd:. _pte_path_expand, firm(firm) nt(nt) treatment(treat_post) omegapoly(2) nsim(100)}{p_end}

{pstd}Specify nsim explicitly{p_end}
{phang2}{cmd:. _pte_path_expand, firm(firm) nt(nt) treatment(treat_post) nsim(500)}{p_end}

{pstd}Linear evolution (nsim defaults to 1, no expansion){p_end}
{phang2}{cmd:. _pte_path_expand, firm(firm) nt(nt) treatment(treat_post) omegapoly(1)}{p_end}

{pstd}Nonlinear evolution with custom polynomial order{p_end}
{phang2}{cmd:. _pte_path_expand, firm(firm) nt(nt) treatment(treat_post) omegapoly(3) nsim(200)}{p_end}

{pstd}Inspect stored results{p_end}
{phang2}{cmd:. display scalar(_pte_nsim)}{p_end}
{phang2}{cmd:. display scalar(_pte_N_original)}{p_end}
{phang2}{cmd:. display scalar(_pte_N_expanded)}{p_end}
{phang2}{cmd:. display scalar(_pte_omegapoly)}{p_end}

{pstd}Verify panel structure after expansion{p_end}
{phang2}{cmd:. tsset}{p_end}
{phang2}{cmd:. tab copy_id}{p_end}
{phang2}{cmd:. summarize firm_sim_id}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Y., and Schurter, K. (2026).
Identifying Treatment Effects on Productivity.
{it:Working Paper}.
{p_end}

{phang}
Ackerberg, D. A., Caves, K., and Frazer, G. (2015).
Identification Properties of Recent Production Function Estimators.
{it:Econometrica} 83(6): 2411-2451.
{p_end}


{title:Author}

{pstd}PTE Development Team{p_end}


{title:Also see}

{psee}
Online: {helpb _pte_att}, {helpb _pte_omega_recovery},
{helpb _pte_validate_nt_neg1}
{p_end}
