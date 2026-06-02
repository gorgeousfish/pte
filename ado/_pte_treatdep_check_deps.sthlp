{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] pte_check_deps" "help pte_check_deps"}{...}
{viewerjumpto "Syntax" "_pte_treatdep_check_deps##syntax"}{...}
{viewerjumpto "Description" "_pte_treatdep_check_deps##description"}{...}
{viewerjumpto "Options" "_pte_treatdep_check_deps##options"}{...}
{viewerjumpto "Stored results" "_pte_treatdep_check_deps##results"}{...}
{viewerjumpto "Error codes" "_pte_treatdep_check_deps##errors"}{...}
{viewerjumpto "Examples" "_pte_treatdep_check_deps##examples"}{...}
{viewerjumpto "References" "_pte_treatdep_check_deps##references"}{...}
{title:Title}

{p2colset 5 42 44 2}{...}
{p2col:{cmd:_pte_treatdep_check_deps} {hline 2}}Dependency check for treatment-dependent production function estimation{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 40 2}
{cmd:_pte_treatdep_check_deps}
[{cmd:,}
{it:options}]

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt detail}}display detailed check results{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_treatdep_check_deps} verifies that the required dependencies are
available before running treatment-dependent production function estimation
via {cmd:endopolyprodest}. It is called automatically at the entry of
{cmd:_pte_treatdep_call_endopoly} (and therefore on the public
{cmd:pte, treatdependent} path) and exits with an error when the hard
requirements are not met.

{pstd}
The command performs five checks:

{p 8 12 2}
{it:Check 1}: whether the optional {cmd:prodest} package is installed. This is
reported for environment diagnostics only.{p_end}
{p 8 12 2}
{it:Check 2}: {cmd:endopolyprodest} command is available, either permanently
installed or defined in the current session. This is a hard requirement.{p_end}
{p 8 12 2}
{it:Check 3}: the package-owned {cmd:_pte_mata_endopoly_patch.do} file is
available and loads successfully. This is a hard requirement because the
official {cmd:endopolyprodest} source is not runnable without the
compatibility patch.{p_end}
{p 8 12 2}
{it:Check 4}: the runnable treatdependent companion Mata contract is
materialized. After the upstream source is prepared and the package-owned
patch is applied, the live runtime must expose
{cmd:facf1()}, {cmd:facf2()}, {cmd:facf3()}, and {cmd:opt_mata()}.{p_end}
{p 8 12 2}
{it:Check 5}: Stata version is 14.0 or higher. This is a hard requirement.{p_end}

{pstd}
If {cmd:_pte_error} (US-E4-015) is available, errors are reported through
the unified error handling framework. Otherwise, the command degrades
gracefully to {cmd:di as error} with {cmd:exit}.

{pstd}
Without the {opt detail} option, the command runs silently when all
hard requirements are satisfied.


{marker options}{...}
{title:Options}

{phang}
{opt detail} displays a formatted report showing the result of each
dependency check, including a header, individual check lines, and a summary
message. When {cmd:prodest} is absent but the hard requirements are met, the
report shows this as an informational advisory rather than a failure.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_treatdep_check_deps} stores the following in {cmd:r()}:

{synoptset 35 tabbed}{...}
{p2col 5 35 39 2: Scalars}{p_end}
{synopt:{cmd:r(prodest_found)}}1 if {cmd:prodest} is installed, 0 otherwise{p_end}
{synopt:{cmd:r(endopolyprodest_found)}}1 if {cmd:endopolyprodest} is available, 0 otherwise{p_end}
{synopt:{cmd:r(treatdep_prepare_rc)}}return code from {cmd:_pte_treatdep_prepare_runtime}{p_end}
{synopt:{cmd:r(treatdep_patch_ready)}}1 if {cmd:_pte_mata_endopoly_patch.do} loaded successfully, 0 otherwise{p_end}
{synopt:{cmd:r(treatdep_patch_rc)}}return code from loading {cmd:_pte_mata_endopoly_patch.do}{p_end}
{synopt:{cmd:r(treatdep_source_loaded)}}1 if the upstream source was loaded during runtime preparation, 0 otherwise{p_end}
{synopt:{cmd:r(treatdep_source_rc)}}return code from loading the upstream source{p_end}
{synopt:{cmd:r(treatdep_contract_ready)}}1 if the live companion Mata contract is ready, 0 otherwise{p_end}
{synopt:{cmd:r(stata_version)}}current Stata version number (e.g., 17.0){p_end}
{synopt:{cmd:r(stata_version_ok)}}1 if Stata version >= 14.0, 0 otherwise{p_end}
{synopt:{cmd:r(all_checks_passed)}}1 if the hard requirements ({cmd:endopolyprodest}, the treatdependent patch, the live companion contract, and Stata version) are satisfied, 0 otherwise{p_end}

{p2col 5 35 39 2: Macros}{p_end}
{synopt:{cmd:r(treatdep_patch_file)}}resolved path to {cmd:_pte_mata_endopoly_patch.do}{p_end}
{synopt:{cmd:r(treatdep_source_file)}}resolved path to the upstream {cmd:endopolyprodest} source{p_end}

{pstd}
When the command exits due to a failed check, partial return values are
set for the checks completed before the failure, including the populated
runtime-prepare trace slots from Check 3 when that helper has already run.


{marker errors}{...}
{title:Error codes}

{pstd}
The following error codes may be issued:

{synoptset 15 tabbed}{...}
{p2col 5 15 19 2: Code}{p_end}
{synopt:{bf:E-199}}{cmd:endopolyprodest} not found. Load the official source
with {cmd:run DOs/treatpolyprodest.ado}. Exit code 199.{p_end}
{synopt:{bf:E-601}}the package-owned
{cmd:_pte_mata_endopoly_patch.do} file is missing or failed to load, or the
live companion Mata contract is still incomplete after runtime preparation.
Exit code 601.{p_end}
{synopt:{bf:E-009}}Stata version is below 14.0. Upgrade Stata or use
standard {cmd:pte} without the {opt treatdependent} option.
Exit code 9.{p_end}


{marker examples}{...}
{title:Examples}

{pstd}Silent check (no output when all dependencies are satisfied){p_end}
{phang2}{cmd:. _pte_treatdep_check_deps}{p_end}

{pstd}Detailed check with formatted report{p_end}
{phang2}{cmd:. _pte_treatdep_check_deps, detail}{p_end}

{pstd}Inspect return values after check{p_end}
{phang2}{cmd:. _pte_treatdep_check_deps}{p_end}
{phang2}{cmd:. return list}{p_end}
{phang2}{cmd:. display "All passed: " r(all_checks_passed)}{p_end}

{pstd}Use in a program to guard execution{p_end}
{phang2}{cmd:. capture _pte_treatdep_check_deps}{p_end}
{phang2}{cmd:. if _rc != 0 {c -(}}{p_end}
{phang2}{cmd:.     display as error "Dependencies not met, aborting."}{p_end}
{phang2}{cmd:.     exit _rc}{p_end}
{phang2}{cmd:. {c )-}}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, X., Liao, Z. & Schurter, K. (2026).
Productivity Treatment Effects.
{it:Working Paper}, Section 5.2 and Appendix C.1.
{p_end}

{phang}
See also {cmd:DOs/treatpolyprodest.ado} for the reference implementation
of {cmd:endopolyprodest}.
{p_end}
{smcl}
