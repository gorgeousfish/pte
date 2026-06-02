{smcl}
{* *! version 1.0.0  01jan2026}{...}
{viewerjumpto "Syntax" "_pte_compare_clktwfe##syntax"}{...}
{viewerjumpto "Description" "_pte_compare_clktwfe##description"}{...}
{viewerjumpto "Options" "_pte_compare_clktwfe##options"}{...}
{viewerjumpto "Stored results" "_pte_compare_clktwfe##results"}{...}
{viewerjumpto "References" "_pte_compare_clktwfe##references"}{...}
{title:Title}

{p2colset 5 30 32 2}{...}
{p2col:{cmd:_pte_compare_clktwfe} {hline 2}}CLK+TWFE method implementation (internal){p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_compare_clktwfe}{cmd:,}
{opt treatment(varname)}
[{it:options}]

{pstd}
This is an internal program called by {cmd:pte_compare, method(clktwfe)}.
Users should call {cmd:pte_compare} rather than this program directly.

{synoptset 28 tabbed}{...}
{synopthdr}
{synoptline}
{p2coldent:* {opt treatment(varname)}}treatment indicator variable{p_end}
{synopt:{opt specs(numlist)}}TWFE specifications: 1, 2, 3; default is all{p_end}
{synopt:{opt absorb(string)}}fixed effects for reghdfe{p_end}
{synopt:{opt vce(string)}}variance-covariance estimator{p_end}
{synopt:{opt industry(varname)}}reserved; currently rejected because this worker does not implement a general by-industry Method III API{p_end}
{synopt:{opt lagtreatment}}use lagged treatment L.D{p_end}
{synopt:{opt diagnose}}display bias source analysis{p_end}
{synopt:{opt noreport}}suppress results table{p_end}
{synoptline}
{p 4 6 2}* {opt treatment()} is required.{p_end}

{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_compare_clktwfe} implements Method III (CLK+TWFE) for comparing
treatment effect estimates. This method:

{p 8 12 2}1. Uses the current CLK-corrected productivity contract from {cmd:pte}; if the exact canonical {cmd:_pte_omega} is missing or stale relative to the active {cmd:phi}/{cmd:beta} state, the worker rebuilds a temporary current omega before regression{p_end}
{p 8 12 2}2. Excludes transition period observations using the package's exact non-transition gate {_cmd:_pte_mid == 0}; shadow leftovers are rejected instead of binding through Stata abbreviation rules{p_end}
{p 8 12 2}3. Runs TWFE regression with lagged treatment (L.D){p_end}

{pstd}
Three TWFE specifications are available (corresponding to m7-m9 in Table 3):

{p2colset 5 20 22 2}{...}
{p2col:Spec 1 (m7)}No controls: reghdfe current CLK omega L.D if _pte_mid==0, absorb(firm year){p_end}
{p2col:Spec 2 (m8)}AR(1) control: reghdfe current CLK omega L.omega L.D if _pte_mid==0, absorb(firm year){p_end}
{p2col:Spec 3 (m9)}AR(3) controls: reghdfe current CLK omega L.omega L.omega2 L.omega3 L.D if _pte_mid==0, absorb(firm year){p_end}
{p2colreset}{...}

{pstd}
The key difference from Methods I and II is that Method III excludes
transition period observations (where D_t != D_{t-1}), which is the
CLK correction. This addresses Problem 3 (conditional unconfoundedness
fails at transition) but still suffers from Problems 1 and 2.

{pstd}
The official reproduction DO applies the non-transition filter only after
trimming to the working sample. Inside the package, {_cmd:_pte_transition} marks observations outside
the estimation sample as {_cmd:_pte_mid=.}, so the package-consistent
implementation must use {_cmd:_pte_mid==0} to avoid leaking sample-out rows
back into Method III regressions.

{marker options}{...}
{title:Options}

{phang}
{opt treatment(varname)} specifies the treatment indicator variable.
This is required and should match the treatment variable used in {cmd:pte}.

