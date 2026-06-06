*! pte Advanced Features Example
*! Demonstrates advanced options of the pte command
*! Dataset: data/pte_example.dta (panel data with firm-year structure)

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

capture confirm file "`root'/data/pte_example.dta"
if _rc {
    di as error "pte_advanced.do could not find `root'/data/pte_example.dta"
    di as error "Run this example from the repository root, pass the repo root as the first do-file argument, or set PTE_STATA_ROOT."
    exit 601
}

quietly adopath + "`root'/ado"
capture mkdir "`root'/output"

display _dup(70) "="
display "  pte Advanced Features Example"
display _dup(70) "="
display ""


* ============================================================================
* SECTION 1: SETUP
* ============================================================================
* Load panel dataset and verify structure

use "`root'/data/pte_example.dta", clear
* Generate synthetic industry grouping (pte_example.dta does not contain industry)
egen ind = cut(firm), group(4)
label variable ind "Industry group (synthetic)"
xtset firm year

display _dup(70) "-"
display "  Section 1: Data Overview"
display _dup(70) "-"
summarize lny lnl lnk lnm D
display "Panels: " e(N)
display ""


* ============================================================================
* SECTION 2: CONTROL VARIABLES
* ============================================================================
* The control() option includes additional regressors in the first-stage
* regression. After estimation, their contribution is subtracted from phi
* (phi = phi_raw - sum(beta_c * control_c)). This removes confounding
* variation such as time trends from the productivity measure.

use "`root'/data/pte_example.dta", clear
egen ind = cut(firm), group(4)
xtset firm year

display _dup(70) "-"
display "  Section 2: Control Variables — Time Trend"
display _dup(70) "-"
display ""
display "Adding year_trend as a control variable to absorb time effects."
display "This is subtracted from phi after first-stage estimation."
display ""

* Generate a linear time trend
gen year_trend = year - 1998

pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    control(year_trend) ///
    omegapoly(3) nolog

display ""
display "Beta estimates with time trend control:"
matrix list e(b)
display ""
display "ATT results:"
matrix list e(att)
display ""


* ============================================================================
* SECTION 3: OMEGA POLYNOMIAL ORDER
* ============================================================================
* The omegapoly() option controls the polynomial order of the productivity
* evolution law h(omega). Higher orders capture nonlinear persistence in
* productivity dynamics. omegapoly(1) = linear AR(1), omegapoly(3) = cubic.
* When omegapoly >= 2, counterfactual simulation with nsim paths is used.

use "`root'/data/pte_example.dta", clear
egen ind = cut(firm), group(4)
xtset firm year

display _dup(70) "-"
display "  Section 3: Omega Polynomial Order Comparison"
display _dup(70) "-"
display ""

* --- Linear evolution: omegapoly(1) ---
display ">>> omegapoly(1): Linear productivity evolution"
display ""

pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    omegapoly(1) nolog

matrix beta_lin = e(b)
matrix att_lin  = e(att)

display "Beta (linear):"
matrix list beta_lin
display ""

* --- Cubic evolution: omegapoly(3) ---
display ">>> omegapoly(3): Cubic productivity evolution"
display ""

pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    omegapoly(3) nolog

matrix beta_cub = e(b)
matrix att_cub  = e(att)

display "Beta (cubic):"
matrix list beta_cub
display ""

display "ATT comparison (linear vs cubic):"
matrix list att_lin
matrix list att_cub
display ""


* ============================================================================
* SECTION 4: NSIM SENSITIVITY
* ============================================================================
* The nsim() option sets the number of Monte Carlo simulation paths for
* counterfactual productivity. More paths reduce simulation variance but
* increase computation time. Default is 100 when omegapoly >= 2.

use "`root'/data/pte_example.dta", clear
egen ind = cut(firm), group(4)
xtset firm year

display _dup(70) "-"
display "  Section 4: NSIM Sensitivity Analysis"
display _dup(70) "-"
display ""

* --- Fewer paths: nsim(50) ---
display ">>> nsim(50): Fewer simulation paths (faster, noisier)"
display ""

pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    omegapoly(3) nsim(50) seed(12345) nolog

matrix att_50 = e(att)

* --- More paths: nsim(200) ---
display ">>> nsim(200): More simulation paths (slower, smoother)"
display ""

pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    omegapoly(3) nsim(200) seed(12345) nolog

matrix att_200 = e(att)

display "ATT comparison by nsim:"
display "  nsim = 50:"
matrix list att_50
display "  nsim = 200:"
matrix list att_200
display ""


* ============================================================================
* SECTION 5: VERBOSE MODE
* ============================================================================
* The verbose option displays detailed intermediate output during estimation,
* including GMM iteration logs, evolution parameter estimates, and simulation
* diagnostics. Useful for debugging and understanding the estimation process.

use "`root'/data/pte_example.dta", clear
egen ind = cut(firm), group(4)
xtset firm year

display _dup(70) "-"
display "  Section 5: Verbose Mode"
display _dup(70) "-"
display ""
display "Running with verbose to show detailed estimation output..."
display ""

pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    omegapoly(3) verbose nolog

display ""


* ============================================================================
* SECTION 6: SAVING BOOTSTRAP RESULTS
* ============================================================================
* The saving() option exports bootstrap replication results to a .dta file.
* Each row contains one bootstrap draw of beta and ATT estimates, enabling
* custom post-estimation analysis (e.g., bias-corrected CIs, density plots).

use "`root'/data/pte_example.dta", clear
egen ind = cut(firm), group(4)
xtset firm year

display _dup(70) "-"
display "  Section 6: Saving Bootstrap Results"
display _dup(70) "-"
display ""
display "Running bootstrap with 20 replications, saving draws to file..."
display ""

local bootstrap_results "`root'/output/bootstrap_results"
capture erase "`bootstrap_results'.dta"

pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    omegapoly(3) bootstrap(20) seed(42) ///
    saving("`bootstrap_results'") nolog

display ""
display "Bootstrap results saved. Inspecting saved file:"
display ""

preserve
use "`bootstrap_results'.dta", clear
describe
summarize
restore

display ""


* ============================================================================
* SECTION 7: CUSTOM ATT PERIODS
* ============================================================================
* The attperiods() option specifies the maximum post-treatment horizon for
* ATT. By default, the public command uses attperiods(4), so ATT is reported
* for event times 0 through 4 unless a smaller feasible horizon binds first.

use "`root'/data/pte_example.dta", clear
egen ind = cut(firm), group(4)
xtset firm year

display _dup(70) "-"
display "  Section 7: Custom ATT Periods"
display _dup(70) "-"
display ""
display "Computing ATT only for periods 0 through 5 after treatment."
display ""

pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    omegapoly(3) attperiods(5) nolog

display ""
display "ATT for selected periods:"
matrix list e(att)
display ""


* ============================================================================
* DONE
* ============================================================================

display _dup(70) "="
display "  All advanced examples completed."
display _dup(70) "="
