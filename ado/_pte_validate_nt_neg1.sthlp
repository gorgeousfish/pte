{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "" "--"}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] _pte_att" "help _pte_att"}{...}
{viewerjumpto "Syntax" "_pte_validate_nt_neg1##syntax"}{...}
{viewerjumpto "Description" "_pte_validate_nt_neg1##description"}{...}
{viewerjumpto "Options" "_pte_validate_nt_neg1##options"}{...}
{viewerjumpto "Stored results" "_pte_validate_nt_neg1##results"}{...}
{viewerjumpto "Errors" "_pte_validate_nt_neg1##errors"}{...}
{viewerjumpto "Examples" "_pte_validate_nt_neg1##examples"}{...}

{title:Title}

{phang}
{bf:_pte_validate_nt_neg1} {hline 2} Validate nt=-1 observations for ATT estimation


{marker syntax}{...}
{title:Syntax}

{p 8 32 2}
{cmd:_pte_validate_nt_neg1}{cmd:,}
{opt firm(varname)}
{opt nt(varname)}
[{opt omega(varname)}]
[{opt verbose}]
[{opt debug}]


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_validate_nt_neg1} validates that nt=-1 observations exist and are
complete for all treated firms in the current dataset. This validation is
required before ATT estimation because the counterfactual simulation
(Proposition 4.3) starts from the lagged productivity value at nt=0.
The nt=0 counterfactual is deterministic under Proposition 4.1 / C.1;
simulated epsilon-zero shocks enter only when recursing to nt>=1.
Both the main ATT simulation and cohort instant objects require nt=-1
to be present.

{pstd}
If some firms are missing nt=-1 while others are complete, the current live
implementation issues a warning, drops the incomplete firms from the working
dataset, and continues with the validated sample. A hard error is raised only
when no nt=-1 observations exist at all, or when none remain after incomplete
firms are dropped.

{pstd}
In short: firms with missing nt=-1 are {bf:warning and dropped}, not treated
as an automatic fatal error when other valid firms remain.

{pstd}
When {opt omega()} is supplied, the helper also requires an observed
omega at nt=-1 for each firm because the ATT simulation starts from the
realized pre-treatment productivity anchor. Firms that have an nt=-1 row
but missing observed omega at that anchor are warned and dropped even when
{opt debug} is omitted.

{pstd}
The validation performs four checks:

{phang2}1. {bf:Existence check}: At least one nt=-1 observation exists in the data.{p_end}

{phang2}2. {bf:Completeness check}: Every treated firm should have an nt=-1
observation. Firms that fail this check are reported, dropped, and excluded
from subsequent ATT simulation.{p_end}

{phang2}3. {bf:Observed omega anchor check}: When {opt omega()} is supplied,
every treated firm must also have observed omega at nt=-1. Firms that fail
this check are reported, dropped, and excluded from subsequent ATT
simulation even outside debug mode.{p_end}

{phang2}4. {bf:L.omega check} (debug mode only, when {opt omega()} is supplied):
L.omega at nt=0 equals omega at nt=-1 for each firm, with tolerance 1e-10.{p_end}


{marker options}{...}
{title:Options}

{phang}
{opt firm(varname)} specifies the exact firm identifier variable. Required.

{phang}
{opt nt(varname)} specifies the exact relative time variable in panel periods,
typically {cmd:(time - treat_year) / delta()} from the active {cmd:xtset}.
Required.

{phang}
{opt omega(varname)} specifies the exact productivity variable. When supplied,
the helper requires an observed omega anchor at nt=-1 for every firm and
uses the same variable for the optional L.omega validation in debug mode.

{phang}
{opt verbose} displays detailed progress messages during validation.

{phang}
{opt debug} enables the L.omega correctness check (Step 4). If
{opt omega()} is omitted, the debug flag is ignored and the command
only performs the nt=-1 existence/completeness validation. When
{opt omega()} is supplied, the observed nt=-1 omega-anchor check still runs
even if {opt debug} is omitted.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_validate_nt_neg1} stores the following in {cmd:r()}:

{synoptset 16 tabbed}{...}
{p2col 5 16 20 2: Scalars}{p_end}
{synopt:{cmd:r(n_neg1)}}number of nt=-1 observations{p_end}
{synopt:{cmd:r(n_firms)}}number of validated firms{p_end}
{synopt:{cmd:r(valid)}}validation status (1 = passed){p_end}


{marker errors}{...}
{title:Error codes}

{pstd}
{bf:E-3002}: Missing nt=-1 observations{break}
Raised only when no nt=-1 observations exist in the data, or when none
remain after dropping firms with incomplete nt=-1 histories. If only some
treated firms are missing nt=-1, the program warns, drops those firms, and
continues with the validated sample. Check that the data includes
year = treat_year - 1 for all treated firms kept for ATT estimation. When
{opt omega()} is supplied, the same error can also arise after the helper
drops firms whose nt=-1 row exists but lacks observed omega at the anchor.

{pstd}
{bf:E-3003}: L.omega mismatch{break}
L.omega at nt=0 does not equal omega at nt=-1 for one or more firms.
This indicates a panel sorting or tsset configuration problem.
Check that the data is correctly sorted and tsset.


{marker examples}{...}
{title:Examples}

{phang}{cmd:. _pte_validate_nt_neg1, firm(firm_id) nt(_pte_nt)}{p_end}

{phang}{cmd:. _pte_validate_nt_neg1, firm(firm_id) nt(_pte_nt) omega(omega) verbose}{p_end}

{phang}{cmd:. _pte_validate_nt_neg1, firm(firm_id) nt(_pte_nt) omega(omega) verbose debug}{p_end}

{phang}Check return values:{p_end}
{phang}{cmd:. return list}{p_end}
{phang}{cmd:. display r(n_neg1)}{p_end}
{phang}{cmd:. display r(n_firms)}{p_end}


{title:Theory}

{pstd}
The main {_bf:_pte_att} simulation worker starts from the lagged
productivity value at nt=0. Proposition 4.1 / C.1 identifies the
onset counterfactual from the untreated conditional mean, so the nt=0
counterfactual is deterministic in the main ATT simulation. Simulated
epsilon-zero shocks enter only when recursing to nt>=1. For the main
simulation chain, the nt=0 counterfactual is:

{pmore}
omega_0 = h_bar_0(L.omega)

{pstd}
where L.omega at nt=0 retrieves the observed productivity at nt=-1.
Firms without nt=-1 cannot supply this starting value, so they are removed
from the validated ATT sample. The helper only aborts when no valid nt=-1
starting points remain.


{title:Also see}

{psee}
{manhelp xtset XT}, {manhelp tsset TS}
{p_end}
