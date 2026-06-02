*! pte_counterfactual.do
*! Appendix D contract notes for the public pte command
*! Reference: Chen, Liao & Schurter (2026), Appendix D.3

// =========================================================================
// This duplicate example is kept for backward file-path compatibility.
// It follows the same public-contract boundary as examples/pte_counterfactual.do:
//   * top-level pte estimates the baseline ATT path only;
//   * Appendix D counterfactual ATE^count workflows require dedicated workers.
// =========================================================================

version 14.0
clear all
set more off

args repo_root
local root "`repo_root'"
if "`root'" == "" {
    local root : environment PTE_STATA_ROOT
}
if "`root'" == "" {
    local root : environment PWD
}
if "`root'" == "" {
    local root `"`c(pwd)'"'
}

capture confirm file "`root'/data/复现数据.dta"
if _rc {
    di as error "pte_counterfactual.do could not find `root'/data/复现数据.dta"
    di as error "Run this example from the repository root, pass the repo root as the first do-file argument, or set PTE_STATA_ROOT."
    exit 601
}

quietly adopath + "`root'/ado"

use "`root'/data/复现数据.dta", clear

// Encode string industry code to numeric
capture confirm numeric variable Scode
if _rc {
    encode Scode, gen(industry_id)
    drop Scode
    rename industry_id Scode
}

xtset firm year

di as text ""
di as text _dup(70) "="
di as text "Appendix D Counterfactual Contract Notes"
di as text "Public pte path: baseline ATT only"
di as text "Appendix D counterfactual path: dedicated worker required"
di as text _dup(70) "="

// =========================================================================
// Example 1: Standard ATT path available from the public pte command
// =========================================================================

di as text ""
di as text _dup(60) "-"
di as text "Example 1: Baseline ATT from public pte"
di as text _dup(60) "-"

capture noisily {
    pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
        attperiods(3)
}

if _rc == 0 {
    di as text ""
    di as text "  ATT (overall): " %9.4f e(ATT_avg)
    capture matrix list e(att)
}

// =========================================================================
// Example 2: Contract reminder for Appendix D objects
// =========================================================================

di as text ""
di as text _dup(60) "-"
di as text "Example 2: Public-contract reminder"
di as text _dup(60) "-"
di as text "  counterfactual and targetgroup() are reserved on the public pte path."
di as text "  Use dedicated counterfactual workers after preparing target-group"
di as text "  timing objects such as reference/expansion periods."
di as text "  This example intentionally avoids calling unsupported entry points."

// =========================================================================
// Example 3: ATT interpretation available today
// =========================================================================

di as text ""
di as text _dup(60) "-"
di as text "Example 3: Interpreting current public output"
di as text _dup(60) "-"

di as text "  ATT answers: What was the effect on firms that were treated?"
di as text "  Appendix D ATE^count answers a different policy-extension question"
di as text "  and is not produced by the current top-level pte command."

di as text ""
di as text _dup(70) "="
di as text "Counterfactual contract note complete."
di as text _dup(70) "="
