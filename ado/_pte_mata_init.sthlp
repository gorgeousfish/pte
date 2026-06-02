{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] pte troubleshooting" "help pte_troubleshooting"}{...}
{viewerjumpto "Syntax" "_pte_mata_init##syntax"}{...}
{viewerjumpto "Description" "_pte_mata_init##description"}{...}
{viewerjumpto "Options" "_pte_mata_init##options"}{...}
{viewerjumpto "Stored results" "_pte_mata_init##results"}{...}
{viewerjumpto "Error codes" "_pte_mata_init##errors"}{...}
{viewerjumpto "Examples" "_pte_mata_init##examples"}{...}
{title:Title}

{p2colset 5 28 30 2}{...}
{p2col:{cmd:_pte_mata_init} {hline 2}}Initialize Mata functions for the PTE package{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_mata_init}
[{cmd:,} {it:options}]

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt force}}recompile even if functions already loaded{p_end}
{synopt:{opt verbose}}display detailed progress information{p_end}
{synopt:{opt nolog}}suppress all non-error output{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_mata_init} compiles and loads all required Mata functions for the
PTE package. It is called automatically by {cmd:pte} before estimation begins.

{pstd}
The initialization process:

{phang2}1. Checks if required Mata functions are already loaded{p_end}
{phang2}2. If not (or if {opt force} specified), finds and compiles .mata source files{p_end}
{phang2}3. Verifies all required functions are available after compilation{p_end}

{pstd}
Required baseline runtime objects include GMM_CLK(), matrix construction
utilities, optimizer drivers, and the {cmd:OptimizationResult()} struct used
by the optimizer entry chain. The ready-runtime check also requires the
package-owned {cmd:_pte_runtime_signature()} marker and the official
{cmd:generate_grid()} CD/translog semantics so foreign same-name preloads
cannot masquerade as the live PTE bundle. Optional functions
(simulation, bootstrap, MC DGP, heterogeneity Q-test, and divergent
counterfactual simulation) are compiled if their source files are found.


{marker options}{...}
{title:Options}

{phang}
{opt force} forces recompilation of all .mata files even if functions are
already loaded in memory. Useful after updating .mata source files. If a
force rebuild fails after a previously certified runtime was already loaded,
{cmd:_pte_mata_init} preserves that last-known-good runtime and still returns
an error for the failed rebuild attempt.

{phang}
{opt verbose} displays detailed progress including which functions are
detected, which files are compiled, and their source locations.

{phang}
{opt nolog} suppresses all output except error messages. This is the default
when called from {cmd:pte}.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_mata_init} stores the following in {cmd:r()}:

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars}{p_end}
{synopt:{cmd:r(compiled)}}1 if compilation was performed, 0 if skipped{p_end}
{synopt:{cmd:r(all_loaded)}}1 if all required functions are loaded{p_end}
{synopt:{cmd:r(n_compiled)}}number of files successfully compiled{p_end}
{synopt:{cmd:r(n_failed)}}number of files that failed to compile{p_end}


{marker errors}{...}
{title:Error codes}

{synoptset 10 tabbed}{...}
{synopt:601}Mata source file not found{p_end}
{synopt:602}Mata compilation syntax error{p_end}
{synopt:603}Stata version incompatible (requires 14.0+){p_end}
{synopt:604}Insufficient memory for compilation{p_end}
{synopt:605}Function name conflict{p_end}
{synopt:606}Function not found after compilation{p_end}

{pstd}
Use {cmd:_pte_mata_error} {it:#} to display detailed error messages with
recovery suggestions.


{marker examples}{...}
{title:Examples}

{phang}{cmd:. _pte_mata_init}{p_end}
{phang}{cmd:. _pte_mata_init, verbose}{p_end}
{phang}{cmd:. _pte_mata_init, force verbose}{p_end}

{pstd}Check function status:{p_end}
{phang}{cmd:. _pte_mata_check, verbose}{p_end}

{pstd}Clean all functions and reinitialize:{p_end}
{phang}{cmd:. _pte_mata_clean, all confirm}{p_end}
{phang}{cmd:. _pte_mata_init, force}{p_end}


{title:Also see}

{psee}
{space 2}Help:  {manhelp pte PTE}, {manhelp mata M}
{p_end}
