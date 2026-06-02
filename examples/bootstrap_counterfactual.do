*! bootstrap_counterfactual.do
*! Example: Public bootstrap ATT workflow with counterfactual contract notes
*! Part of pte package - Chen, Liao & Schurter (2026)
*! EPIC-012 US-E12-006 Task 90

// =========================================================================
// This example demonstrates the runnable public bootstrap workflow:
//   1. Load data and set panel structure
//   2. Run pte estimation with bootstrap on the baseline ATT path
//   3. Inspect public e() results
//   4. Generate ATT/TT graphs that the public path supports today
//   5. Export results to LaTeX/Excel/CSV
// Appendix D counterfactual ATE^count objects require dedicated workers and
// are not created by the top-level pte command.
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
    di as error "bootstrap_counterfactual.do could not find `root'/data/pte_example.dta"
    di as error "Run this example from the repository root, pass the repo root as the first do-file argument, or set PTE_STATA_ROOT."
    exit 601
}

quietly adopath + "`root'/ado"
capture mkdir "`root'/output"

// =========================================================================
// Step 1: Load data and set panel structure
// =========================================================================

use "`root'/data/pte_example.dta", clear
xtset firm year

// =========================================================================
// Step 2: Run public pte with bootstrap
// =========================================================================

// Cobb-Douglas production function with bootstrap ATT inference.
// The paper reports inference with B=500; this packaged example uses B=5
// so the full public workflow can be run as a smoke test.
pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
    attperiods(4) pfunc(cd) omegapoly(3) ///
    bootstrap(5) level(95)

// =========================================================================
// Step 3: Inspect estimation results
// =========================================================================

// List all stored results
ereturn list

// Key scalars on the public serial bootstrap path
display "ATT (pooled):       " e(ATT_avg)
display "Bootstrap reps:     " e(bootstrap)
display "Successful reps:    " e(n_success)

// Period-specific results
matrix list e(att_se),    title("ATT Standard Errors")
matrix list e(att_ci_lower), title("ATT Lower Bound (95% CI)")
matrix list e(att_ci_upper), title("ATT Upper Bound (95% CI)")
matrix list e(att_lb),    title("ATT Dynamic Lower Bound Alias")
matrix list e(att_ub),    title("ATT Dynamic Upper Bound Alias")

di as text _n "Note: the public pte command does not post Appendix D ATE^count, Delta, or Wald objects."

// =========================================================================
// Step 4: Generate ATT/TT graphs
// =========================================================================

// ATT dynamic effects with shaded CI band
pte_graph, att_dynamic
// graph export "output/att_dynamic.png", as(png) width(1200) replace

// TT kernel density by period
pte_graph, tt_distribution
// graph export "output/tt_dist.png", as(png) width(1200) replace

// eps0 diagnostic: CDF + Q-Q plot
pte_graph, eps0_diagnostic
// graph export "output/eps0_diag.png", as(png) width(1200) replace

// =========================================================================
// Step 5: Export results
// =========================================================================

// LaTeX table for paper
pte_export results using "`root'/output/table_effects.tex", ///
    format(latex) title("Treatment Effects on Productivity") replace

// Excel for further analysis
pte_export results using "`root'/output/results.xlsx", ///
    format(xlsx) replace

// CSV for portability
pte_export results using "`root'/output/results.csv", ///
    format(csv) replace

// =========================================================================
// Step 6: Translog specification (alternative)
// =========================================================================

/*
// Translog production function with bootstrap ATT inference
pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
    attperiods(4) pfunc(translog) omegapoly(3) ///
    bootstrap(500) level(95)

pte_graph, att_dynamic title("Translog ATT Dynamics")
pte_export results using "`root'/output/table_translog.tex", ///
    format(latex) title("Translog Treatment Effects") replace
*/

display _n "Public bootstrap ATT example complete."
