*! pte Paper Replication Example
*! Replicates main results from Chen, Liao & Schurter (2026)
*! Tables 1, 2, and 4: Production function estimates and ATT
*!
*! Dataset: data/pte_example.dta
*! Variables: lny lnl lnk lnm D firm year ind

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
    di as error "pte_replication.do could not find `root'/data/pte_example.dta"
    di as error "Run this example from the repository root, pass the repo root as the first do-file argument, or set PTE_STATA_ROOT."
    exit 601
}

* Load pte package
quietly adopath + "`root'/ado"

display as text ""
display as text _dup(70) "="
display as text "  Paper Replication: Chen, Liao & Schurter (2026)"
display as text "  Productivity Treatment Effects (CLK Framework)"
display as text _dup(70) "="
display as text ""

* ============================================================================
* 2. DATA LOADING
* ============================================================================

display as text _dup(70) "-"
display as text "  Section 2: Data Loading and Summary"
display as text _dup(70) "-"
display as text ""

use "`root'/data/pte_example.dta", clear

* Use packaged panel ID, industry variable, and treatment indicator
gen ind = industry

* Declare panel structure
xtset firm year

* Dataset overview
describe, short
display as text ""
summarize lny lnl lnk lnm D, separator(0)

* Panel structure summary
display as text ""
display as text "Panel structure:"
display as text _dup(40) "-"

quietly tab firm
local n_firms = r(r)
display as text "  Number of firms:     " as result `n_firms'

quietly summarize year
display as text "  Time span:           " as result r(min) " - " r(max)

quietly count if D == 1
display as text "  Treated obs:         " as result r(N)

quietly count if D == 0
display as text "  Control obs:         " as result r(N)

* Industry distribution
display as text ""
display as text "Industry distribution:"
tab ind

display as text ""

* ============================================================================
* 3. TABLE 1 REPLICATION: COBB-DOUGLAS PRODUCTION FUNCTION
* ============================================================================
*
* Paper Table 1: Pooled Cobb-Douglas estimates with CLK correction
*   - Production function: y = beta_l * l + beta_k * k + omega + epsilon
*   - CLK correction: exclude transition observations (D_t != D_{t-1})
*   - ATT via counterfactual simulation
*   - Bootstrap inference (200 replications)
*
* Note: CD forces omegapoly(1) automatically (linear evolution)

display as text _dup(70) "="
display as text "  Table 1: Cobb-Douglas Production Function (Pooled)"
display as text _dup(70) "="
display as text ""

timer clear 1
timer on 1

pte lny, treatment(D) free(lnl) state(lnk) proxy(lnm) ///
    pfunc(cd) bootstrap(200) seed(12345)

timer off 1

* Store CD results for later comparison
local cd_beta_l = e(beta_l)
local cd_beta_k = e(beta_k)
local cd_att    = e(ATT_avg)
local cd_att_se = e(bs_se)
local cd_N      = e(N)
local cd_N_gmm  = e(N_gmm)

* Display key results
display as text ""
display as text "Table 1 Summary:"
display as text _dup(50) "-"
display as text "  beta_l (labor):      " as result %9.6f `cd_beta_l'
display as text "  beta_k (capital):    " as result %9.6f `cd_beta_k'
display as text "  ATT (average):       " as result %9.6f `cd_att'
display as text "  Bootstrap SE:        " as result %9.6f `cd_att_se'
display as text "  N (total):           " as result `cd_N'
display as text "  N (GMM):             " as result `cd_N_gmm'
display as text ""

* Evolution parameters
display as text "Omega evolution (linear, omegapoly=1):"
display as text "  rho0 (intercept):    " as result %9.6f e(rho0)
display as text "  rho1 (persistence):  " as result %9.6f e(rho1)
display as text "  gamma1 (treatment):  " as result %9.6f e(gamma1)
display as text "  delta (interaction): " as result %9.6f e(delta)
display as text ""

* ATT by period (if available)
display as text "ATT by post-treatment period:"
capture matrix attperiods_mat = e(attperiods)
if _rc == 0 {
    forvalues j = 1/`=colsof(attperiods_mat)' {
        local s = attperiods_mat[1, `j']
        capture display as text "  ATT(s=`s'):          " as result %9.6f e(att_`s')
    }
}
else {
    capture local att_max = e(attperiods_max)
    if _rc == 0 {
        forvalues s = 0/`att_max' {
            capture display as text "  ATT(s=`s'):          " as result %9.6f e(att_`s')
        }
    }
}

