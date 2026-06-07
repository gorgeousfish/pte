{smcl}
{* *! version 1.0.0}{...}
{viewerjumpto "Syntax" "pte_diagnose##syntax"}{...}
{viewerjumpto "Description" "pte_diagnose##description"}{...}
{viewerjumpto "Options" "pte_diagnose##options"}{...}
{viewerjumpto "Stored results" "pte_diagnose##results"}{...}
{viewerjumpto "Examples" "pte_diagnose##examples"}{...}
{title:Title}

{phang}
{bf:pte_diagnose} {hline 2} Diagnostic tests for productivity treatment effects assumptions


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:pte_diagnose}
[{cmd:,} {it:options}]

{synoptset 22 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Test selection}
{synopt:{opt par:allel}}parallel trends test{p_end}
{synopt:{opt ks:test}}Kolmogorov-Smirnov test on eps0{p_end}
{synopt:{opt cond:itional}}conditional independence test{p_end}
{synopt:{opt cdf}}CDF comparison{p_end}
{synopt:{opt all}}run all diagnostics (default){p_end}

{syntab:Parameters}
{synopt:{opt omega(varname)}}override omega variable name{p_end}
{synopt:{opt eps0(varname)}}override eps0 variable name{p_end}
{synopt:{opt pre:periods(#)}}number of pre-treatment periods; default is {cmd:4}{p_end}
{synopt:{opt bins(#)}}number of bins for conditional test; default is {cmd:3}{p_end}
{synopt:{opt baseyear(#)}}base year for parallel trends{p_end}
{synopt:{opt minobs(#)}}minimum observations per bin; default is {cmd:30}{p_end}
{synopt:{opt alpha(#)}}significance level; default is {cmd:0.05}{p_end}
{synopt:{opt level(#)}}confidence level for intervals{p_end}
{synopt:{opt sav:ing(filename)}}save CDF graph to file{p_end}
{synopt:{opt notrimeps}}skip eps0 trimming{p_end}
{synopt:{opt strict:control}}strict control-only sample{p_end}
{synopt:{opt qui:etly}}suppress output{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:pte_diagnose} runs the public diagnostics suite for productivity and
untreated-shock objects left in memory after {cmd:pte} estimation.  It tests
the key assumptions underlying the CLK framework:

{phang2}(1) Parallel trends in pre-treatment productivity evolution{p_end}
{phang2}(2) Independence of eps0 shocks from treatment assignment (KS test){p_end}
{phang2}(3) Conditional independence given observables{p_end}
{phang2}(4) CDF overlap between treated and control eps0 distributions{p_end}
{phang2}(5) Assumption 3.3 transition-period identification{p_end}

{pstd}
By default all tests are run.  Use individual options to select a subset.


{marker options}{...}
{title:Options}

{dlgtab:Test selection}

{phang}
{opt parallel} tests for parallel pre-trends in productivity evolution across
treatment and control groups.

{phang}
{opt kstest} performs Kolmogorov-Smirnov tests comparing the eps0 distribution
between treated and control firms.

{phang}
{opt conditional} tests for conditional independence of shocks given observables.

{phang}
{opt cdf} plots the empirical CDF of eps0 for treated vs control groups.

{dlgtab:Parameters}

{phang}
{opt preperiods(#)} specifies the number of pre-treatment periods used for the
parallel trends test.  Default is 4.

{phang}
{opt saving(filename)} saves the CDF comparison graph.  Only valid with {opt cdf}
or {opt all}.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:pte_diagnose} stores the following in {cmd:r()}:

{pstd}{ul:Summary}

{synoptset 34 tabbed}{...}
{synopt:{cmd:r(n_tests)}}total number of tests run{p_end}
{synopt:{cmd:r(n_pass)}}number of tests passed{p_end}
{synopt:{cmd:r(n_fail)}}number of tests failed{p_end}
{synopt:{cmd:r(n_skip)}}number of tests skipped{p_end}
{synopt:{cmd:r(overall_pass)}}1 if all passed, 0 if any failed, {cmd:.} if inconclusive{p_end}

{pstd}{ul:Parallel trends}

{synopt:{cmd:r(pretrend_F)}}pre-trend F-statistic{p_end}
{synopt:{cmd:r(pretrend_p)}}pre-trend p-value{p_end}
{synopt:{cmd:r(pretrend_pass)}}1 if pre-trend test passed{p_end}
{synopt:{cmd:r(pretrend_skipped)}}1 if pre-trend test was skipped{p_end}

{pstd}{ul:KS test (pooled)}

{synopt:{cmd:r(ks_D)}}KS test statistic{p_end}
{synopt:{cmd:r(ks_p)}}KS test p-value{p_end}
{synopt:{cmd:r(ks_pass)}}1 if KS test passed{p_end}
{synopt:{cmd:r(ks_D_treat)}}KS statistic for treated subsample{p_end}
{synopt:{cmd:r(ks_p_treat)}}KS p-value for treated subsample{p_end}
{synopt:{cmd:r(ks_D_plus)}}one-sided KS D+ statistic{p_end}
{synopt:{cmd:r(ks_p_plus)}}p-value for D+{p_end}
{synopt:{cmd:r(ks_D_minus)}}one-sided KS D- statistic{p_end}
{synopt:{cmd:r(ks_p_minus)}}p-value for D-{p_end}
{synopt:{cmd:r(ks_N_treated)}}treated observations in KS test{p_end}
{synopt:{cmd:r(ks_N_control)}}control observations in KS test{p_end}
{synopt:{cmd:r(prewindow)}}pre-treatment window used{p_end}

{pstd}{ul:KS test (group-level)}

{synopt:{cmd:r(ks_D_group)}}group-level KS statistic{p_end}
{synopt:{cmd:r(ks_D1_group)}}group 1 KS statistic{p_end}
{synopt:{cmd:r(ks_D2_group)}}group 2 KS statistic{p_end}
{synopt:{cmd:r(ks_p_group)}}group-level KS p-value{p_end}
{synopt:{cmd:r(group_pass)}}1 if group test passed{p_end}
{synopt:{cmd:r(n_treated_pretreat)}}treated pre-treatment observations{p_end}
{synopt:{cmd:r(n_control_group)}}control group observations{p_end}
{synopt:{cmd:r(min_pretreat_year)}}minimum pre-treatment year{p_end}
{synopt:{cmd:r(max_pretreat_year)}}maximum pre-treatment year{p_end}
{synopt:{cmd:r(group_stability_skipped)}}1 if group stability skipped{p_end}
{synopt:{cmd:r(group_stability_fallback)}}1 if fallback used{p_end}
{synopt:{cmd:r(group_prewindow)}}group pre-treatment window{p_end}

{pstd}{ul:Normality diagnostics}

{synopt:{cmd:r(norm_pass)}}1 if normality test passed{p_end}
{synopt:{cmd:r(ks_D_norm)}}KS normality statistic{p_end}
{synopt:{cmd:r(ks_p_norm)}}KS normality p-value{p_end}
{synopt:{cmd:r(sktest_chi2)}}skewness-kurtosis chi-squared{p_end}
{synopt:{cmd:r(sktest_p)}}skewness-kurtosis p-value{p_end}
{synopt:{cmd:r(N_eps0_norm)}}sample size for normality test{p_end}
{synopt:{cmd:r(eps0_mean)}}eps0 mean{p_end}
{synopt:{cmd:r(eps0_sd)}}eps0 standard deviation{p_end}
{synopt:{cmd:r(eps0_skewness)}}eps0 skewness{p_end}
{synopt:{cmd:r(eps0_kurtosis)}}eps0 kurtosis{p_end}

{pstd}{ul:Conditional and Assumption 3.3}

{synopt:{cmd:r(conditional_pass)}}1 if conditional test passed{p_end}
{synopt:{cmd:r(assumption33_pass)}}1 if Assumption 3.3 passed{p_end}

{pstd}{ul:Sample composition}

{synopt:{cmd:r(n_stable_0)}}stable control observations{p_end}
{synopt:{cmd:r(n_stable_1)}}stable treated observations{p_end}
{synopt:{cmd:r(n_transition)}}transition observations{p_end}
{synopt:{cmd:r(n_trans_in)}}transition-in observations{p_end}
{synopt:{cmd:r(n_trans_out)}}transition-out observations{p_end}
{synopt:{cmd:r(n_first_period)}}first-period observations{p_end}
{synopt:{cmd:r(n_valid)}}valid observations{p_end}
{synopt:{cmd:r(pct_transition)}}percent transition{p_end}

{pstd}{ul:Macros}

{synopt:{cmd:r(group_sample_type)}}sample type for group tests{p_end}
{synoptline}


{marker examples}{...}
{title:Examples}

{phang}{cmd:. pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) pfunc(cd)}{p_end}
{phang}{cmd:. pte_diagnose}{p_end}
{phang}{cmd:. pte_diagnose, kstest}{p_end}
{phang}{cmd:. pte_diagnose, parallel preperiods(3)}{p_end}
{phang}{cmd:. pte_diagnose, cdf saving(eps0_cdf.gph)}{p_end}


{title:Author}

{pstd}
Xuanyu Cai, City University of Macau.{break}
Email: {browse "mailto:xuanyuCAI@outlook.com":xuanyuCAI@outlook.com}


{title:Also see}

{psee}
{space 2}Help:  {helpb pte}, {helpb pte_setup}, {helpb pte_graph}
{p_end}
