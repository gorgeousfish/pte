{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] _pte_prodfunc" "help _pte_prodfunc"}{...}
{viewerjumpto "Syntax" "_pte_treatdep_interact##syntax"}{...}
{viewerjumpto "Description" "_pte_treatdep_interact##description"}{...}
{viewerjumpto "Options" "_pte_treatdep_interact##options"}{...}
{viewerjumpto "Stored results" "_pte_treatdep_interact##results"}{...}
{viewerjumpto "Examples" "_pte_treatdep_interact##examples"}{...}
{viewerjumpto "References" "_pte_treatdep_interact##references"}{...}
{title:Title}

{p2colset 5 36 38 2}{...}
{p2col:{cmd:_pte_treatdep_interact} {hline 2}}Treatment interaction term
generation{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_treatdep_interact}{cmd:,}
{opt free(name)}
{opt state(name)}
{opt treatment(name)}
[{it:options}]

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt free(name)}}free (flexible) input variable, e.g., log labor; must
match an existing variable exactly{p_end}
{synopt:{opt state(name)}}state variable, e.g., log capital; must match an
existing variable exactly{p_end}
{synopt:{opt treatment(name)}}binary treatment indicator (0/1); must match an
existing variable exactly{p_end}

{syntab:Optional}
{synopt:{opt pfunc(string)}}production function type; {bf:cd} (default) or
{bf:translog}{p_end}
{synopt:{opt suffix(string)}}suffix for generated variable names; default is
{bf:tp}{p_end}
{synopt:{opt noclean}}do not overwrite existing interaction variables; error if
they exist{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_treatdep_interact} is an internal module that generates treatment
interaction terms for treatment-dependent production function estimation as
described in Appendix C.1 of Chen, Liao & Schurter (2026).

{pstd}
The helper operates on the exact realized {it:l_t}, {it:k_t}, and {it:D_t}
state variables. It does {bf:not} accept Stata unique-abbreviation fallback.
For example, {cmd:free(lnl)} is rejected if the data contain only
{cmd:lnl_shadow}.

{pstd}
For a given free input variable {it:lnl} and state variable {it:lnk}, the
command creates two interaction terms:

{p 8 8 2}
{it:lnl_tp} = {it:lnl} {it:x} D{break}
{it:lnk_tp} = {it:lnk} {it:x} D

{pstd}
where D is the binary treatment indicator. These interaction terms allow the
production function coefficients to differ between treated and untreated firms.
The generated variables and corresponding parameter lists are returned in
{cmd:r()} for direct use with {cmd:endopolyprodest} or other estimation
commands.

{pstd}
By default, existing variables with the same names are silently replaced.
Specify {opt noclean} to prevent overwriting and raise an error if the
variables already exist.


{marker options}{...}
{title:Options}

{dlgtab:Required}

{phang}
{opt free(name)} specifies the free (flexible) input variable, typically
log labor ({it:lnl}). The name must match an existing numeric variable
exactly; abbreviation fallback such as {cmd:free(lnl)} binding to
{cmd:lnl_shadow} is rejected.

{phang}
{opt state(name)} specifies the state variable, typically log capital
({it:lnk}). The name must match an existing numeric variable exactly;
abbreviation fallback such as {cmd:state(lnk)} binding to {cmd:lnk_shadow}
is rejected.

{phang}
{opt treatment(name)} specifies the binary treatment indicator variable.
The name must match an existing numeric variable exactly; abbreviation
fallback such as {cmd:treatment(D)} binding to {cmd:D_shadow} is rejected.
The variable must contain only values 0, 1, or missing.

{dlgtab:Optional}

{phang}
{opt pfunc(string)} specifies the production function type. Valid values are
{bf:cd} (Cobb-Douglas, the default) and {bf:translog}.

{phang}
{opt suffix(string)} specifies the suffix appended to variable names when
creating interaction terms. The default is {bf:tp}, which produces variables
named {it:free}_tp and {it:state}_tp.

{phang}
{opt noclean} prevents the command from dropping existing interaction
variables before generation. If the target variables already exist, an error
is raised.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_treatdep_interact} stores the following in {cmd:r()}:

{synoptset 24 tabbed}{...}
{p2col 5 24 28 2: Scalars}{p_end}
{synopt:{cmd:r(n_interact)}}number of interaction terms generated (always
2){p_end}
{synopt:{cmd:r(n_free)}}number of free variables (original + interaction){p_end}
{synopt:{cmd:r(n_state)}}number of state variables (original +
interaction){p_end}
{synopt:{cmd:r(n_untreated)}}number of untreated observations (D=0){p_end}
{synopt:{cmd:r(n_treated)}}number of treated observations (D=1){p_end}

{p2col 5 24 28 2: Macros}{p_end}
{synopt:{cmd:r(free_vars)}}list of free variables including interaction
term{p_end}
{synopt:{cmd:r(state_vars)}}list of state variables including interaction
term{p_end}
{synopt:{cmd:r(interact_vars)}}list of generated interaction variables{p_end}
{synopt:{cmd:r(treatment_var)}}name of the treatment variable{p_end}
{synopt:{cmd:r(pfunc)}}production function type used{p_end}
{synopt:{cmd:r(suffix)}}suffix used for generated variable names{p_end}


{marker examples}{...}
{title:Examples}

{pstd}Setup{p_end}
{phang2}{cmd:. webuse nlswork, clear}{p_end}
{phang2}{cmd:. gen lnl = ln(hours)}{p_end}
{phang2}{cmd:. gen lnk = ln(tenure + 1)}{p_end}
{phang2}{cmd:. gen D = (union == 1) if !missing(union)}{p_end}

{pstd}Generate interaction terms with default settings (Cobb-Douglas){p_end}
{phang2}{cmd:. _pte_treatdep_interact, free(lnl) state(lnk) treatment(D)}{p_end}

{pstd}Use returned variable lists{p_end}
{phang2}{cmd:. display "`r(free_vars)'"}{p_end}
{phang2}{cmd:. display "`r(state_vars)'"}{p_end}

{pstd}Generate with custom suffix{p_end}
{phang2}{cmd:. _pte_treatdep_interact, free(lnl) state(lnk) treatment(D) suffix(treat)}{p_end}

{pstd}Generate without overwriting existing variables{p_end}
{phang2}{cmd:. _pte_treatdep_interact, free(lnl) state(lnk) treatment(D) noclean}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, X., W. Liao, and K. Schurter. 2026. Productivity treatment effects.
Appendix C.1: Treatment-dependent production functions.
{p_end}
{smcl}
