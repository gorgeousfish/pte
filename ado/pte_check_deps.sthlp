{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{vieweralsosee "[PTE] _pte_treatdep_check_deps" "help _pte_treatdep_check_deps"}{...}
{viewerjumpto "Syntax" "pte_check_deps##syntax"}{...}
{viewerjumpto "Description" "pte_check_deps##description"}{...}
{viewerjumpto "Options" "pte_check_deps##options"}{...}
{viewerjumpto "Core vs extended dependencies" "pte_check_deps##groups"}{...}
{viewerjumpto "Stored results" "pte_check_deps##results"}{...}
{viewerjumpto "Examples" "pte_check_deps##examples"}{...}
{viewerjumpto "References" "pte_check_deps##references"}{...}
{title:Title}

{p2colset 5 30 32 2}{...}
{p2col:{cmd:pte_check_deps} {hline 2}}Check all dependencies for the pte package{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 30 2}
{cmd:pte_check_deps}
[{cmd:,}
{it:options}]

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt detail}}display detailed check results including file locations{p_end}
{synopt:{opt treatdependent}}additionally check the live treatdependent gate: {cmd:endopolyprodest} as hard requirement and {cmd:prodest} as advisory environment info{p_end}
{synopt:{opt compare}}check the public {cmd:pte_compare} workflow bundle ({cmd:reghdfe} plus companion compare Mata sources that resolve to the active source-tree bundle when present, otherwise fall back to adopath, are compilable, and publish the required compare worker-entry Mata symbol); compare mode does not require baseline GMM Mata readiness{p_end}
{synopt:{opt notrimeps}}report the trimming environment for a {cmd:pte, notrimeps} run; {cmd:winsor2} remains advisory only{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:pte_check_deps} verifies that all required dependencies are available
for the {cmd:pte} package. It reports the status of each dependency and
provides installation instructions for any missing packages.

{pstd}
The command also reports whether {cmd:moremata} is visible in the current
Stata environment. This is advisory information only: the current public
runtime no longer consumes {cmd:moremata} on its baseline initialization
chain, so its presence does not affect {cmd:r(all_satisfied)}.

{pstd}
By default, only core baseline dependencies are checked. Specify
{opt treatdependent} to additionally verify the live gate used by the
treatment-dependent production function path. Under that gate,
{cmd:endopolyprodest} is the hard external requirement, the package-owned
{cmd:_pte_mata_endopoly_patch.do} file must also load successfully, and
{cmd:prodest} is reported as recommended environment information only.
Specify {opt compare} to certify the public TWFE comparison workflow
required by {cmd:pte_compare}; this compare-only bundle checks
{cmd:reghdfe} plus the companion compare Mata source files used by
Methods I and II, verifies that those sources can actually compile under
the public compare worker contract {it:and} export the worker-entry Mata
symbol consumed by the public compare dispatcher, resolves source-tree
companions ahead of stale installed shadows when the active package tree is
on adopath, and intentionally skips the unrelated baseline GMM Mata
runtime. Specify {opt notrimeps} when you want the report text to reflect
a planned {cmd:pte, notrimeps} run; the
{cmd:winsor2} line remains advisory because baseline public {cmd:pte}
uses a built-in deterministic trimming path.

{pstd}
The command always displays a formatted report with explicit status tags for
each line. Required checks use [PASS] or [FAIL], advisory environment lines
use [INFO], followed by a summary line.

{pstd}
If an internal load probe used by the public dependency gate itself errors,
{cmd:pte_check_deps} summarizes that condition as a failed required check
instead of aborting with the helper's return code.


{marker options}{...}
{title:Options}

{phang}
{opt detail} displays additional information for each check, such as the
file location of installed packages and a numeric summary of checks
passed and failed.

{phang}
{opt treatdependent} extends the check to include the live dependency gate
used by treatment-dependent production function estimation via
{cmd:endopolyprodest}. This adds a hard check for the
{cmd:endopolyprodest} command, a hard load probe for the package-owned
{cmd:_pte_mata_endopoly_patch.do} compatibility file, and an advisory
environment check for the {cmd:prodest} base package. The advisory line
does not change the required check denominator reported in
{cmd:r(n_checks)}. Any internal runtime-prepare failure on this path is
reported as a failed check in the public summary rather than being rethrown
to the caller.

{phang}
{opt compare} switches the required bundle to the public comparison command
{cmd:pte_compare}. This checks the shared {cmd:reghdfe} dependency plus the
companion compare Mata source files used by the paper's Method I/II
comparison workers, preferring the active package/source-tree companion
files over stale installed shadows with the same basename, and does not
promote the baseline GMM Mata runtime to a
required compare-path dependency.

{phang}
{opt notrimeps} adjusts the advisory trimming message so it matches a
planned {cmd:pte} run that disables epsilon-zero trimming. The public
dependency gate does not promote {cmd:winsor2} to a required check in
either mode because baseline {cmd:pte} uses a built-in deterministic
trimming path.


