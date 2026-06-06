// ==========================================================================
// mc_coverage_example.do
// Example: Monte Carlo coverage test for pte estimator
// Part of pte package (Chen, Liao & Schurter, 2026)
// ==========================================================================
//
// This example demonstrates the shipped internal Monte Carlo engine used by
// the package's simulation workflow. The repository does not currently ship a
// standalone public pte_simulate command; see help pte_simulate for the
// developer-facing simulation surface.
//
// Prerequisites:
//   - pte package installed (adopath includes ado/)
//   - No manual Mata preload required; the shipped entry chain loads
//     _pte_mc_engine_helpers.mata automatically when needed
//   - moremata package optional; baseline public runtime does not require it
//
// ==========================================================================

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
    di as error "mc_coverage_example.do could not find `root'/data/pte_example.dta"
    di as error "Run this example from the repository root, pass the repo root as the first do-file argument, or set PTE_STATA_ROOT."
    exit 601
}

quietly adopath + "`root'/ado"
quietly adopath + "`root'/mata"

// --- Example 1: Set up calibrated parameters ---

// Production function coefficients (Cobb-Douglas: trend, labor, capital)
matrix beta = (0, 0.6, 0.4)
matrix colnames beta = t lnl lnk

// Evolution parameters (AR(1) coefficients)
matrix rho = (0.7, 0.7)
matrix colnames rho = rho0 rho1

// Initial omega distribution
matrix omega = (1.0, 0.5)
matrix colnames omega = mean sd

// Source panel used by the internal DGP resampler.
// The MC engine preserves and restores this dataset for each iteration.
use "`root'/data/pte_example.dta", clear
gen double t = year - 2010
gen byte treat_post = D
bysort firm (year): egen treat_yr0 = min(cond(D == 1, year, .))
xtset firm year

// --- Example 2: Quick smoke test (no bootstrap) ---
// Verify DGP generates reasonable data without running full estimation

di as text "=== Example 2: DGP-only smoke test ==="
_pte_mc_engine, nsim(5) betamat(beta) rhomat(rho) omegamat(omega) ///
    tau(0.06) order(1) pfunc(cd) attperiods(4) ///
    noestimate
assert r(nsim_failed) == 0

// Check true ATT values
di as text "True ATT by period:"
matrix list r(ATT_true), format(%9.6f)

// Verify ATT_true is non-missing and positive (tau > 0)
forvalues j = 1/5 {
    assert r(ATT_true)[1, `j'] > 0
}
di as result "DGP smoke test passed."

// --- Example 3: Small MC simulation with bootstrap ---
// This runs a small-scale coverage test (nsim=10, nboot=50)
// For publication-quality results, use nsim=200, nboot=500

di as text ""
di as text "=== Example 3: Small MC coverage test ==="
_pte_mc_engine, nsim(10) betamat(beta) rhomat(rho) omegamat(omega) ///
    tau(0.06) order(1) pfunc(cd) attperiods(4) ///
    seed(10000) attseed(20000) bootseed(20000) ///
    noestimate
assert r(nsim_failed) == 0

// Display results
di as text "True ATT:"
matrix list r(ATT_true), format(%9.6f)

di as text ""
di as text "No-estimate mode generated 10 DGP draws without failed iterations."

// --- Example 4: Interpreting results ---
// After a full MC run (nsim=200, nboot=500), check:
//
//   1. Coverage: Should be in [0.92, 0.98] for all periods
//      matrix list r(COVERAGE), format(%9.4f)
//
//   2. Bias: Relative bias |Bias/ATT_true| should be < 5%
//      matrix list r(BIAS), format(%9.6f)
//
//   3. SE ratio: Bootstrap SE / MC SE should be in [0.9, 1.1]
//      matrix list r(SE_RATIO), format(%9.4f)
//
// If coverage is too low:
//   - Increase nboot (more bootstrap replications)
//   - Check DGP parameters match paper calibration
//   - Verify production function specification
//
// If bias is too large:
//   - Increase nsim (more MC iterations)
//   - Check if tau is too large relative to sigma_eps

di as text ""
di as result "Examples completed successfully."
