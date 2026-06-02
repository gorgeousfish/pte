*! pte Extensions Example
*! Demonstrates extension options of the pte command
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
    di as error "pte_extensions.do could not find `root'/data/pte_example.dta"
    di as error "Run this example from the repository root, pass the repo root as the first do-file argument, or set PTE_STATA_ROOT."
    exit 601
}

quietly adopath + "`root'/ado"

display _dup(70) "="
display "  pte Extensions Example"
display _dup(70) "="
display ""


* ============================================================================
* SECTION 1: SETUP
* ============================================================================
* Load panel dataset and verify structure

use "`root'/data/pte_example.dta", clear
gen ind = industry
xtset firm year

display _dup(70) "-"
display "  Section 1: Data Overview"
display _dup(70) "-"
summarize lny lnl lnk lnm D
display ""


* ============================================================================
* SECTION 2: NON-ABSORBING TREATMENT
* ============================================================================
* The nonabsorbing option relaxes the absorbing-state assumption: firms can
* exit treatment (D switches from 1 back to 0). The estimator separately
* identifies ATT+ (effect of entering treatment) and ATT- (effect of exiting
* treatment), enabling analysis of reversible policy interventions.

use "`root'/data/pte_example.dta", clear
gen ind = industry
xtset firm year

display _dup(70) "-"
display "  Section 2: Non-Absorbing Treatment"
display _dup(70) "-"
display ""
display "Allowing firms to exit treatment (D can switch 1 -> 0)."
display "Reports ATT+ (entering) and ATT- (exiting) separately."
display ""

capture noisily pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    nonabsorbing ///
    omegapoly(3) nolog

if _rc == 0 {
    display ""
    display "ATT results (non-absorbing):"
    matrix list e(att)
}
display ""


* ============================================================================
* SECTION 3: TREATMENT-DEPENDENT PRODUCTION
* ============================================================================
* The treatdependent option allows production technology to differ by
* treatment status. Instead of a single production function, the estimator
* fits separate input elasticities for treated and untreated firms. This
* captures settings where treatment alters the production process itself,
* not just productivity levels.

use "`root'/data/pte_example.dta", clear
gen ind = industry
xtset firm year

display _dup(70) "-"
display "  Section 3: Treatment-Dependent Production"
display _dup(70) "-"
display ""
display "Estimating separate production functions by treatment status."
display "Captures cases where treatment changes the technology, not just TFP."
display ""

capture noisily pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    treatdependent ///
    omegapoly(3) nolog

if _rc == 0 {
    display ""
    display "Beta estimates (treatment-dependent):"
    matrix list e(b)
    display ""
    display "ATT results:"
    matrix list e(att)
}
display ""


* ============================================================================
* SECTION 4: COHORT ANALYSIS
* ============================================================================
* The cohort() option is currently metadata-only on the public baseline path.
* pte validates the cohort variable name/type but does not yet dispatch the
* internal multi-cohort ATT workers or post cohort-specific e() results.
* This example shows how to prepare cohort metadata while keeping expectations
* aligned with the current public contract.

use "`root'/data/pte_example.dta", clear
gen ind = industry
xtset firm year

display _dup(70) "-"
display "  Section 4: Cohort Analysis"
display _dup(70) "-"
display ""

* Generate cohort metadata from observed 0->1 treatment entries only.
* Left-censored treated firms have no observed entry year on the public path
* and therefore keep missing cohort metadata here as well.
bysort firm (year): gen first_treat = year if _n > 1 & D == 1 & D[_n-1] == 0
bysort firm (year): egen cohort_year = min(first_treat)
drop first_treat

display "Cohort distribution (year of first treatment):"
tab cohort_year if cohort_year < .
display ""

capture noisily pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    cohort(cohort_year) ///
    omegapoly(3) nolog

if _rc == 0 {
    display ""
    display "ATT results (pooled public path; cohort() validated only):"
    matrix list e(att)
}
display ""


* ============================================================================
* SECTION 5: METHOD COMPARISON
* ============================================================================
* pte_compare contrasts the CLK estimator against alternative approaches:
*   expost  — Ex-post regression + TWFE (Method I)
*   endog   — Endogenous productivity + TWFE (Method II)
*   clktwfe — CLK + TWFE (Method III)
*   all     — Run all three methods
* Requires a prior pte estimation stored in e().

use "`root'/data/pte_example.dta", clear
gen ind = industry
xtset firm year

display _dup(70) "-"
display "  Section 5: Method Comparison"
display _dup(70) "-"
display ""

* First run baseline pte estimation
display "Running baseline pte estimation..."
display ""

capture noisily pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    omegapoly(3) nolog

* Compare with alternative estimators
if _rc == 0 {
    display ""
    display "Comparing CLK with alternative methods..."
    display ""
    capture which reghdfe
    if _rc == 0 {
        capture noisily pte_compare, method(all)
        if _rc != 0 {
            di as error "pte_compare failed with return code " _rc
            exit _rc
        }
    }
    else {
        display "Skipping pte_compare because reghdfe is not installed."
    }
}
display ""


* ============================================================================
* SECTION 6: HETEROGENEITY ANALYSIS
* ============================================================================
* pte_heterogeneity examines how treatment effects vary across subgroups
* defined by a discrete variable (e.g., industry). Reports group-specific
* ATT, contribution rates, and optionally a Cochran Q test for homogeneity.
* Requires a prior pte estimation with bootstrap.

use "`root'/data/pte_example.dta", clear
gen ind = industry
xtset firm year

display _dup(70) "-"
display "  Section 6: Heterogeneity Analysis"
display _dup(70) "-"
display ""

* Run pte with bootstrap for SE estimation
display "Running pte with bootstrap (20 reps) for heterogeneity analysis..."
display ""

capture noisily pte lny, treatment(D) ///
    free(lnl) state(lnk) proxy(lnm) ///
    omegapoly(3) bootstrap(20) seed(42) nolog

* Analyze heterogeneity by industry
if _rc == 0 {
    display ""
    display "Heterogeneity by industry (ind):"
    display ""
    capture noisily pte_heterogeneity, by(ind) test
    if _rc != 0 {
        di as error "pte_heterogeneity failed with return code " _rc
        exit _rc
    }
}
display ""


* ============================================================================
* DONE
* ============================================================================

display _dup(70) "="
display "  All extension examples completed."
display _dup(70) "="