{marker groups}{...}
{title:Core vs extended dependencies}

{pstd}
{it:Core baseline dependencies} (checked by default, and skipped in compare-only mode):

{p 8 12 2}
1. Stata version >= 14.0 {hline 2} required for Mata optimization
functions.{p_end}

{p 8 12 2}
2. Baseline Mata runtime {hline 2} the public baseline path must be able
to verify or initialize the GMM optimizer, the
{cmd:OptimizationResult()} struct, the package-owned
{cmd:_pte_runtime_signature()} marker, the deterministic
{cmd:generate_grid()} CD/translog semantics, and the matrix-construction
functions consumed by {cmd:pte} and {cmd:_pte_gmm_wrapper}. A cold, broken,
or foreign same-name preload fails the required dependency gate and sets
{cmd:r(all_satisfied)}=0. This check is intentionally skipped when
{opt compare} certifies the compare-only workflow because {cmd:pte_compare}
does not dispatch through the baseline GMM entry chain.{p_end}

{pstd}
{it:Advisory trimming environment} (always reported):

{p 8 12 2}
{cmd:winsor2} {hline 2} optional for running the official DO replication
scripts directly. The public {cmd:pte} command uses a built-in
deterministic 1%/99% trimming path, so this line is reported as
environment information rather than a required dependency.{p_end}

{p 8 12 2}
{cmd:moremata} {hline 2} reported as optional environment information.
Legacy local workflows may still carry the library, but the current public
runtime does not require it at entry.{p_end}

{pstd}
{it:Treatdependent gate and advisory checks} (checked when {opt treatdependent} is specified):

{p 8 12 2}
3. {cmd:prodest} {hline 2} recommended base package reported for
environment diagnostics only. When the official
{cmd:endopolyprodest} command is already available in the current
session, a missing {cmd:prodest} installation does not by itself fail the
public dependency check. Install with {cmd:ssc install prodest}.{p_end}
{p 8 12 2}
4. {cmd:endopolyprodest} {hline 2} treatment-dependent estimation command.
Load with {cmd:run DOs/treatpolyprodest.ado} or install permanently.{p_end}
{p 8 12 2}
5. {cmd:_pte_mata_endopoly_patch.do} {hline 2} package-owned compatibility
patch that must load successfully before the official
{cmd:endopolyprodest} source is runnable from the public treatdependent
chain.{p_end}

{pstd}
{it:Compare-workflow dependency} (checked when {opt compare} is specified):

{p 8 12 2}
6. {cmd:reghdfe} {hline 2} TWFE regression engine used by the public
{cmd:pte_compare} workflow and the corresponding paper/DO comparison
regressions. Install with {cmd:ssc install reghdfe}.{p_end}

{p 8 12 2}
7. Compare Mata sources {hline 2} {_cmd:_pte_compare_expost_gmm.mata} and
{_cmd:_pte_compare_endog_gmm.mata} must be discoverable from adopath or the
project tree, compile successfully under the public worker contract, {it:and}
publish the required worker-entry Mata symbol because the Method I/II
workers execute those exact entry points at runtime.{p_end}

{pstd}
Optional helpers outside the baseline estimation path may also use
community utilities such as {cmd:distinct}, but they are not required for
the core {cmd:pte} dependency contract enforced by {cmd:pte_check_deps}.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:pte_check_deps} stores the following in {cmd:r()}:

{synoptset 25 tabbed}{...}
{p2col 5 25 29 2: Scalars}{p_end}
{synopt:{cmd:r(all_satisfied)}}1 if all required checks passed, 0 otherwise{p_end}
{synopt:{cmd:r(n_missing)}}number of failed required checks{p_end}
{synopt:{cmd:r(n_checks)}}total number of required pass/fail checks performed{p_end}


{marker examples}{...}
{title:Examples}

{pstd}Check core dependencies only{p_end}
{phang2}{cmd:. pte_check_deps}{p_end}

{pstd}Check all dependencies including treatment-dependent extensions{p_end}
{phang2}{cmd:. pte_check_deps, treatdependent}{p_end}

{pstd}Check dependencies for a {cmd:pte, notrimeps} run{p_end}
{phang2}{cmd:. pte_check_deps, notrimeps}{p_end}

{pstd}Detailed report with file locations{p_end}
{phang2}{cmd:. pte_check_deps, detail treatdependent}{p_end}

{pstd}Check dependencies for the public compare workflow{p_end}
{phang2}{cmd:. pte_check_deps, compare}{p_end}

{pstd}Inspect return values{p_end}
{phang2}{cmd:. pte_check_deps}{p_end}
{phang2}{cmd:. return list}{p_end}
{phang2}{cmd:. display "All satisfied: " r(all_satisfied)}{p_end}


{marker references}{...}
{title:References}

{phang}
Chen, Z., Liao, M. & Schurter, K. (2026).
Identifying Treatment Effects on Productivity: Theory with an Application to Production Digitalization.
{it:Working Paper}.
{p_end}
{smcl}
