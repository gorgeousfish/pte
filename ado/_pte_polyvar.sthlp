{smcl}
{* *! version 1.0.0  01jan2026}{...}
{* *! US-E1-002: Polynomial Variable Generation}{...}

{cmd:help _pte_polyvar}{right:PTE Package}
{hline}

{title:Title}

{p2colset 5 26 28 2}{...}
{p2col:{hi:_pte_polyvar} {hline 2} Polynomial Variable Generation for PTE}{p_end}
{p2colreset}{...}


{title:Syntax}

{p 8 28 2}{cmd:_pte_polyvar}, {opt free(varname)} {opt proxy(varname)} {opt state(varname)}
[{it:options}]

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{p2coldent:* {opt free(varname)}}exact free-variable name (labor, in logs){p_end}
{p2coldent:* {opt proxy(varname)}}exact proxy-variable name (intermediate inputs, in logs){p_end}
{p2coldent:* {opt state(varname)}}exact state-variable name (capital, in logs){p_end}

{syntab:Optional}
{synopt:{opt pfunc(string)}}production function type; {cmd:cd} (default) or {cmd:translog}{p_end}
{synopt:{opt poly(#)}}polynomial degree; 1, 2, or 3; default is {cmd:3}{p_end}
{synopt:{opt genlag}}generate lagged variables for GMM instruments{p_end}
{synopt:{opt noclean}}do not drop existing variables with the same names{p_end}
{synoptline}
{p 4 6 2}
{cmd:*} {opt free()}, {opt proxy()}, and {opt state()} are required.{p_end}
{p 4 6 2}
Data must be {helpb xtset} as panel data when {opt genlag} is specified.{p_end}


{title:Description}

{pstd}
{cmd:_pte_polyvar} generates polynomial expansion terms and cross terms of
input variables for the ACF (2015) first-stage nonparametric regression.
These variables approximate the proxy function
{it:Phi(k,l,m) = E[y | k, l, m]} using a polynomial of degree {opt poly()}.

{pstd}
This is a core preprocessing step for production function estimation in the
PTE package.  The generated variables are used by {cmd:_pte_prodfunc} for
first-stage regression (US-E1-003) and by the GMM optimizer for instrument
matrix construction (US-E1-004).

{pstd}
The command supports both Cobb-Douglas ({cmd:pfunc(cd)}) and Translog
({cmd:pfunc(translog)}) production functions.  When {opt poly(3)} is
specified, 19 polynomial variables are generated for both types.  The
downstream module (US-E1-003) determines which variables enter the
first-stage regression based on the estimation mode.

{pstd}
When {opt genlag} is specified, the command also generates lagged variables
needed for GMM instrument matrices (Z matrix).  The number of lag variables
depends on {opt poly()}: 3 for {cmd:poly(1)}, 6 for {cmd:poly(2)} or
{cmd:poly(3)}.


{title:Options}

{dlgtab:Required}

{phang}
{opt free(varname)} specifies the exact free-variable name (labor input, in
logs). The variable must exist under that exact name, be numeric, and
contain at least one non-missing value.

{phang}
{opt proxy(varname)} specifies the exact proxy-variable name (intermediate
inputs, in logs). The variable must exist under that exact name, be
numeric, and contain at least one non-missing value.

{phang}
{opt state(varname)} specifies the exact state-variable name (capital input,
in logs). The variable must exist under that exact name, be numeric, and
contain at least one non-missing value.

{dlgtab:Optional}

{phang}
{opt pfunc(string)} specifies the production function type.  Valid values
are {cmd:cd} (Cobb-Douglas, the default) and {cmd:translog}.  This value
is stored in {cmd:r(pfunc)} and used by downstream modules to determine
which variables enter the first-stage regression and GMM matrices.

{phang}
{opt poly(#)} specifies the polynomial degree for the expansion.  Valid
values are 1, 2, or 3.  The default is {cmd:3}.  Higher degrees provide
more flexible approximation of the proxy function but consume more degrees
of freedom.

{p 12 12 2}
{cmd:poly(1)}: 3 variables (first-order terms only){break}
{cmd:poly(2)}: 9 variables (first- and second-order terms){break}
{cmd:poly(3)}: 19 variables (full third-order expansion)

{phang}
{opt genlag} requests generation of lagged variables for GMM instrument
matrix construction.  This option requires the data to be {helpb xtset}
as panel data.  Panel first-period observations will have missing lag
values (standard Stata {cmd:L.} operator behavior).

{phang}
{opt noclean} prevents the command from dropping existing variables with
the same names before generating new ones.  By default, existing polynomial
and lag variables are silently dropped and recreated.



{title:Generated variables}

{pstd}
The following polynomial variables are generated depending on {opt poly()}:

{dlgtab:First-order terms (poly >= 1)}

{synoptset 14 tabbed}{...}
{synopt:{cmd:l1}}double; log labor = {it:free}{p_end}
{synopt:{cmd:m1}}double; log materials = {it:proxy}{p_end}
{synopt:{cmd:k1}}double; log capital = {it:state}{p_end}
{p2colreset}{...}

{dlgtab:Second-order terms (poly >= 2)}

{synoptset 14 tabbed}{...}
{synopt:{cmd:l2}}double; log labor squared = {it:free}^2{p_end}
{synopt:{cmd:m2}}double; log materials squared = {it:proxy}^2{p_end}
{synopt:{cmd:k2}}double; log capital squared = {it:state}^2{p_end}
{synopt:{cmd:l1m1}}double; log labor * log materials{p_end}
{synopt:{cmd:l1k1}}double; log labor * log capital{p_end}
{synopt:{cmd:m1k1}}double; log materials * log capital{p_end}
{p2colreset}{...}

{dlgtab:Third-order terms (poly = 3)}

{pstd}Pure third-order terms:

{synoptset 14 tabbed}{...}
{synopt:{cmd:l3}}double; log labor cubed = {it:free}^3{p_end}
{synopt:{cmd:m3}}double; log materials cubed = {it:proxy}^3{p_end}
{synopt:{cmd:k3}}double; log capital cubed = {it:state}^3{p_end}
{p2colreset}{...}

{pstd}Third-order cross terms (two-variable):

{synoptset 14 tabbed}{...}
{synopt:{cmd:l1m2}}double; {it:free} * {it:proxy}^2{p_end}
{synopt:{cmd:l1k2}}double; {it:free} * {it:state}^2{p_end}
{synopt:{cmd:m1k2}}double; {it:proxy} * {it:state}^2{p_end}
{synopt:{cmd:m1l2}}double; {it:proxy} * {it:free}^2{p_end}
{synopt:{cmd:k1l2}}double; {it:state} * {it:free}^2{p_end}
{synopt:{cmd:k1m2}}double; {it:state} * {it:proxy}^2{p_end}
{p2colreset}{...}

{pstd}Third-order cross term (three-variable):

{synoptset 14 tabbed}{...}
{synopt:{cmd:k1l1m1}}double; {it:state} * {it:free} * {it:proxy}{p_end}
{p2colreset}{...}

{dlgtab:Lag variables (if genlag specified)}

{pstd}Input lags (always generated when {opt genlag} is specified):

{synoptset 18 tabbed}{...}
{synopt:{cmd:{it:free}_lag}}double; L.{it:free} (lagged free variable){p_end}
{synopt:{cmd:{it:proxy}_lag}}double; L.{it:proxy} (lagged proxy variable){p_end}
{synopt:{cmd:{it:state}_lag}}double; L.{it:state} (lagged state variable){p_end}
{p2colreset}{...}

{pstd}Square and mixed lags (generated when {opt genlag} and {opt poly()} >= 2):

{synoptset 18 tabbed}{...}
{synopt:{cmd:l2_lag}}double; L.l2 (lagged log labor squared){p_end}
{synopt:{cmd:k2_lag}}double; L.k2 (lagged log capital squared){p_end}
{synopt:{cmd:l1k_lag}}double; L.{it:free} * {it:state} (see {help _pte_polyvar##l1k_lag:important note}){p_end}
{p2colreset}{...}


{marker l1k_lag}{...}
{title:Important note on l1k_lag}

{pstd}
{err:WARNING:} The variable {cmd:l1k_lag} is defined as
{bf:lagged labor * CURRENT capital}:

{p 8 12 2}
{cmd:l1k_lag} = L.{it:free} * {it:state} = ln(L{sub:t-1}) * ln(K{sub:t})

{pstd}
This is {bf:NOT} the lag of the cross term {cmd:l1k1}.  That is:

{p 8 12 2}
{cmd:l1k_lag} {it:!=} L.l1k1 = L.(ln(L) * ln(K)) = ln(L{sub:t-1}) * ln(K{sub:t-1})

{pstd}
{ul:Theoretical justification} (Assumption 2.2 of Chen, Liao & Schurter 2026):
Capital K{sub:it} is determined at or before time t-1, so current capital k{sub:t}
is predetermined with respect to the productivity innovation and serves as a
valid instrument.  Lagged labor l{sub:t-1} also satisfies the exogeneity
condition.  The product l{sub:t-1} * k{sub:t} is therefore a valid instrument
for the Translog GMM Z matrix.

{pstd}
{ul:Numerical example}:

        {c TLC}{hline 6}{c -}{hline 6}{c -}{hline 6}{c -}{hline 6}{c -}{hline 10}{c -}{hline 14}{c -}{hline 10}{c TRC}
        {c |} firm   year    lnl    lnk   L.lnl   l1k_lag        L.l1k1     diff {c |}
        {c LT}{hline 6}{c -}{hline 6}{c -}{hline 6}{c -}{hline 6}{c -}{hline 10}{c -}{hline 14}{c -}{hline 10}{c RT}
        {c |}    1   2000    2.0    3.0       .          .             .        . {c |}
        {c |}    1   2001    2.5    3.5     2.0   {bf:7.0}          6.0      1.0 {c |}
        {c |}    1   2002    3.0    4.0     2.5  {bf:10.0}          8.75     1.25 {c |}
        {c BLC}{hline 6}{c -}{hline 6}{c -}{hline 6}{c -}{hline 6}{c -}{hline 10}{c -}{hline 14}{c -}{hline 10}{c BRC}

{p 8 12 2}
year 2001: l1k_lag = 2.0 * 3.5 = {bf:7.0} (correct){break}
           L.l1k1  = 2.0 * 3.0 = 6.0 (wrong){break}
year 2002: l1k_lag = 2.5 * 4.0 = {bf:10.0} (correct){break}
           L.l1k1  = 2.5 * 3.5 = 8.75 (wrong)

{pstd}
Reference: {cmd:DOs/prodest_clk_mata_pool_trlg_nonlinear.do} line 58:
{cmd:g l1k_lag = lnl_lag*lnk}


{title:Stored results}

{pstd}
{cmd:_pte_polyvar} stores the following in {cmd:r()}:

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:r(n_polyvars)}}number of polynomial variables generated{p_end}
{synopt:{cmd:r(poly)}}polynomial degree used{p_end}
{synopt:{cmd:r(n_lagvars)}}number of lag variables generated (if {opt genlag}){p_end}

{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:r(polyvars)}}space-separated list of polynomial variable names{p_end}
{synopt:{cmd:r(pfunc)}}production function type used ({cmd:cd} or {cmd:translog}){p_end}
{synopt:{cmd:r(lagvars)}}space-separated list of lag variable names (if {opt genlag}){p_end}
{p2colreset}{...}

{pstd}
Variable counts by configuration:

        {c TLC}{hline 10}{c -}{hline 14}{c -}{hline 14}{c TRC}
        {c |}   poly    n_polyvars   n_lagvars  {c |}
        {c LT}{hline 10}{c -}{hline 14}{c -}{hline 14}{c RT}
        {c |}      1             3           3  {c |}
        {c |}      2             9           6  {c |}
        {c |}      3            19           6  {c |}
        {c BLC}{hline 10}{c -}{hline 14}{c -}{hline 14}{c BRC}

{p 8 12 2}
Note: {cmd:n_lagvars} is only returned when {opt genlag} is specified.
When {cmd:poly(1)} is used with {opt genlag}, only 3 input lags are
generated (no {cmd:l2_lag}, {cmd:k2_lag}, or {cmd:l1k_lag}).


{title:Error codes}

{synoptset 10 tabbed}{...}
{synopt:{cmd:111}}specified input variable not found{p_end}
{synopt:{cmd:109}}specified input variable is not numeric{p_end}
{synopt:{cmd:198}}invalid {opt poly()} or {opt pfunc()} value{p_end}
{synopt:{cmd:459}}data not {helpb xtset} as panel when {opt genlag} is specified{p_end}
{synopt:{cmd:2000}}specified input variable has all missing values{p_end}
{p2colreset}{...}


{title:Examples}

{pstd}Setup: load panel data and set panel structure{p_end}

{phang2}{cmd:. use "data/mydata.dta", clear}{p_end}
{phang2}{cmd:. xtset firm year}{p_end}

{pstd}Basic usage with Cobb-Douglas (default){p_end}
{phang2}{cmd:. _pte_polyvar, free(lnl) proxy(lnm) state(lnk)}{p_end}

{pstd}Translog with lag variables for GMM{p_end}
{phang2}{cmd:. _pte_polyvar, free(lnl) proxy(lnm) state(lnk) pfunc(translog) genlag}{p_end}

{pstd}Second-order polynomial only{p_end}
{phang2}{cmd:. _pte_polyvar, free(lnl) proxy(lnm) state(lnk) poly(2)}{p_end}

{pstd}Inspect stored results{p_end}
{phang2}{cmd:. return list}{p_end}

{pstd}Use generated variables in first-stage regression{p_end}
{phang2}{cmd:. _pte_polyvar, free(lnl) proxy(lnm) state(lnk) pfunc(cd)}{p_end}
{phang2}{cmd:. reg lny `r(polyvars)' t}{p_end}
{phang2}{cmd:. predict double phi, xb}{p_end}

{pstd}Construct Translog GMM Z matrix in Mata{p_end}
{phang2}{cmd:. _pte_polyvar, free(lnl) proxy(lnm) state(lnk) pfunc(translog) genlag}{p_end}
{phang2}{cmd:. mata: Z = st_data(., ("const", "lnl_lag", "lnk", "l2_lag", "k2", "l1k_lag", "t"))}{p_end}

{pstd}Verify l1k_lag is correct{p_end}
{phang2}{cmd:. gen double check = L.lnl * lnk}{p_end}
{phang2}{cmd:. assert abs(l1k_lag - check) < 1e-14 if !mi(l1k_lag)}{p_end}


{title:Theoretical background}

{pstd}
This module implements the polynomial variable generation step for the ACF
(Ackerberg, Caves & Frazer, 2015) first-stage nonparametric regression.
The proxy function is approximated as:

{p 8 12 2}
Phi(k, l, m) = sum_{i+j+k <= p} gamma_{ijk} * l^i * m^j * k^k

{pstd}
where p is the polynomial degree (default 3).  This approximation is the
foundation for Theorem 3.1 of Chen, Liao & Schurter (2026), which
establishes identification of the production function parameters under the
CLK correction framework.

{pstd}
The Translog production function (Equation 15 of the paper) is:

{p 8 12 2}
y = beta_t + beta_l * l + beta_k * k + beta_ll * l^2 + beta_kk * k^2
    + beta_lk * k * l + omega + eta

{pstd}
The lag variables serve as instruments in the GMM second stage.  Their
validity relies on Assumption 2.2 (Timing of Inputs): capital and labor
are determined at or before t-1, while intermediate inputs are determined
after the realization of productivity omega_t.


{title:References}

{phang}
Ackerberg, D. A., Caves, K., and Frazer, G. (2015).
Identification Properties of Recent Production Function Estimators.
{it:Econometrica} 83(6): 2411-2451.
{p_end}

{phang}
Chen, X., Liao, Y., and Schurter, K. (2026).
Identifying Treatment Effects on Productivity.
{it:Working Paper}.
{p_end}


{title:Author}

{pstd}PTE Development Team{p_end}


{title:Also see}

{psee}
Online: {helpb xtset}, {helpb _pte_transition}, {helpb _pte_prodfunc}
{p_end}
