{smcl}
{* *! version 1.0.0  01jan2026}{...}
{viewerjumpto "Syntax" "_pte_cd_estimate##syntax"}{...}
{viewerjumpto "Description" "_pte_cd_estimate##description"}{...}
{viewerjumpto "Options" "_pte_cd_estimate##options"}{...}
{viewerjumpto "Stored results" "_pte_cd_estimate##results"}{...}
{viewerjumpto "Examples" "_pte_cd_estimate##examples"}{...}
{viewerjumpto "References" "_pte_cd_estimate##references"}{...}
{title:Title}

{p2colset 5 30 32 2}{...}
{p2col:{bf:_pte_cd_estimate} {hline 2}}Cobb-Douglas production function
parameter estimation{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_cd_estimate} {ifin}{cmd:,}
{opt depvar(varname)}
{opt free(varname)}
{opt state(varname)}
{opt proxy(varname)}
{opt treatment(varname)}
[{it:options}]

{synoptset 28 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt depvar(varname)}}log output variable (e.g., lny){p_end}
{synopt:{opt free(varname)}}log labor variable (free input){p_end}
{synopt:{opt state(varname)}}log capital variable (state input){p_end}
{synopt:{opt proxy(varname)}}log materials variable (proxy input){p_end}
{synopt:{opt treatment(varname)}}binary treatment indicator (0/1){p_end}