timer list 1
display as text ""

* ============================================================================
* 4. TABLE 2 REPLICATION: TRANSLOG PRODUCTION FUNCTION
* ============================================================================
*
* Paper Table 2: Pooled Translog estimates with CLK correction
*   - Production function: y = beta_l*l + beta_k*k + beta_ll*l^2
*                            + beta_kk*k^2 + beta_lk*l*k + omega + epsilon
*   - Cubic evolution polynomial (omegapoly=3, default for translog)
*   - nsim=100 counterfactual simulation paths (auto-default)
*   - Bootstrap inference (200 replications)

display as text _dup(70) "="
display as text "  Table 2: Translog Production Function (Pooled)"
display as text _dup(70) "="
display as text ""

* Reload data (clean state for each estimation)
use "`root'/data/pte_example.dta", clear
gen ind = industry
xtset firm year

timer clear 2
timer on 2

pte lny, treatment(D) free(lnl) state(lnk) proxy(lnm) ///
    translog bootstrap(200) seed(12345)

timer off 2

* Store Translog results for later comparison
local tl_beta_l  = e(beta_l)
local tl_beta_k  = e(beta_k)
local tl_beta_ll = e(beta_ll)
local tl_beta_kk = e(beta_kk)
local tl_beta_lk = e(beta_lk)
local tl_att     = e(ATT_avg)
local tl_att_se  = e(bs_se)
local tl_N       = e(N)
local tl_N_gmm   = e(N_gmm)

* Display key results
display as text ""
display as text "Table 2 Summary:"
display as text _dup(50) "-"
display as text "  beta_l  (labor):     " as result %9.6f `tl_beta_l'
display as text "  beta_k  (capital):   " as result %9.6f `tl_beta_k'
display as text "  beta_ll (l^2):       " as result %9.6f `tl_beta_ll'
display as text "  beta_kk (k^2):       " as result %9.6f `tl_beta_kk'
display as text "  beta_lk (l*k):       " as result %9.6f `tl_beta_lk'
display as text "  ATT (average):       " as result %9.6f `tl_att'
display as text "  Bootstrap SE:        " as result %9.6f `tl_att_se'
display as text "  N (total):           " as result `tl_N'
display as text "  N (GMM):             " as result `tl_N_gmm'
display as text ""

* Evolution parameters (cubic)
display as text "Omega evolution (cubic, omegapoly=3):"
display as text "  rho0 (intercept):    " as result %9.6f e(rho0)
display as text "  rho1 (omega):        " as result %9.6f e(rho1)
display as text "  rho2 (omega^2):      " as result %9.6f e(rho2)
display as text "  rho3 (omega^3):      " as result %9.6f e(rho3)
display as text "  gamma1 (treatment):  " as result %9.6f e(gamma1)
display as text "  delta (interaction): " as result %9.6f e(delta)
display as text ""

* ATT by period
display as text "ATT by post-treatment period:"
capture matrix attperiods_mat = e(attperiods)
if _rc == 0 {
    forvalues j = 1/`=colsof(attperiods_mat)' {
        local s = attperiods_mat[1, `j']
        capture display as text "  ATT(s=`s'):          " as result %9.6f e(att_`s')
    }
}
else {
    capture local att_max = e(attperiods_max)
    if _rc == 0 {
        forvalues s = 0/`att_max' {
            capture display as text "  ATT(s=`s'):          " as result %9.6f e(att_`s')
        }
    }
}

timer list 2
display as text ""

* ============================================================================
* 5. TABLE 4 REPLICATION: BY INDUSTRY (COBB-DOUGLAS)
* ============================================================================
*
* Paper Table 4: Industry-specific CD estimates
*   - Separate estimation for each industry (ind = 1..7)
*   - Same specification as Table 1 but restricted to each industry subsample
*   - No bootstrap here to save time; add bootstrap(200) for full replication

display as text _dup(70) "="
display as text "  Table 4: Industry-Specific Cobb-Douglas Estimates"
display as text _dup(70) "="
display as text ""

* Determine number of industries
use "`root'/data/pte_example.dta", clear
gen ind = industry
xtset firm year
quietly tab ind
local n_ind = r(r)

