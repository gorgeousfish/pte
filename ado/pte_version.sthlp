{smcl}
{* *! version 1.0.0  01jan2026}{...}
{viewerjumpto "Syntax" "pte_version##syntax"}{...}
{viewerjumpto "Description" "pte_version##description"}{...}
{viewerjumpto "Options" "pte_version##options"}{...}
{viewerjumpto "Examples" "pte_version##examples"}{...}
{viewerjumpto "Stored results" "pte_version##results"}{...}
{viewerjumpto "References" "pte_version##references"}{...}
{title:Title}

{p2colset 5 24 26 2}{...}
{p2col:{bf:pte_version} {hline 2}}Display pte package version information{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:pte_version}
[{cmd:,} {it:options}]

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt d:etail}}display release history{p_end}
{synopt:{opt c:heck}}check for updates{p_end}
{synoptline}

{p 4 6 2}
Options {opt detail} and {opt check} may not be combined.


{marker description}{...}
{title:Description}

{pstd}
{cmd:pte_version} displays version information for the {cmd:pte}
(Productivity Treatment Effects) package, including the version number,
release date, authors, and paper reference.

{pstd}
Without options, {cmd:pte_version} displays basic version information.
With {opt detail}, it additionally shows the complete release history.
With {opt check}, it displays update instructions for obtaining the latest
version.


{marker options}{...}
{title:Options}

{phang}
{opt detail} displays the complete release history, listing all versions
with their dates and changes.

{phang}
{opt check} displays update instructions for obtaining the latest version of
{cmd:pte}
from the GitHub repository.


{marker examples}{...}
{title:Examples}

{pstd}Display basic version information{p_end}
{phang2}{cmd:. pte_version}{p_end}

{pstd}Display version with release history{p_end}
{phang2}{cmd:. pte_version, detail}{p_end}

{pstd}Check for updates{p_end}
{phang2}{cmd:. pte_version, check}{p_end}

{pstd}Use version in a script{p_end}
{phang2}{cmd:. pte_version}{p_end}
{phang2}{cmd:. local ver "`r(version)'"}{p_end}
{phang2}{cmd:. display "Running pte version `ver'"}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:pte_version} stores the following in {cmd:r()}:

{p2colset 5 24 28 2}{...}
{p2col 5 24 28 2: Locals}{p_end}
{synopt:{cmd:r(version)}}version number (e.g., {cmd:1.0.0}){p_end}
{synopt:{cmd:r(date)}}release date in ISO 8601 format (e.g.,
{cmd:2026-01-01}){p_end}
{synopt:{cmd:r(authors)}}author names (e.g., {cmd:Chen, Liao, Schurter}){p_end}
