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
    pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
        attperiods(3) evolution(independent)
}

if _rc == 0 {
    di as text ""
    di as text "  Evolution assumption: " e(evolution)
    di as text "  Number of moments:    " e(n_moments)
    di as text "  J test statistic:     " %9.4f e(j_stat)
    di as text "  J test p-value:       " %9.4f e(j_pval)
    di as text "  J test df:            " e(j_df)
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
    pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
        attperiods(3) evolution(divergent)
}

if _rc == 0 {
    di as text ""
    di as text "  Evolution assumption: " e(evolution)
    di as text "  Number of moments:    " e(n_moments)
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
    pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
        attperiods(3) evolution(independent) overid
}

if _rc == 0 {
    di as text ""
    di as text "  J statistic: " %9.4f e(j_stat)
    di as text "  p-value:     " %9.4f e(j_pval)
    di as text "  df:          " e(j_df)
    di as text ""
    if e(j_pval) > 0.10 {
        di as text "  => Fail to reject H0: extended moments appear valid."
    }
    else if e(j_pval) > 0.05 {
        di as text "  => Marginal: use extended moments with caution."
    }
    else {
        di as text "  => Reject H0: consider using standard diagonal method."
    }
}

di as text ""
di as text _dup(70) "="
di as text "FR-018 examples complete."
di as text _dup(70) "="