{phang}
{opt specs(numlist)} specifies which TWFE specifications to run.
Default is {cmd:specs(1 2 3)} for all three. Values must be 1, 2, or 3.

{phang}
{opt absorb(string)} specifies the fixed effects for {cmd:reghdfe}.
Default is firm and year fixed effects from {cmd:xtset}.

{phang}
{opt vce(string)} specifies the variance-covariance estimator passed
to {cmd:reghdfe}. Default is the {cmd:reghdfe} default (robust).

{phang}
{opt industry(varname)} is currently reserved and rejected. The paper/DO
comparison path uses hard-coded sample splits rather than a general
by-industry API, so this worker requires the caller to subset the data
before estimation.

{phang}
{opt lagtreatment} uses the lagged treatment variable L.D. This is
the default behavior for CLK+TWFE to match the reproduction code.

{phang}
{opt diagnose} displays a detailed bias source analysis based on
Paper Section 5.

{phang}
{opt noreport} suppresses the results table output.

{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_compare_clktwfe} stores the following in {cmd:e()}:

{synoptset 28 tabbed}{...}
{p2col 5 28 32 2: Scalars}{p_end}
{synopt:{cmd:e(att_clk_twfe_1)}}Spec 1 (m7) ATT estimate{p_end}
{synopt:{cmd:e(att_clk_twfe_2)}}Spec 2 (m8) ATT estimate{p_end}
{synopt:{cmd:e(att_clk_twfe_3)}}Spec 3 (m9) ATT estimate{p_end}
{synopt:{cmd:e(se_clk_twfe_1)}}Spec 1 standard error{p_end}
{synopt:{cmd:e(se_clk_twfe_2)}}Spec 2 standard error{p_end}
{synopt:{cmd:e(se_clk_twfe_3)}}Spec 3 standard error{p_end}
{synopt:{cmd:e(N_clk_twfe)}}number of observations{p_end}
{synopt:{cmd:e(bias_clk_twfe)}}relative bias vs pte (%){p_end}

{p2col 5 28 32 2: Matrices}{p_end}
{synopt:{cmd:e(coef_clk_twfe)}}1x3 coefficient vector (spec1, spec2, spec3){p_end}
{synopt:{cmd:e(se_clk_twfe)}}1x3 standard error vector{p_end}
{synopt:{cmd:e(ci_clk_twfe)}}3x2 confidence interval matrix{p_end}
{synopt:{cmd:e(r2_clk_twfe)}}1x3 adjusted R-squared vector{p_end}
{synopt:{cmd:e(n_clk_twfe)}}1x3 sample size vector{p_end}
{synopt:{cmd:e(coef_clktwfe)}}alias for coef_clk_twfe (compatibility){p_end}
{synopt:{cmd:e(se_clktwfe)}}alias for se_clk_twfe (compatibility){p_end}
{synopt:{cmd:e(compare_coef)}}1x3 coefficient vector (chart interface){p_end}
{synopt:{cmd:e(compare_se)}}1x3 SE vector (chart interface){p_end}

{p2col 5 28 32 2: Macros}{p_end}
{synopt:{cmd:e(cmd)}}{cmd:pte_compare}{p_end}
{synopt:{cmd:e(method)}}{cmd:clktwfe}{p_end}
{synopt:{cmd:e(treatment)}}treatment variable name{p_end}
{synopt:{cmd:e(absorb)}}fixed effects specification{p_end}
{synopt:{cmd:e(specs)}}specifications run{p_end}
{synopt:{cmd:e(lagtreatment)}}{cmd:lagtreatment}{p_end}

{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z. & Schurter, K. (2026).
Productivity Treatment Effects.
{it:Working Paper}. Section 5, Table 3 (m7-m9).
{p_end}

{phang}
Reproduction code reference: DOs/att_estimation_simulation_r1.do L200-205
{p_end}

{title:Also see}

{psee}
{space 2}Help:  {help pte_compare:pte_compare}, {help pte:pte}, {help reghdfe:reghdfe}
{p_end}