* Storage matrices: rows = industries, cols = (beta_l, beta_k, ATT, N_gmm)
matrix IND_RESULTS = J(`n_ind', 4, .)
matrix colnames IND_RESULTS = beta_l beta_k ATT N_gmm

timer clear 3
timer on 3

forvalues j = 1/`n_ind' {
    display as text ""
    display as text _dup(50) "-"
    display as text "  Industry `j' of `n_ind'"
    display as text _dup(50) "-"

    * Reload data for each industry (clean state)
    quietly use "`root'/data/pte_example.dta", clear
    quietly gen ind = industry
    quietly xtset firm year

    * Check if this industry has enough observations
    quietly count if ind == `j'
    local n_obs = r(N)
    if `n_obs' < 50 {
        display as text "  Skipping: only `n_obs' observations"
        continue
    }

    * Check treatment variation within industry
    quietly summarize D if ind == `j'
    if r(min) == r(max) {
        display as text "  Skipping: no treatment variation"
        continue
    }

    * Estimate CD production function for this industry
    capture noisily pte lny if ind == `j', ///
        treatment(D) free(lnl) state(lnk) proxy(lnm) ///
        pfunc(cd) seed(12345)

    if _rc == 0 {
        matrix IND_RESULTS[`j', 1] = e(beta_l)
        matrix IND_RESULTS[`j', 2] = e(beta_k)
        matrix IND_RESULTS[`j', 3] = e(ATT_avg)
        matrix IND_RESULTS[`j', 4] = e(N_gmm)

        display as text "  beta_l:  " as result %9.6f e(beta_l)
        display as text "  beta_k:  " as result %9.6f e(beta_k)
        display as text "  ATT:     " as result %9.6f e(ATT_avg)
        display as text "  N (GMM): " as result e(N_gmm)
    }
    else {
        display as error "  Estimation failed for industry `j' (rc = " _rc ")"
    }
}

timer off 3

* Display industry results table
display as text ""
display as text _dup(70) "="
display as text "  Table 4 Summary: Industry-Specific Results"
display as text _dup(70) "="
display as text ""
display as text "  Industry    beta_l     beta_k       ATT      N_gmm"
display as text _dup(60) "-"

forvalues j = 1/`n_ind' {
    if IND_RESULTS[`j', 1] != . {
        display as text "     `j'" ///
            as result %12.6f IND_RESULTS[`j', 1] ///
            as result %11.6f IND_RESULTS[`j', 2] ///
            as result %10.6f IND_RESULTS[`j', 3] ///
            as result %10.0f IND_RESULTS[`j', 4]
    }
    else {
        display as text "     `j'         .          .          .          ."
    }
}

display as text _dup(60) "-"
display as text ""
matrix list IND_RESULTS, format(%9.6f) title("Industry-Specific CD Estimates")

timer list 3
display as text ""

* ============================================================================
* 6. RESULTS COMPARISON: CD vs TRANSLOG
* ============================================================================

display as text _dup(70) "="
display as text "  Results Comparison: Cobb-Douglas vs Translog"
display as text _dup(70) "="
display as text ""

display as text "  Parameter          Cobb-Douglas      Translog"
display as text _dup(60) "-"
display as text "  beta_l" ///
    as result %18.6f `cd_beta_l' as result %14.6f `tl_beta_l'
display as text "  beta_k" ///
    as result %18.6f `cd_beta_k' as result %14.6f `tl_beta_k'
display as text "  beta_ll" ///
    as result "               ." as result %14.6f `tl_beta_ll'
display as text "  beta_kk" ///
    as result "               ." as result %14.6f `tl_beta_kk'
display as text "  beta_lk" ///
    as result "               ." as result %14.6f `tl_beta_lk'
display as text _dup(60) "-"
display as text "  ATT (avg)" ///
    as result %16.6f `cd_att' as result %14.6f `tl_att'
display as text "  ATT SE" ///
    as result %19.6f `cd_att_se' as result %14.6f `tl_att_se'
display as text _dup(60) "-"
display as text "  N (total)" ///
    as result %16.0f `cd_N' as result %14.0f `tl_N'
display as text "  N (GMM)" ///
    as result %18.0f `cd_N_gmm' as result %14.0f `tl_N_gmm'
display as text _dup(60) "-"

display as text ""
display as text _dup(70) "="
display as text "  Replication Complete"
display as text _dup(70) "="
display as text ""
display as text "  Notes:"
display as text "  - Table 1 (CD) uses omegapoly(1) with linear evolution"
display as text "  - Table 2 (Translog) uses omegapoly(3) with cubic evolution"
display as text "  - Table 4 (by industry) uses CD without bootstrap for speed"
display as text "  - Add bootstrap(200) to Table 4 loop for full inference"
display as text "  - Use replicate(order1) for exact seed matching with DOs/ code"
display as text ""

timer list