{syntab:Optional}
{synopt:{opt control(varlist)}}additional control variables; each name must be
spelled exactly, without Stata abbreviation fallback{p_end}
{synopt:{opt id(varname)}}panel identifier (overrides xtset){p_end}
{synopt:{opt t(varname)}}time variable (overrides xtset){p_end}
{synopt:{opt pooled}}use pooled estimation mode{p_end}
{synopt:{opt by(varname)}}industry grouping variable (with {opt pooled}); the
grouping variable name must be spelled exactly{p_end}
{synopt:{opt omegapoly(#)}}omega evolution polynomial order; default is
{cmd:1}{p_end}
{synopt:{opt maxiter(#)}}maximum GMM iterations; default is {cmd:10000}{p_end}
{synopt:{opt touse(varname)}}internal numeric sample indicator; zero and missing
values are excluded from all estimator stages{p_end}
{synopt:{opt nodiagnose}}suppress diagnostic output{p_end}
{synopt:{opt nolog}}suppress progress log{p_end}
{synoptline}
{p2colreset}{...}

{p 4 6 2}
Data must be {cmd:xtset} before calling this command. The canonical transition
indicator is {bf:_pte_mid} from {cmd:_pte_transition}; legacy {bf:mid} is
accepted only as a compatibility fallback when present.

{p 4 6 2}
{cmd:if}, {cmd:in}, and {opt touse()} define the live estimation sample.  The
same sample contract is applied to the first-stage proxy regression, GMM matrix
assembly, OLS starting values, transition-law validation, and the posted
{cmd:e(sample)}.


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_cd_estimate} estimates Cobb-Douglas production function parameters
using the ACF two-stage GMM method with the CLK correction from
Chen, Liao & Schurter (2026).

{pstd}
The Cobb-Douglas production function in log form is:

{p 8 8 2}
y_it = beta_l * l_it + beta_k * k_it + omega_it + eta_it

{pstd}
where y is log output, l is log labor, k is log capital, omega is total
factor productivity, and eta is an ex-post shock.

{pstd}
The estimation proceeds in phases:

{p 8 12 2}
1. Polynomial variable generation (3rd-order approximation){p_end}
{p 8 12 2}
2. First-stage OLS regression to obtain phi = E[y|k,l,m]{p_end}
{p 8 12 2}
3. GMM matrix construction (excluding transitions {cmd:_pte_mid=1}, or legacy
{cmd:mid=1} when that alias is the only available transition indicator){p_end}
{p 8 12 2}
4. Nelder-Mead GMM optimization{p_end}
{p 8 12 2}
5. Parameter validation and result storage{p_end}

{pstd}
The CLK correction excludes transition-period observations (where D_t !=
D_{t-1})
from the GMM estimation, as required by Theorem 3.1.

{pstd}
The live transition indicator must therefore come from the same D_t path used
by the current {opt treatment()} input. If {cmd:_pte_mid} (or legacy
{cmd:mid}) was built from a different treatment variable or before the current
data were modified, {cmd:_pte_cd_estimate} fails closed with {cmd:rc=498}
instead of silently mixing inconsistent transition state into the GMM sample.
Re-run {cmd:_pte_transition, treatment(...)} on the current sample before
calling {cmd:_pte_cd_estimate}.

{pstd}
Two estimation modes are supported:

{p 8 12 2}
{bf:By-industry} (default): Estimates parameters separately for each industry
using a simple time trend.  Reference:
{it:prodest_clk_mata_industry_est.do}.{p_end}

{p 8 12 2}
{bf:Pooled}: Estimates parameters using all industries jointly with
industry-specific time trends.  Reference:
{it:prodest_clk_mata_pool_est.do}.{p_end}


{marker options}{...}
{title:Options}

{dlgtab:Required}

{phang}
{opt depvar(varname)} specifies the log output variable (dependent variable).

{phang}
{opt free(varname)} specifies the log labor variable (free input in ACF
terminology).

{phang}
{opt state(varname)} specifies the log capital variable (state variable in ACF
terminology).

{phang}
{opt proxy(varname)} specifies the log materials variable (proxy for unobserved
productivity).

{phang}
{opt treatment(varname)} specifies the binary treatment indicator.  Must contain
only values 0 and 1.

{dlgtab:Optional}

{phang}
{opt control(varlist)} specifies additional control variables to include in the
first-stage regression.  Each control name must be written exactly as it
exists in the data.  Unique-abbreviation fallback is rejected because a shadow
control would change the control-subtracted {it:phi} object carried into the
GMM step.

{phang}
{opt id(varname)} specifies the panel identifier variable.  If not specified,
the panel variable from {cmd:xtset} is used.

{phang}
{opt t(varname)} specifies the time variable.  If not specified, the time
variable from {cmd:xtset} is used.

{phang}
{opt pooled} requests pooled estimation across all industries.  When combined
with {opt by()}, industry-specific time trends are generated.

{phang}
{opt by(varname)} specifies the industry grouping variable. In {opt pooled}
mode it generates industry-specific time trends (t1, t2, ..., tJ). In the
non-{opt pooled} path, supplying {opt by()} still activates the live
single-industry contract: the estimation sample must contain exactly one
nonmissing {opt by()} level; otherwise users should subset to one industry or
add {bf:pooled}.  The
grouping variable name itself must also be written exactly; abbreviation
fallback is rejected because it would silently redirect the pooled time-trend
partition.

{phang}
{opt omegapoly(#)} specifies the polynomial order for the omega evolution
function.  Valid values are {cmd:1} through {cmd:4}.  The standalone
{cmd:_pte_cd_estimate} entry point defaults to {cmd:omegapoly(1)}, but the
current implementation accepts higher-order omega polynomials when requested.

{phang}
{opt maxiter(#)} specifies the maximum number of iterations for the
Nelder-Mead GMM optimizer.  Default is {cmd:10000}.

{phang}
{opt touse(varname)} specifies an internal numeric sample indicator.
Observations
where {it:varname} is zero or missing are excluded before required variables,
controls, grouping variables, and transition periods are checked.  This option
is
intended for callers that have already constructed a package-level sample.

{phang}
{opt nodiagnose} suppresses diagnostic output (R-squared checks, VIF, etc.).

{phang}
{opt nolog} suppresses the progress log during estimation.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_cd_estimate} stores the following in {cmd:e()}:

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars}{p_end}
{synopt:{cmd:e(N)}}number of observations used in GMM{p_end}
{synopt:{cmd:e(converged)}}1 if optimizer converged, 0 otherwise{p_end}
{synopt:{cmd:e(iterations)}}number of optimizer iterations{p_end}
{synopt:{cmd:e(fval)}}GMM objective function value at optimum{p_end}
{synopt:{cmd:e(r2_stage1)}}first-stage regression R-squared{p_end}
{synopt:{cmd:e(rts)}}returns to scale (beta_l + beta_k){p_end}

{p2col 5 20 24 2: Macros}{p_end}
{synopt:{cmd:e(cmd)}}{cmd:pte}{p_end}
{synopt:{cmd:e(pfunc)}}{cmd:cd}{p_end}
{synopt:{cmd:e(depvar)}}name of dependent variable{p_end}
{synopt:{cmd:e(free)}}name of free variable{p_end}
{synopt:{cmd:e(state)}}name of state variable{p_end}
{synopt:{cmd:e(proxy)}}name of proxy variable{p_end}
{synopt:{cmd:e(treatment)}}name of treatment variable{p_end}

{p2col 5 20 24 2: Matrices}{p_end}
{synopt:{cmd:e(b)}}1 x 2 coefficient vector (beta_l, beta_k){p_end}
{synopt:{cmd:e(V)}}not returned; this module does not release an inferential
covariance matrix{p_end}


{marker examples}{...}
{title:Examples}

{pstd}Setup{p_end}
{phang2}{cmd:. use data/复现数据.dta, clear}{p_end}
{phang2}{cmd:. xtset firm year}{p_end}

{pstd}Transition period identification (prerequisite){p_end}
{phang2}{cmd:. _pte_transition, treatment(treat_post) id(firm) time(year) replace}{p_end}

{pstd}By-industry CD estimation (default mode){p_end}
{phang2}{cmd:. _pte_cd_estimate, depvar(lny) free(lnl) state(lnk) proxy(lnm) treatment(treat_post)}{p_end}

{pstd}Pooled CD estimation with industry grouping{p_end}
{phang2}{cmd:. _pte_cd_estimate, depvar(lny) free(lnl) state(lnk) proxy(lnm) treatment(treat_post) pooled by(industry)}{p_end}

{pstd}With custom max iterations{p_end}
{phang2}{cmd:. _pte_cd_estimate, depvar(lny) free(lnl) state(lnk) proxy(lnm) treatment(treat_post) maxiter(20000)}{p_end}

{pstd}Suppress log output{p_end}
{phang2}{cmd:. _pte_cd_estimate, depvar(lny) free(lnl) state(lnk) proxy(lnm) treatment(treat_post) nolog}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Y., & Schurter, K. (2026).
Identifying Treatment Effects on Productivity.
{p_end}

{phang}
Ackerberg, D. A., Caves, K., & Frazer, G. (2015).
Identification Properties of Recent Production Function Estimators.
{it:Econometrica}, 83(6), 2411-2451.
{p_end}


{title:Also see}

{psee}
{space 2}Help:  {manhelp xtset XT}, {helpb _pte_transition},
{helpb _pte_polyvar}, {helpb _pte_stage1}, {helpb _pte_gmm_matrices},
{helpb _pte_gmm_wrapper}
{p_end}
