*! pte_extended_moments.do
*! FR-018 Extended Moment Conditions Examples
*! Reference: Chen, Liao & Schurter (2026), Appendix D.1-D.2

// =========================================================================
// Setup: Load data and prepare variables
// =========================================================================

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

capture confirm file "`root'/data/pte_example.dta"
if _rc {
    di as error "pte_extended_moments.do could not find `root'/data/pte_example.dta"
    di as error "Run this example from the repository root, pass the repo root as the first do-file argument, or set PTE_STATA_ROOT."
    exit 601
}

quietly adopath + "`root'/ado"

use "`root'/data/pte_example.dta", clear

xtset firm year

// Generate treatment-post indicator
capture drop treat_post
gen treat_post = (D == 1)

di as text ""
di as text _dup(70) "="
di as text "FR-018: Extended Moment Conditions Examples"
di as text "Reference: Appendix D.1-D.2"
di as text _dup(70) "="

// =========================================================================
// Example 1: Independent Evolution (Corollary D.1)
// Under Example 3 assumption, productivity innovations are uncorrelated
// with past productivity, allowing additional lagged instruments.
// =========================================================================

di as text ""
di as text _dup(60) "-"
di as text "Example 1: Independent Evolution (Corollary D.1)"
di as text _dup(60) "-"

capture noisily {
    // Note: evolution() option is reserved for a future version.
    // The standard pte command uses omegapoly() to control evolution order.
    // pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
    //     attperiods(3) evolution(independent)
    pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
        attperiods(3) omegapoly(1)
}

if _rc == 0 {
    di as text ""
    di as text "  Omega polynomial order: " e(omegapoly)
    di as text "  ATT results:"
    capture matrix list e(att)
}

// =========================================================================
// Example 2: Divergent Evolution (Corollary D.2)
// Under Example 2 assumption, treated and untreated firms follow
// different evolution processes that diverge after treatment.
// =========================================================================

di as text ""
di as text _dup(60) "-"
di as text "Example 2: Divergent Evolution (Corollary D.2)"
di as text _dup(60) "-"

capture noisily {
    // Note: evolution(divergent) option is reserved for a future version.
    // Using higher-order polynomial as a proxy for divergent evolution.
    // pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
    //     attperiods(3) evolution(divergent)
    pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
        attperiods(3) omegapoly(3)
}

if _rc == 0 {
    di as text ""
    di as text "  Omega polynomial order: " e(omegapoly)
    di as text "  ATT results:"
    capture matrix list e(att)
}

// =========================================================================
// Example 3: Overidentification (J) Test
// The J test checks validity of extended moment conditions.
// p > 0.10: fail to reject => extended moments valid
// p <= 0.05: reject => use standard diagonal method
// =========================================================================

di as text ""
di as text _dup(60) "-"
di as text "Example 3: Overidentification J Test"
di as text _dup(60) "-"

capture noisily {
    // Note: evolution() and overid options are reserved for a future version.
    // Running standard estimation with omegapoly(1) as a placeholder.
    // pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
    //     attperiods(3) evolution(independent) overid
    pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
        attperiods(3) omegapoly(1)
}

if _rc == 0 {
    di as text ""
    di as text "  ATT results:"
    capture matrix list e(att)
    di as text ""
    di as text "  Note: Overidentification (J) test requires future evolution() support."
    di as text "  When available, check e(j_stat) and e(j_pval) for moment validity."
}

di as text ""
di as text _dup(70) "="
di as text "FR-018 examples complete."
di as text _dup(70) "="
