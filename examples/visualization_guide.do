*! visualization_guide.do
*! Example: Comprehensive guide to all pte_graph types
*! Part of pte package - Chen, Liao & Schurter (2026)
*! EPIC-012 US-E12-006 Task 91

// =========================================================================
// This example demonstrates graph types available from the public pte path:
//   A. Standard graphs (from pte estimation)
//      1. tt           - TT kernel density (Figure 4)
//      2. catt         - CATT by initial productivity (Figure 5)
//      3. att          - Dynamic ATT summary (Table 1)
//      4. scatter      - TT vs initial productivity
//      5. evolution    - Productivity evolution
//      6. heterogeneity - Heterogeneity analysis (Table 2)
//      7. compare      - Method comparison (Figure 6)
//      8. diagnose     - eps0 diagnostic (Figure E.1)
//   B. Bootstrap ATT graphs (available from public pte bootstrap)
//      9. att_dynamic       - ATT dynamic with CI bands
//     10. tt_distribution   - TT density by period
//     11. eps0_diagnostic   - CDF + Q-Q diagnostic
//   C. Reserved counterfactual wrappers
//      12. compare_cf       - requires a dedicated counterfactual bundle
//      13. ate_count_dynamic - requires a dedicated counterfactual bundle
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
    di as error "visualization_guide.do could not find `root'/data/pte_example.dta"
    di as error "Run this example from the repository root, pass the repo root as the first do-file argument, or set PTE_STATA_ROOT."
    exit 601
}

quietly adopath + "`root'/ado"

// =========================================================================
// Setup: Load data and run estimation
// =========================================================================

use "`root'/data/pte_example.dta", clear
xtset firm year

// Run pte with bootstrap for public graph access
pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) ///
    attperiods(4) pfunc(cd) omegapoly(3) ///
    bootstrap(5) level(95)

// =========================================================================
// A. Standard Graph Types
// =========================================================================

// --- 1. TT kernel density (Figure 4 style) ---
pte_graph, tt
// With custom periods
pte_graph, tt nt(0 1 2 3)

// --- 2. CATT by initial productivity (Figure 5 style) ---
pte_graph, catt
// 5 groups, byperiod layout (default)
pte_graph, catt quantiles(5)
// Note: type(bygroup) is accepted by the CATT worker but currently
// intercepted by the pte_graph router. Use the default byperiod layout.
// pte_graph, catt quantiles(5) type(bygroup)

// --- 3. Dynamic ATT summary ---
pte_graph, att level(95)
pte_graph, att title("Dynamic Treatment Effects on Productivity")

// --- 4. TT scatter ---
capture noisily pte_graph, scatter         // period 0
capture noisily pte_graph, scatter nt(2)   // period 2

// --- 5. Productivity evolution ---
capture noisily pte_graph, evolution

// --- 6. Diagnostic plots ---
// CDF comparison (Figure E.1)
capture noisily pte_graph, diagnose type(cdf)
if _rc == 0 {
    return list   // check K-S test: r(ks_D), r(ks_p)
}

// Kernel density comparison
capture noisily pte_graph, diagnose type(kdensity)

// =========================================================================
// B. Bootstrap ATT Graph Types
// =========================================================================

// --- 9. ATT dynamic effects with CI bands ---
capture noisily pte_graph, att_dynamic
// Suppress reference line
capture noisily pte_graph, att_dynamic norefline

// --- 10. TT distribution density by period ---
capture noisily pte_graph, tt_distribution

// --- 11. eps0 diagnostic: CDF + Q-Q ---
capture noisily pte_graph, eps0_diagnostic
// CDF only
capture noisily pte_graph, eps0_diagnostic cdfonly
// Q-Q only
capture noisily pte_graph, eps0_diagnostic qqonly

// =========================================================================
// C. Reserved Counterfactual Wrappers
// =========================================================================

di as text _n "Counterfactual wrappers such as compare_cf and ate_count_dynamic"
di as text "require a dedicated standardized counterfactual result object."
di as text "The top-level pte bootstrap path shown here does not create that bundle."

// =========================================================================
// D. Customization Examples
// =========================================================================

// Custom titles and export
capture noisily pte_graph, att_dynamic ///
    title("ATT Dynamics") ///
    xtitle("Event time") ///
    ytitle("Effect on log productivity")

// Export to different formats
// pte_graph, att_dynamic export(fig_att.png) width(1600) height(1200)
// pte_graph, att_dynamic export(fig_att.pdf)
// pte_graph, att_dynamic export(fig_att.eps)
// pte_graph, att_dynamic save(fig_att)   // .gph format

// Custom scheme
// pte_graph, att_dynamic scheme(s2color)

display _n "Visualization guide complete."
