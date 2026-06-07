{smcl}
{* *! version 1.0.0  01jan2026}{...}
{viewerjumpto "Syntax" "_pte_nonabs_ereturn##syntax"}{...}
{viewerjumpto "Description" "_pte_nonabs_ereturn##description"}{...}
{viewerjumpto "Options" "_pte_nonabs_ereturn##options"}{...}
{viewerjumpto "Stored results" "_pte_nonabs_ereturn##results"}{...}
{viewerjumpto "Examples" "_pte_nonabs_ereturn##examples"}{...}
{viewerjumpto "References" "_pte_nonabs_ereturn##references"}{...}
{title:Title}

{p2colset 5 35 37 2}{...}
{p2col:{cmd:_pte_nonabs_ereturn} {hline 2}}Store non-absorbing treatment effect
results in e() (internal){p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_nonabs_ereturn}{cmd:,}
{opt atts:witchin(matname)}
{opt attswitchins:e(matname)}
{opt attswitcho:ut(matname)}
{opt attswitchouts:e(matname)}
{opt ns:witchin(#)}
{opt nswitcho:ut(#)}
{opt attp:eriods(matname)}
{opt persist:periods(#)}
[{it:options}]

{pstd}
This is an internal {cmd:eclass} program called by {cmd:_pte_main} after
non-absorbing treatment estimation. Users should not call this program
directly.

{synoptset 32 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt atts:witchin(matname)}}ATT{sup:+} matrix, (L+2){it:x}3 [period,
ATT, N_firms]{p_end}
{synopt:{opt attswitchins:e(matname)}}ATT{sup:+} bootstrap SE matrix,
(L+2){it:x}1{p_end}
{synopt:{opt attswitcho:ut(matname)}}ATT{sup:-} matrix, (L+2){it:x}3 [period,
ATT, N_firms]{p_end}
{synopt:{opt attswitchouts:e(matname)}}ATT{sup:-} bootstrap SE matrix,
(L+2){it:x}1{p_end}
{synopt:{opt ns:witchin(#)}}number of entry events (G=+1){p_end}
{synopt:{opt nswitcho:ut(#)}}number of exit events (G=-1); 0 implies
absorbing{p_end}
{synopt:{opt attp:eriods(matname)}}ATT evaluation periods matrix,
1{it:x}(L+1){p_end}
{synopt:{opt persist:periods(#)}}persistence requirement for treatment
classification{p_end}

{syntab:Shock distribution}
{synopt:{opt sigmaeps0(#)}}std. dev. of control-group productivity shock{p_end}
{synopt:{opt sigmaeps1(#)}}std. dev. of treated-group productivity shock{p_end}
{synopt:{opt sigmaeps0trim(#)}}trimmed std. dev. of control-group shock{p_end}
{synopt:{opt sigmaeps1trim(#)}}trimmed std. dev. of treated-group shock{p_end}

{syntab:Bootstrap}
{synopt:{opt nb:oot(#)}}number of bootstrap replications{p_end}
{synopt:{opt bootf:ailed(#)}}number of failed bootstrap iterations{p_end}
{synopt:{opt ciswitchinl(matname)}}ATT{sup:+} lower CI bound matrix{p_end}
{synopt:{opt ciswitchinu(matname)}}ATT{sup:+} upper CI bound matrix{p_end}
{synopt:{opt ciswitchoutl(matname)}}ATT{sup:-} lower CI bound matrix{p_end}
{synopt:{opt ciswitchoutu(matname)}}ATT{sup:-} upper CI bound matrix{p_end}

{syntab:Metadata}
{synopt:{opt nt:otal(#)}}total number of observations{p_end}
{synopt:{opt touse(name)}}exact existing estimation-sample marker; abbreviation
fallback is rejected{p_end}
{synopt:{opt cmdline(string)}}full command line for replay{p_end}
{synopt:{opt v:erbose}}display additional diagnostic messages{p_end}
{synoptline}

{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_nonabs_ereturn} stores non-absorbing treatment effect estimation
results in {cmd:e()} for downstream use by {cmd:pte_graph}, {cmd:esttab},
and other post-estimation commands. It is the final step in the non-absorbing
estimation pipeline, called after ATT{sup:+} (entry switch effects) and
ATT{sup:-} (staying-treated counterfactuals for exit switchers) have been
computed.

{pstd}
The program performs the following:

{p 8 12 2}1. {bf:Input validation}: checks matrix dimensions for consistency
(ATT rows = periods + 1, correct column counts).{p_end}

{p 8 12 2}2. {bf:Absorbing detection}: if {opt nswitchout(0)}, the treatment is
classified as absorbing. ATT{sup:-} matrices are set to missing, and
{cmd:e(b)}/{cmd:e(V)} contain only ATT{sup:+} estimates.{p_end}

{p 8 12 2}3. {bf:Sign consistency diagnostic}: for non-absorbing treatments,
issues warning {bf:W-3027} if ATT{sup:+} and ATT{sup:-} have opposite signs
at nt=0, which may indicate asymmetric treatment effects.{p_end}

{p 8 12 2}4. {bf:esttab-compatible matrices}: constructs {cmd:e(b)} and
{cmd:e(V)} suitable for {cmd:esttab} and {cmd:estout}. For non-absorbing
treatments, ATT{sup:+} and ATT{sup:-} period estimates are concatenated
into a single coefficient vector with a block-diagonal variance matrix.{p_end}

{p 8 12 2}5. {bf:Formatted output}: displays summary tables with ATT
estimates, standard errors, significance stars, and optional confidence
intervals for each period.{p_end}

{marker options}{...}
{title:Options}

{dlgtab:Required}

{phang}
{opt attswitchin(matname)} specifies the ATT{sup:+} results matrix with
dimensions (L+2){it:x}3. Each row corresponds to a period (nt=0, 1, ..., L)
plus an average row. Columns are: period index, ATT estimate, and number of
contributing firms.

{phang}
{opt attswitchinse(matname)} specifies the ATT{sup:+} standard error matrix
with dimensions (L+2){it:x}1, one SE per period plus the average.

{phang}
{opt attswitchout(matname)} specifies the ATT{sup:-} results matrix with
the same structure as {opt attswitchin()}. For absorbing treatments, pass a
conformable matrix (values are replaced with missing).

{phang}
{opt attswitchoutse(matname)} specifies the ATT{sup:-} standard error matrix
with the same structure as {opt attswitchinse()}.

{phang}
{opt nswitchin(#)} is the number of entry events (firms switching into
treatment, G=+1). Must be positive.

{phang}
{opt nswitchout(#)} is the number of exit events (firms switching out of
treatment, G=-1). When set to 0, the program treats the design as absorbing
and suppresses ATT{sup:-} output.

{phang}
{opt attperiods(matname)} specifies a 1{it:x}(L+1) matrix of ATT evaluation
periods (e.g., 0, 1, 2, ..., L).

{phang}
{opt persistperiods(#)} is the persistence requirement used in treatment
classification.

{phang}
Negative standard errors are rejected with error {bf:E-3025}.

{dlgtab:Shock distribution}

{phang}
{opt sigmaeps0(#)} stores the standard deviation of the control-group
productivity shock (epsilon-zero). Stored only if positive.

{phang}
{opt sigmaeps1(#)} stores the standard deviation of the treated-group
productivity shock. Stored only for non-absorbing treatments.

{phang}
{opt sigmaeps0trim(#)} and {opt sigmaeps1trim(#)} store the trimmed
(Winsorized 1-99%) versions of the shock standard deviations.

{dlgtab:Bootstrap}

{phang}
{opt nboot(#)} specifies the number of bootstrap replications performed.
When positive, bootstrap-related scalars and CI matrices are stored.

{phang}
{opt bootfailed(#)} records the number of failed bootstrap iterations.
If all iterations fail, the program exits with error {bf:E-3026}.

{phang}
{opt ciswitchinl(matname)} and {opt ciswitchinu(matname)} specify the lower
and upper confidence interval bound matrices for ATT{sup:+}.

{phang}
{opt ciswitchoutl(matname)} and {opt ciswitchoutu(matname)} specify the lower
and upper confidence interval bound matrices for ATT{sup:-}. Ignored for
absorbing treatments.

{dlgtab:Metadata}

{phang}
{opt ntotal(#)} stores the total number of observations in the estimation
sample.

{phang}
{opt touse(name)} specifies the estimation sample indicator variable by its
exact existing name. Abbreviation fallback is rejected, so
{cmd:touse(keep)} fails unless the dataset really contains a variable named
{cmd:keep}.
passed to {cmd:ereturn post} for {cmd:e(sample)} marking.

{phang}
{opt cmdline(string)} stores the full command line for result replay.

{phang}
{opt verbose} displays additional diagnostic messages, including a note
when absorbing treatment is detected.

{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_nonabs_ereturn} stores the following in {cmd:e()}:

{synoptset 28 tabbed}{...}
{p2col 5 28 32 2: Scalars}{p_end}
{synopt:{cmd:e(n_switchin)}}number of entry events{p_end}
{synopt:{cmd:e(n_switchout)}}number of exit events (0 if absorbing){p_end}
{synopt:{cmd:e(absorbing)}}1 if absorbing treatment, 0 otherwise{p_end}
{synopt:{cmd:e(persistperiods)}}persistence requirement{p_end}
{synopt:{cmd:e(sigma_eps0)}}control-group shock std. dev. (if positive){p_end}
{synopt:{cmd:e(sigma_eps1)}}treated-group shock std. dev. (non-absorbing, if
positive){p_end}
{synopt:{cmd:e(sigma_eps0_trim)}}trimmed control-group shock std. dev. (if
positive){p_end}
{synopt:{cmd:e(sigma_eps1_trim)}}trimmed treated-group shock std. dev.
(non-absorbing, if positive){p_end}
{synopt:{cmd:e(nboot)}}number of bootstrap replications (if bootstrap){p_end}
{synopt:{cmd:e(boot_failed)}}number of failed bootstrap iterations (if
bootstrap){p_end}
{synopt:{cmd:e(N_total)}}total observations (if specified){p_end}

{p2col 5 28 32 2: Macros}{p_end}
{synopt:{cmd:e(treatment_type)}}{bf:absorbing} or {bf:nonabsorbing}{p_end}
{synopt:{cmd:e(cmd)}}{bf:pte}{p_end}
{synopt:{cmd:e(cmdline)}}full command line (if specified){p_end}

{p2col 5 28 32 2: Matrices}{p_end}
{synopt:{cmd:e(att_switchin)}}ATT{sup:+} estimates, (L+2){it:x}3{p_end}
{synopt:{cmd:e(att_switchin_se)}}ATT{sup:+} standard errors, (L+2){it:x}1{p_end}
{synopt:{cmd:e(att_switchout)}}ATT{sup:-} estimates, (L+2){it:x}3; missing if
absorbing{p_end}
{synopt:{cmd:e(att_switchout_se)}}ATT{sup:-} standard errors, (L+2){it:x}1;
missing if absorbing{p_end}
{synopt:{cmd:e(attperiods)}}evaluation periods, 1{it:x}(L+1){p_end}
{synopt:{cmd:e(b)}}coefficient vector for {cmd:esttab} compatibility{p_end}
{synopt:{cmd:e(V)}}variance matrix for {cmd:esttab} compatibility{p_end}
{synopt:{cmd:e(att_switchin_ci_l)}}ATT{sup:+} lower CI bounds (if
bootstrap){p_end}
{synopt:{cmd:e(att_switchin_ci_u)}}ATT{sup:+} upper CI bounds (if
bootstrap){p_end}
{synopt:{cmd:e(att_switchout_ci_l)}}ATT{sup:-} lower CI bounds (if bootstrap,
non-absorbing){p_end}
{synopt:{cmd:e(att_switchout_ci_u)}}ATT{sup:-} upper CI bounds (if bootstrap,
non-absorbing){p_end}

{pstd}
{bf:Note on e(b) and e(V) structure:}

{pstd}
For absorbing treatments, {cmd:e(b)} contains L+1 elements named
{bf:ATT_plus_0}, {bf:ATT_plus_1}, ..., {bf:ATT_plus_L} (period estimates
only, excluding the average row).

{pstd}
For non-absorbing treatments, {cmd:e(b)} contains 2(L+1) elements:
{bf:ATT_plus_0}, ..., {bf:ATT_plus_L}, {bf:ATT_minus_0}, ...,
{bf:ATT_minus_L}. The variance matrix {cmd:e(V)} is block-diagonal with
ATT{sup:+} variances in the upper-left block and ATT{sup:-} variances in
the lower-right block.

{marker examples}{...}
{title:Examples}

{pstd}
This program is not intended for direct use. It is called internally by
{cmd:_pte_main} after non-absorbing ATT estimation. The following
illustrates the typical calling pattern within the pte pipeline:

{phang2}{cmd:. // After computing ATT+ and ATT- matrices:}{p_end}
{phang2}{cmd:. _pte_nonabs_ereturn, attswitchin(att_plus) attswitchinse(se_plus) ///}{p_end}
{phang2}{cmd:.     attswitchout(att_minus) attswitchoutse(se_minus) ///}{p_end}
{phang2}{cmd:.     nswitchin(150) nswitchout(80) ///}{p_end}
{phang2}{cmd:.     attperiods(periods) persistperiods(2)}{p_end}

{pstd}
With bootstrap CIs and metadata:

{phang2}{cmd:. _pte_nonabs_ereturn, attswitchin(att_plus) attswitchinse(se_plus) ///}{p_end}
{phang2}{cmd:.     attswitchout(att_minus) attswitchoutse(se_minus) ///}{p_end}
{phang2}{cmd:.     nswitchin(150) nswitchout(80) ///}{p_end}
{phang2}{cmd:.     attperiods(periods) persistperiods(2) ///}{p_end}
{phang2}{cmd:.     nboot(500) bootfailed(3) ///}{p_end}
{phang2}{cmd:.     ciswitchinl(ci_p_l) ciswitchinu(ci_p_u) ///}{p_end}
{phang2}{cmd:.     ciswitchoutl(ci_m_l) ciswitchoutu(ci_m_u) ///}{p_end}
{phang2}{cmd:.     sigmaeps0(0.25) sigmaeps1(0.30) ///}{p_end}
{phang2}{cmd:.     cmdline("pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) nonabsorbing")}{p_end}

{pstd}
Absorbing case (nswitchout = 0):

{phang2}{cmd:. _pte_nonabs_ereturn, attswitchin(att_plus) attswitchinse(se_plus) ///}{p_end}
{phang2}{cmd:.     attswitchout(att_dummy) attswitchoutse(se_dummy) ///}{p_end}
{phang2}{cmd:.     nswitchin(200) nswitchout(0) ///}{p_end}
{phang2}{cmd:.     attperiods(periods) persistperiods(2) verbose}{p_end}

{pstd}
After calling, results are available via standard post-estimation:

{phang2}{cmd:. ereturn list}{p_end}
{phang2}{cmd:. matrix list e(att_switchin)}{p_end}
{phang2}{cmd:. di e(treatment_type)}{p_end}
{phang2}{cmd:. pte_graph}{p_end}

{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z. & Schurter, K. (2026).
Productivity Treatment Effects.
{it:Working Paper}. Appendix C.3 (Non-absorbing Treatment Extension),
Section 4.4 (Non-absorbing Treatment), Proposition 4.3 (ATT Estimation).
{p_end}

{title:Also see}

{psee}
{space 2}Help:  {help pte:pte}, {help pte_graph:pte_graph},
{help _pte_graph_att_nonabs:_pte_graph_att_nonabs}
{p_end}
