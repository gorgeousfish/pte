*! _pte_graph_compare.ado
*! Method Comparison Graph (Figure 6 style)
*! Compares ATT estimates across different methods and specifications

version 14.0
program define _pte_graph_compare, rclass
    version 14.0
    
    // =========================================================================
    // T-002: Syntax parsing
    // =========================================================================
    
    syntax [, TItle(string) XTItle(string) ///
              SCHeme(string) SAVE(string) EXPort(string) ///
              Width(integer 800) Height(integer 600)]
    
    // =========================================================================
    // T-003: Check e(cmd)
    // =========================================================================
    
    if "`e(cmd)'" != "pte_compare" {
        di as error "{bf:Error}: pte_compare has not been run."
        di as error ""
        di as text "Please run {bf:pte_compare} first."
        di as text ""
        di as text "Example workflow:"
        di as text "    . pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D)"
        di as text "    . pte_compare, all"
        di as text "    . pte_graph, compare"
        exit 301
    }
    
    // =========================================================================
    // T-004: Matrix existence checks
    // =========================================================================
    
    local has_compare_contract = 1
    local required_matrices "compare_coef compare_ci_lower compare_ci_upper compare_spec"
    foreach mat of local required_matrices {
        capture confirm matrix e(`mat')
        if _rc {
            local has_compare_contract = 0
        }
    }

    tempname coef_mat ci_lower_mat ci_upper_mat spec_mat
    if `has_compare_contract' {
        matrix `coef_mat' = e(compare_coef)
        matrix `ci_lower_mat' = e(compare_ci_lower)
        matrix `ci_upper_mat' = e(compare_ci_upper)
        matrix `spec_mat' = e(compare_spec)
    }
    else {
        local legacy_matrices "coef_all ci_lower ci_upper spec_all"
        foreach mat of local legacy_matrices {
            capture confirm matrix e(`mat')
            if _rc {
                di as error "{bf:Error}: Required matrix e(compare_*) or legacy e(`mat') not found."
                di as error "This may indicate pte_compare did not complete successfully."
                exit 301
            }
        }

        matrix `coef_mat' = e(coef_all)'
        matrix `ci_lower_mat' = e(ci_lower)'
        matrix `ci_upper_mat' = e(ci_upper)'
        matrix `spec_mat' = e(spec_all)'
    }
    
    // =========================================================================
    // T-005: Dimension validation
    // =========================================================================
    
    if rowsof(`coef_mat') == 1 & colsof(`coef_mat') == 9 {
        matrix `coef_mat' = `coef_mat''
    }
    if rowsof(`ci_lower_mat') == 1 & colsof(`ci_lower_mat') == 9 {
        matrix `ci_lower_mat' = `ci_lower_mat''
    }
    if rowsof(`ci_upper_mat') == 1 & colsof(`ci_upper_mat') == 9 {
        matrix `ci_upper_mat' = `ci_upper_mat''
    }
    if rowsof(`spec_mat') == 1 & colsof(`spec_mat') == 9 {
        matrix `spec_mat' = `spec_mat''
    }

    local K = rowsof(`coef_mat')
    if `K' != 9 {
        di as error "{bf:Error}: Matrix dimension mismatch."
        di as error "Comparison coefficient matrix has `K' rows, expected 9."
        di as error ""
        di as text "The comparison graph requires all 9 method-specification combinations."
        di as text "Please run {bf:pte_compare, all} to generate complete results."
        exit 503
    }

    if colsof(`coef_mat') != 1 | colsof(`ci_lower_mat') != 1 | colsof(`ci_upper_mat') != 1 | colsof(`spec_mat') != 1 {
        di as error "{bf:Error}: Comparison graph matrices must be column vectors after normalization."
        exit 503
    }

    local canonical_rows "m1 m2 m3 m4 m5 m6 m7 m8 m9"
    local coef_rows : rownames `coef_mat'
    local ci_lower_rows : rownames `ci_lower_mat'
    local ci_upper_rows : rownames `ci_upper_mat'
    local spec_rows : rownames `spec_mat'
    local has_bad_rows = 0
    if `"`coef_rows'"' == "" | `"`ci_lower_rows'"' == "" | `"`ci_upper_rows'"' == "" | `"`spec_rows'"' == "" {
        local has_bad_rows = 1
    }
    else if `"`coef_rows'"' != `"`ci_lower_rows'"' | `"`coef_rows'"' != `"`ci_upper_rows'"' | `"`coef_rows'"' != `"`spec_rows'"' {
        local has_bad_rows = 1
    }
    else if `"`coef_rows'"' != "`canonical_rows'" {
        local has_bad_rows = 1
    }

    local expected_specs "1 2 3 1 2 3 1 2 3"
    local has_missing_row = 0
    local has_bad_spec = 0
    forvalues i = 1/9 {
        if missing(`coef_mat'[`i', 1]) | missing(`ci_lower_mat'[`i', 1]) | ///
            missing(`ci_upper_mat'[`i', 1]) | missing(`spec_mat'[`i', 1]) {
            local has_missing_row = 1
            continue, break
        }
        local expected_spec : word `i' of `expected_specs'
        if `spec_mat'[`i', 1] != `expected_spec' {
            local has_bad_spec = 1
            continue, break
        }
    }
    if `has_missing_row' {
        di as error "{bf:Error}: Comparison graph requires a complete nonmissing 9-row compare bundle."
        di as error "The active e(compare_*) results contain missing method/specification rows."
        di as error "Re-run {bf:pte_compare, method(all)} with all requested methods/specifications available before calling {bf:pte_graph, compare}."
        exit 503
    }
    if `has_bad_spec' {
        di as error "{bf:Error}: Comparison graph requires the canonical spec layout 1,2,3 repeated for each method."
        di as error "The active e(compare_spec) matrix does not match the advertised Table 3 compare contract."
        exit 503
    }
    if `has_bad_rows' {
        di as error "{bf:Error}: Comparison graph requires canonical compare row labels m1-m9 in order."
        di as error "The active e(compare_*) results do not preserve the Table 3 method ordering consumed by {bf:pte_graph, compare}."
        exit 503
    }
    
    // =========================================================================
    // T-007: Matrix extraction
    // =========================================================================
    
    local has_pte_att = 0
    tempname pte_att_scalar
    capture scalar `pte_att_scalar' = e(pte_att)
    if _rc == 0 & !missing(scalar(`pte_att_scalar')) {
        local has_pte_att = 1
        local pte_att = scalar(`pte_att_scalar')
    }
    
    // =========================================================================
    // T-008: Dataset construction
    // =========================================================================
    
    // Set defaults
    if `"`title'"' == "" local title "Method Comparison"
    if `"`xtitle'"' == "" local xtitle "Estimated Coefficient"
    if "`scheme'" == "" local scheme "s1color"
    
    preserve
    clear
    quietly set obs 9
    
    quietly gen int pte_gc_method_id = _n
    quietly gen double pte_gc_coef = .
    quietly gen double pte_gc_ci_lower = .
    quietly gen double pte_gc_ci_upper = .
    quietly gen int pte_gc_spec = .
    
    forvalues i = 1/9 {
        quietly replace pte_gc_coef = `coef_mat'[`i', 1] in `i'
        quietly replace pte_gc_ci_lower = `ci_lower_mat'[`i', 1] in `i'
        quietly replace pte_gc_ci_upper = `ci_upper_mat'[`i', 1] in `i'
        quietly replace pte_gc_spec = `spec_mat'[`i', 1] in `i'
    }
    
    // =========================================================================
    // T-009: Y-axis position calculation
    // =========================================================================
    // Method I (rows 1-3): center y=1
    // Method II (rows 4-6): center y=2
    // Method III (rows 7-9): center y=3
    // Within-method offset: (spec - 2) * 0.3
    
    quietly gen double pte_gc_y_pos = .
    quietly replace pte_gc_y_pos = 1 + (pte_gc_spec - 2) * 0.3 if inlist(pte_gc_method_id, 1, 2, 3)
    quietly replace pte_gc_y_pos = 2 + (pte_gc_spec - 2) * 0.3 if inlist(pte_gc_method_id, 4, 5, 6)
    quietly replace pte_gc_y_pos = 3 + (pte_gc_spec - 2) * 0.3 if inlist(pte_gc_method_id, 7, 8, 9)
    
    // =========================================================================
    // T-010 to T-013: Build graph command
    // =========================================================================
    
    // T-010: CI line segments (rcap, horizontal)
    // T-011: Point estimate markers (scatter, diamond)
    local graph_cmd "twoway"
    local graph_opts ""
    
    // Spec 1: blue (no lagged terms)
    local graph_cmd "`graph_cmd' (rcap pte_gc_ci_lower pte_gc_ci_upper pte_gc_y_pos if pte_gc_spec==1, horizontal lcolor(blue) lwidth(medium))"
    local graph_cmd "`graph_cmd' (scatter pte_gc_y_pos pte_gc_coef if pte_gc_spec==1, msymbol(D) mcolor(blue) msize(small))"
    
    // Spec 2: red (linear lagged terms)
    local graph_cmd "`graph_cmd' (rcap pte_gc_ci_lower pte_gc_ci_upper pte_gc_y_pos if pte_gc_spec==2, horizontal lcolor(red) lwidth(medium))"
    local graph_cmd "`graph_cmd' (scatter pte_gc_y_pos pte_gc_coef if pte_gc_spec==2, msymbol(D) mcolor(red) msize(small))"
    
    // Spec 3: green (third-order lagged terms)
    local graph_cmd "`graph_cmd' (rcap pte_gc_ci_lower pte_gc_ci_upper pte_gc_y_pos if pte_gc_spec==3, horizontal lcolor(green) lwidth(medium))"
    local graph_cmd "`graph_cmd' (scatter pte_gc_y_pos pte_gc_coef if pte_gc_spec==3, msymbol(D) mcolor(green) msize(small))"
    
    // T-012: Reference lines
    // Draw the package ATT reference only when the upstream compare producer
    // actually posted it; the 9-row Table 3 bundle remains graphable without
    // that optional scalar (for example after noatt-backed compare runs).
    if `has_pte_att' {
        local graph_opts "`graph_opts' xline(`pte_att', lcolor(black) lwidth(medium) lpattern(solid))"
    }
    else {
        local graph_opts "`graph_opts' xline(0, lcolor(white) lwidth(vthin) lpattern(solid))"
    }
    // Orange dashed separators between method groups
    local graph_opts "`graph_opts' yline(1.5 2.5, lcolor(orange) lpattern(dash) lwidth(thin))"
    
    // T-013: Axes and legend
    local graph_opts `"`graph_opts' ylabel(1 "Method I" 2 "Method II" 3 "Method III", angle(0) labsize(medium))"'
    local graph_opts "`graph_opts' yscale(range(0.5 3.5))"
    local graph_opts "`graph_opts' xlabel(, grid)"
    local graph_opts `"`graph_opts' xtitle(`"`xtitle'"')"'
    local graph_opts `"`graph_opts' ytitle("")"'
    local graph_opts `"`graph_opts' legend(order(1 "no lagged terms" 3 "linear lagged terms" 5 "third-order lagged terms") rows(1) position(6) size(small))"'
    local graph_opts `"`graph_opts' title(`"`title'"')"'
    if `has_pte_att' {
        local graph_opts `"`graph_opts' note("Black vertical line: ATT estimated by our method")"'
    }
    else {
        local graph_opts `"`graph_opts' note("Reference ATT line omitted")"'
    }
    local graph_opts "`graph_opts' scheme(`scheme')"
    
    // Execute graph
    `graph_cmd', `graph_opts'
    
    // =========================================================================
    // T-014: Export functionality
    // =========================================================================
    
    if `"`save'"' != "" {
        if !regexm(`"`save'"', "\.gph$") {
            local save "`save'.gph"
        }
        quietly graph save `"`save'"', replace
        di as text "Graph saved to: `save'"
    }
    
    if `"`export'"' != "" {
        local ext ""
        if regexm(`"`export'"', "\.[a-zA-Z]+$") {
            local ext = regexs(0)
        }
        
        if inlist(`"`ext'"', ".png", ".PNG") {
            quietly graph export `"`export'"', as(png) width(`width') height(`height') replace
        }
        else if inlist(`"`ext'"', ".eps", ".EPS") {
            quietly graph export `"`export'"', as(eps) replace
        }
        else if inlist(`"`ext'"', ".pdf", ".PDF") {
            quietly graph export `"`export'"', as(pdf) replace
        }
        else {
            di as error "{bf:Error}: Unsupported export format: `ext'"
            di as error "Supported formats: .png, .eps, .pdf"
            restore
            exit 198
        }
        di as text "Graph exported to: `export'"
    }
    
    // =========================================================================
    // Return values and cleanup
    // =========================================================================
    
    restore
    
    // r() return values
    return scalar n_points = 9
    return scalar n_methods = 3
    return scalar n_specs = 3
    if `has_pte_att' {
        return scalar pte_att = `pte_att'
    }
    else {
        return scalar pte_att = .
    }
    
    // Summary display
    di as text ""
    di as text "{bf:Method Comparison Graph}"
    di as text "{hline 60}"
    di as text "Points plotted: 9 (3 methods x 3 specifications)"
    if `has_pte_att' {
        di as text "PTE ATT reference: " %9.4f `pte_att'
    }
    else {
        di as text "PTE ATT reference: omitted"
    }
    di as text "{hline 60}"
    
end
