{smcl}
{* *! version 1.0.0  01jan2026}{...}
{vieweralsosee "[PTE] _pte_bootstrap_bygroup" "help _pte_bootstrap_bygroup"}{...}
{vieweralsosee "[PTE] _pte_bygroup_boot_single" "help _pte_bygroup_boot_single"}{...}
{vieweralsosee "[PTE] pte" "help pte"}{...}
{viewerjumpto "Syntax" "_pte_bygroup_aggregate##syntax"}{...}
{viewerjumpto "Description" "_pte_bygroup_aggregate##description"}{...}
{viewerjumpto "Options" "_pte_bygroup_aggregate##options"}{...}
{viewerjumpto "Stored results" "_pte_bygroup_aggregate##results"}{...}
{title:Title}

{p2colset 5 30 32 2}{...}
{p2col:{cmd:_pte_bygroup_aggregate} {hline 2}}Cross-group ATT aggregation{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:_pte_bygroup_aggregate}{cmd:,}
{opt ngroups(#)}
{opt nboot(#)}
{opt attperiods(#)}
{opt tmpdir(string)}
[{opt ttprefix(string)}]
[{opt runid(string)}]
[{opt notrimeps}]

{synoptset 22 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt ngroups(#)}}number of groups{p_end}
{synopt:{opt nboot(#)}}number of bootstrap replications{p_end}
{synopt:{opt attperiods(#)}}maximum post-treatment periods{p_end}
{synopt:{opt tmpdir(string)}}directory containing per-group TT data files{p_end}
{synopt:{opt ttprefix(string)}}filename prefix before
{it:g}{cmd:_b}{it:b}{cmd:.dta}; default {cmd:pte_tt_g}{p_end}
{synopt:{opt runid(string)}}expected invocation token; if present, all TT files
for a bootstrap draw must match it{p_end}
{synopt:{opt notrimeps}}disable trimmed-track aggregation{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:_pte_bygroup_aggregate} is an internal helper that aggregates
per-group treatment effect (TT) data across all groups for each bootstrap
iteration. It is called by {helpb _pte_bootstrap_bygroup} after the
per-group bootstrap loops complete.

{pstd}
For each bootstrap iteration b = 1, ..., B:

{phang2}1. Load and append TT data files from all groups
({cmd:{it:ttprefix}}{it:g}{cmd:_b}{it:b}{cmd:.dta}).{p_end}

{phang2}2. Compute pooled ATT = mean(TT) overall and by period (nt).{p_end}

{pstd}
Each bootstrap iteration contributes a pooled draw only when TT files for
all {cmd:ngroups()} are present, load successfully, and carry the complete
TT payload required by the active track ({cmd:_pte_nt} + {cmd:_pte_tt_raw},
plus {cmd:_pte_tt_trim} when trimming is enabled). If any group file is
missing, unreadable, or lacks that payload for iteration {it:b}, the
corresponding row in
{cmd:r(att_pool)} (and {cmd:r(att_pool_trim)} when applicable) remains
missing.

{pstd}
When TT files contain the invocation marker variable {cmd:_pte_tt_runid},
the helper enforces same-run consistency within each bootstrap draw. Mixed
run IDs, or mixed metadata where some files carry {cmd:_pte_tt_runid} and
others do not, are treated as incomplete draws and remain missing.
Supplying {opt runid()} tightens this contract further by requiring an
exact match to the current invocation token.

{pstd}
This implements the sample-weighted average approach from the replication
code ({cmd:DOs/att_estimation_industry_trlg_nonlinear.do} L253-263).

{pstd}
This module can also be called independently for testing or by the
parallel worker.


{marker options}{...}
{title:Options}

{phang}
{opt ngroups(#)} specifies the total number of groups.

{phang}
{opt nboot(#)} specifies the number of bootstrap replications.

{phang}
{opt attperiods(#)} specifies the maximum post-treatment period index.

{phang}
{opt tmpdir(string)} specifies the directory containing per-group TT data
files. Files are expected at
{cmd:`tmpdir'/{it:ttprefix}}{it:g}{cmd:_b}{it:b}{cmd:.dta}.

{phang}
{opt ttprefix(string)} specifies the filename prefix used for per-group TT
files. The default is {cmd:pte_tt_g}. Current grouped bootstrap producers
use a run-unique prefix to avoid cross-invocation collisions in shared
temporary directories.

{phang}
{opt runid(string)} specifies the expected invocation token stored in
{cmd:_pte_tt_runid}. If the loaded group files disagree on run ID, or do
not match {opt runid()}, or mix tagged and untagged TT files within the
same draw, that bootstrap draw is treated as incomplete.

{phang}
{opt notrimeps} skips aggregation of the trimmed TT track.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:_pte_bygroup_aggregate} stores the following in {cmd:r()}:

{synoptset 24 tabbed}{...}
{p2col 5 24 28 2: Matrices}{p_end}
{synopt:{cmd:r(att_pool)}}B x (1+T) pooled ATT bootstrap distribution
(raw){p_end}
{synopt:{cmd:r(att_pool_trim)}}B x (1+T) pooled ATT bootstrap distribution
(trimmed; if trimming enabled){p_end}

{pstd}
Column layout follows the official industry DO order:
columns 1..(T+1) = period-specific ATT for nt = 0, 1, ..., T,
and column (T+2) = overall ATT (all nt >= 0).
