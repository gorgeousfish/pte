{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] _pte_bootstrap_bygroup" "help _pte_bootstrap_bygroup"}{...}
{vieweralsosee "[PTE] _pte_bygroup_aggregate" "help _pte_bygroup_aggregate"}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{viewerjumpto "Syntax" "_pte_bygroup_boot_single##syntax"}{...}
{viewerjumpto "Description" "_pte_bygroup_boot_single##description"}{...}
{viewerjumpto "Options" "_pte_bygroup_boot_single##options"}{...}
{viewerjumpto "Stored results" "_pte_bygroup_boot_single##results"}{...}
{title:Title}

{p2colset 5 34 36 2}{...}
{p2col:{cmd:_pte_bygroup_boot_single} {hline 2}}Single bootstrap iteration for one group{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_bygroup_boot_single}{cmd:,}
{opt treatment(varname)}
{opt depvar(varname)}
{opt free(varname)}
{opt state(varname)}
{opt proxy(varname)}
{opt id(varname)}
{opt time(varname)}
[{it:options}]

{synoptset 25 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt treatment(varname)}}binary treatment indicator{p_end}
{synopt:{opt depvar(varname)}}dependent variable (log output){p_end}
{synopt:{opt free(varname)}}free input variable{p_end}
{synopt:{opt state(varname)}}state variable{p_end}
{synopt:{opt proxy(varname)}}proxy variable{p_end}
{synopt:{opt id(varname)}}panel identifier variable{p_end}
{synopt:{opt time(varname)}}time variable{p_end}

{syntab:Estimation}
{synopt:{opt prodfunc(string)}}production function type; default is {cmd:cd}{p_end}
{synopt:{opt poly(#)}}polynomial order; default is {cmd:3}{p_end}
{synopt:{opt omegapoly(#)}}evolution polynomial order; default is {cmd:3}{p_end}
{synopt:{opt eps0window(#)}}untreated innovation window passed to {cmd:_pte_omega}; default is {cmd:0} (all identified untreated pre-treatment support, scaled by the current {cmd:xtset} {cmd:delta()} declaration when windowed){p_end}
{synopt:{opt control(varlist)}}control variables{p_end}
{synopt:{opt attperiods(#)}}max post-treatment periods; default is {cmd:4}{p_end}
{synopt:{opt nsim(#)}}simulation paths; default is auto ({cmd:1} if {cmd:omegapoly(1)}, else {cmd:100}){p_end}
{synopt:{opt inner_seed(#)}}inner ATT seed; default is {cmd:-1} (no reset){p_end}
{synopt:{opt notrimeps}}disable eps0 Winsorize trimming{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_bygroup_boot_single} is an internal helper that executes one
complete bootstrap iteration for a single group. It is called by
{helpb _pte_bootstrap_bygroup} during the per-group bootstrap loop.

{pstd}
The module performs the following steps on the current dataset (which
should already be filtered to a single group):

{phang2}1. Stratified cluster bootstrap resampling via {cmd:bsample}.{p_end}
{phang2}2. Production function re-estimation via {cmd:_pte_prodfunc}.{p_end}
{phang2}3. Productivity recovery and evolution via {cmd:_pte_omega}.{p_end}
{phang2}4. ATT estimation via {cmd:_pte_att}.{p_end}

{pstd}
{bf:Key difference from _pte_bootstrap_single:} This module does {it:not}
set the outer seed (the caller manages group-level seed). The inner ATT
seed is optional and defaults to no reset, matching the replication code
behavior for industry-level bootstrap.


{marker options}{...}
{title:Options}

{phang}
{opt treatment(varname)}, {opt depvar(varname)}, {opt free(varname)},
{opt state(varname)}, {opt proxy(varname)}, {opt id(varname)},
{opt time(varname)} are required and specify the panel and estimation
variables.

{phang}
{opt prodfunc(string)} specifies the production function type ({cmd:cd}
or {cmd:translog}). Default is {cmd:cd}.

{phang}
{opt eps0window(#)} specifies the untreated innovation window passed to
{cmd:_pte_omega} during the bootstrap rerun. {cmd:eps0window(0)} keeps all
identified untreated pre-treatment support; positive values restrict the
bootstrap worker to the corresponding number of panel periods before the
relevant first-treatment anchor used by EPIC-002, scaled by the current
{cmd:xtset} {cmd:delta()} declaration.

{phang}
{opt inner_seed(#)} specifies the inner seed for ATT simulation. Default
is -1 (no reset), meaning the RNG state continues from the resampling step.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_bygroup_boot_single} stores the following in {cmd:r()}:

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:r(att)}}overall ATT estimate for this iteration{p_end}

{p2col 5 22 26 2: Matrices}{p_end}
{synopt:{cmd:r(att_raw)}}1 x (1+T) raw ATT vector [overall, nt=0, ..., nt=T]{p_end}
{synopt:{cmd:r(att_trim)}}1 x (1+T) trimmed ATT vector (if trimming enabled){p_end}
{synopt:{cmd:r(betas)}}1 x k production function coefficients{p_end}


{marker author}{...}
{title:Author}

{pstd}
PTE Package Development Team
{p_end}
