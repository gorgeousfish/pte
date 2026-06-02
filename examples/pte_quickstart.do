*! pte Quick Start Example
*! Demonstrates basic usage of the pte Stata package
*! CLK framework: Chen, Liao & Schurter (2026)

* ============================================================================
* 1. SETUP
* ============================================================================

version 14.0
clear all
set more off
set matsize 5000

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
    di as error "pte_quickstart.do could not find `root'/data/pte_example.dta"
    di as error "Run this example from the repository root, pass the repo root as the first do-file argument, or set PTE_STATA_ROOT."
    exit 601
}

* Load pte package modules
quietly adopath + "`root'/ado"

display as text ""
display as text _dup(70) "="
display as text "  pte Quick Start Example"
display as text "  Productivity Treatment Effects (CLK Framework)"
display as text _dup(70) "="
display as text ""

* ============================================================================
* 2. DATA PREPARATION
* ============================================================================

* Load example dataset
* Variables: firm year lny lnl lnk lnm D
*   lny  = log output
*   lnl  = log labor (free input)
*   lnk  = log capital (state variable)
*   lnm  = log materials (proxy variable)
*   D    = treatment indicator (absorbing: 0 -> 1)
use "`root'/data/pte_example.dta", clear

* Declare panel structure
xtset firm year

* Quick overview of the data
describe, short
summarize lny lnl lnk lnm D, separator(0)

display as text ""
display as text "Panel structure:"
display as text _dup(40) "-"

* Count firms and time periods
quietly tab firm
display as text "  Number of firms:   " r(r)
quietly summarize year
display as text "  Time periods:      " r(min) " - " r(max)
quietly count if D == 1
display as text "  Treated obs:       " r(N)
quietly count if D == 0
display as text "  Control obs:       " r(N)
display as text ""

* ============================================================================
* 3. BASIC ESTIMATION
* ============================================================================

* --- 3a. Cobb-Douglas production function ---
display as text _dup(70) "="
display as text "  Estimation: Cobb-Douglas with Bootstrap"
display as text _dup(70) "="
display as text ""

* Core pte command:
*   depvar    = lny (log output)
*   treat()   = D (treatment indicator)
*   free()    = lnl (freely chosen inputs)
*   state()   = lnk (state variables, predetermined)
*   proxy()   = lnm (proxy for unobserved productivity)
*   bootstrap = number of bootstrap replications for inference

pte lny, treatment(D) free(lnl) state(lnk) proxy(lnm) ///
    pfunc(cd) bootstrap(50) seed(12345)

* --- 3b. Estimation with specific ATT periods ---
display as text ""
display as text _dup(70) "="
display as text "  Estimation: Cobb-Douglas with ATT Periods"
display as text _dup(70) "="
display as text ""

* attperiods() specifies the maximum post-treatment horizon to compute ATT.
* e.g., attperiods(3) computes ATT for event times 0, 1, 2, and 3.
pte lny, treatment(D) free(lnl) state(lnk) proxy(lnm) ///
    pfunc(cd) attperiods(3) bootstrap(50) seed(12345)

* ============================================================================
* 4. RESULTS INSPECTION
* ============================================================================

display as text ""
display as text _dup(70) "="
display as text "  Results Inspection"
display as text _dup(70) "="
display as text ""

* --- 4a. View all stored estimation results ---
ereturn list

* --- 4b. Production function coefficients ---
display as text ""
display as text "Production function coefficients:"
matrix list e(b), format(%9.6f)

* --- 4c. ATT estimates ---
display as text ""
display as text "ATT estimates (overall):"
display as text "  ATT_avg = " %9.6f e(ATT_avg)

* Period-specific ATT (from bootstrap mode)
display as text ""
display as text "Period-specific ATT:"
capture matrix attperiods_mat = e(attperiods)
if _rc == 0 {
    forvalues j = 1/`=colsof(attperiods_mat)' {
        local s = attperiods_mat[1, `j']
        capture display as text "  ATT(s=`s') = " %9.6f e(att_`s')
    }
}

* --- 4d. Productivity evolution parameters ---
display as text ""
display as text "Omega evolution parameters (control path):"
capture matrix list e(rho_0), format(%9.6f)
if _rc != 0 {
    display as text "(e(rho_0) not posted by this estimation route)"
}

display as text ""
display as text "Omega evolution parameters (treated path):"
capture matrix list e(rho_1), format(%9.6f)
if _rc != 0 {
    display as text "(e(rho_1) not posted by this estimation route)"
}

* --- 4e. Bootstrap inference ---
display as text ""
display as text "Bootstrap inference:"
capture confirm scalar e(bs_se)
if _rc == 0 {
    display as text "  Bootstrap SE:  " %9.6f e(bs_se)
}
capture confirm scalar e(ci_lo)
if _rc == 0 {
    display as text "  95% CI lower:  " %9.6f e(ci_lo)
}
capture confirm scalar e(ci_hi)
if _rc == 0 {
    display as text "  95% CI upper:  " %9.6f e(ci_hi)
}

* --- 4f. Predict productivity and treatment effects ---
* Note: predict postestimation requires pte_p.ado
capture {
    predict omega_hat, omega
    summarize omega_hat, detail

    predict tt_hat, tt
    summarize tt_hat if tt_hat != .

    display as text ""
    display as text "Average TT among treated firms:"
    quietly summarize tt_hat if tt_hat != .
    display as result %9.4f r(mean)
}
if _rc != 0 {
    display as text "(predict postestimation skipped)"
}

* ============================================================================
* 5. VISUALIZATION
* ============================================================================

display as text ""
display as text _dup(70) "="
display as text "  Visualization"
display as text _dup(70) "="
display as text ""

* --- 5a. ATT plot: average treatment effect over time ---
capture noisily pte_graph, att
if _rc != 0 {
    display as text "(pte_graph, att skipped — command may not be available)"
}

* --- 5b. TT plot: individual treatment effects ---
capture noisily pte_graph, tt
if _rc != 0 {
    display as text "(pte_graph, tt skipped)"
}

* --- 5c. Productivity evolution comparison ---
capture noisily pte_graph, evolution
if _rc != 0 {
    display as text "(pte_graph, evolution skipped)"
}

display as text ""
display as text _dup(70) "="
display as text "  Quick Start Complete"
display as text _dup(70) "="
display as text ""
