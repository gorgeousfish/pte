*! _pte_graph_evolution.ado
*! Productivity Evolution Plot
*! Plots mean productivity trajectories for treated vs control groups
*! across periods relative to treatment

version 14.0
program define _pte_graph_evolution, rclass
    version 14.0
    
    syntax , [NTRange(numlist) LEVEL(integer 95) CURRENTLAWCHECKED ///
              TItle(string) XTItle(string) YTItle(string) ///
              SCHeme(string) COLor(string) ///
              SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600) ///
              NOci]
    
    // =========================================================================
    // Task 2: Prerequisite validation
    // =========================================================================
    
    foreach var in _pte_omega _pte_nt _pte_treat {
        capture confirm variable `var', exact
        if _rc {
            di as error "pte_graph requires prior pte estimation"
            di as error "variable `var' not found"
            di as error "run {bf:pte} command first"
            exit 111
        }
    }

    _pte_validate_internal_state _pte_omega numeric ///
        "pte_graph, evolution requires _pte_omega to remain the numeric productivity bridge."

    _pte_graph_evtreat, context("pte_graph, evolution") `currentlawchecked'
    
    // Check valid observations
    quietly count if !missing(_pte_omega)
    if r(N) == 0 {
        di as error "pte: no valid observations with non-missing _pte_omega"
        exit 2000
    }
    
    // =========================================================================
    // Task 3: Option parsing and defaults
    // =========================================================================
    
    // Validate confidence level
    if `level' < 10 | `level' > 99 {
        di as error "pte: level() must be between 10 and 99"
        exit 198
    }
    
    // Default ntrange
    if "`ntrange'" == "" local ntrange "-3 -2 -1 0 1 2 3 4"
    
    // Parse ntmin and ntmax from ntrange
    local ntmin = .
    local ntmax = .
    foreach val of numlist `ntrange' {
        if missing(`ntmin') | `val' < `ntmin' {
            local ntmin = `val'
        }
        if missing(`ntmax') | `val' > `ntmax' {
            local ntmax = `val'
        }
    }

    local xlabel_list "`ntrange'"
    
    // Default scheme and titles
    if "`scheme'" == "" local scheme "s1color"
    if `"`title'"' == "" local title "Productivity Evolution"
    if `"`xtitle'"' == "" local xtitle "Periods Relative to Treatment"
    if `"`ytitle'"' == "" local ytitle `"Mean Productivity ({&omega})"'
    
    // =========================================================================
    // Task 4a: Preserve data
    // =========================================================================
    
    preserve
    
    // =========================================================================
    // Task 4b: Data filtering
    // =========================================================================
    
    quietly keep if !missing(_pte_omega, _pte_nt, _pte_treat)
    tempvar _pte_keep_nt
    quietly gen byte `_pte_keep_nt' = 0
    foreach val of numlist `ntrange' {
        quietly replace `_pte_keep_nt' = 1 if _pte_nt == `val'
    }
    quietly keep if `_pte_keep_nt'
    
    // =========================================================================
    // Task 4c: Record observation counts
    // =========================================================================
    
    quietly count
    local nobs_total = r(N)
    
    quietly count if _pte_treat == 1
    local nobs_treat = r(N)
    
    quietly count if _pte_treat == 0
    local nobs_control = r(N)
    
    // =========================================================================
    // Task 4d: Collapse grouped statistics
    // =========================================================================
    
    collapse (mean) mean_omega=_pte_omega ///
             (sd) sd_omega=_pte_omega ///
             (count) n=_pte_omega, ///
             by(_pte_treat _pte_nt)
    
    // Sort for connected line drawing
    sort _pte_treat _pte_nt
    
    // =========================================================================
    // Task 5: Confidence band calculation
    // =========================================================================
    
    // SE = sd / sqrt(n)
    quietly gen double se = sd_omega / sqrt(n)
    
    // z critical value
    local z = invnormal((100 + `level') / 200)
    
    // CI bounds
    quietly gen double ci_upper = mean_omega + `z' * se
    quietly gen double ci_lower = mean_omega - `z' * se
    
    // Set CI to missing when n < 2 (no valid SE)
    quietly replace ci_upper = . if n < 2
    quietly replace ci_lower = . if n < 2
    quietly replace se = . if n < 2
    
    // =========================================================================
    // Task 6: Store return value statistics in locals before restore
    // =========================================================================
    
    // Count periods available
    quietly levelsof _pte_nt, local(available_periods)
    local n_periods : word count `available_periods'
    
    // Store per-period statistics for treated and control
    // Use safe macro names: replace "-" with "m" for negative periods
    foreach nt of numlist `ntrange' {
        // Build safe macro name suffix
        local suf = "`nt'"
        if `nt' < 0 {
            local abs_nt = abs(`nt')
            local suf = "m`abs_nt'"
        }
        
        // Treated group
        quietly count if _pte_treat == 1 & _pte_nt == `nt'
        if r(N) > 0 {
            quietly summarize mean_omega if _pte_treat == 1 & _pte_nt == `nt', meanonly
            local mean_treat_`suf' = r(mean)
            quietly summarize se if _pte_treat == 1 & _pte_nt == `nt', meanonly
            local se_treat_`suf' = r(mean)
            quietly summarize n if _pte_treat == 1 & _pte_nt == `nt', meanonly
            local nobs_treat_`suf' = r(mean)
        }
        else {
            local mean_treat_`suf' = .
            local se_treat_`suf' = .
            local nobs_treat_`suf' = 0
        }
        
        // Control group
        quietly count if _pte_treat == 0 & _pte_nt == `nt'
        if r(N) > 0 {
            quietly summarize mean_omega if _pte_treat == 0 & _pte_nt == `nt', meanonly
            local mean_control_`suf' = r(mean)
            quietly summarize se if _pte_treat == 0 & _pte_nt == `nt', meanonly
            local se_control_`suf' = r(mean)
            quietly summarize n if _pte_treat == 0 & _pte_nt == `nt', meanonly
            local nobs_control_`suf' = r(mean)
        }
        else {
            local mean_control_`suf' = .
            local se_control_`suf' = .
            local nobs_control_`suf' = 0
        }
    }
    
    // =========================================================================
    // Task 7: Data range check and adjustment
    // =========================================================================
    
    quietly count
    if r(N) == 0 {
        di as error "pte: no data available in ntrange(`ntrange')"
        di as error "  Try adjusting ntrange() to match available periods"
        restore
        exit 2000
    }
    
    // Check if both groups present
    quietly count if _pte_treat == 1
    local has_treat = (r(N) > 0)
    quietly count if _pte_treat == 0
    local has_control = (r(N) > 0)
    
    if `has_treat' == 0 & `has_control' == 0 {
        di as error "pte: no observations for either group in ntrange"
        restore
        exit 2000
    }
    
    if `has_treat' == 0 {
        di as text "{bf:Warning}: no treated group observations in ntrange"
    }
    if `has_control' == 0 {
        di as text "{bf:Warning}: no control group observations in ntrange"
    }
    
    // =========================================================================
    // Task 8: Build twoway command - confidence bands
    // =========================================================================
    
    local graph_cmd "twoway"
    local plot_idx = 0
    
    if "`noci'" == "" {
        // Treated CI band
        if `has_treat' {
            local graph_cmd "`graph_cmd' (rarea ci_lower ci_upper _pte_nt if _pte_treat==1 & !missing(ci_lower, ci_upper), color(navy%30) fintensity(30))"
            local plot_idx = `plot_idx' + 1
        }
        
        // Control CI band
        if `has_control' {
            local graph_cmd "`graph_cmd' (rarea ci_lower ci_upper _pte_nt if _pte_treat==0 & !missing(ci_lower, ci_upper), color(maroon%30) fintensity(30))"
            local plot_idx = `plot_idx' + 1
        }
    }
    
    // =========================================================================
    // Task 9: Build twoway command - path lines
    // =========================================================================
    
    // Treated connected line
    local treat_idx = 0
    if `has_treat' {
        local plot_idx = `plot_idx' + 1
        local treat_idx = `plot_idx'
        local graph_cmd "`graph_cmd' (connected mean_omega _pte_nt if _pte_treat==1, lc(navy) mc(navy) m(O) lw(0.5) msize(2))"
    }
    
    // Control connected line
    local control_idx = 0
    if `has_control' {
        local plot_idx = `plot_idx' + 1
        local control_idx = `plot_idx'
        local graph_cmd "`graph_cmd' (connected mean_omega _pte_nt if _pte_treat==0, lc(maroon) mc(maroon) m(T) lp(dash) lw(0.5) msize(2))"
    }
    
    // =========================================================================
    // Task 10: Add reference line (nt=0) and chart options
    // =========================================================================
    
    // Check if ntrange contains 0
    local has_zero = 0
    foreach val of numlist `ntrange' {
        if `val' == 0 {
            local has_zero = 1
        }
    }
    
    // Start options section with comma
    if `has_zero' {
        local graph_cmd "`graph_cmd', xline(0, lc(gray) lp(dash) lw(0.5))"
    }
    else {
        local graph_cmd "`graph_cmd',"
    }
    
    // =========================================================================
    // Task 11: Add legend and titles
    // =========================================================================
    
    // Build legend
    local legend_items ""
    if `has_treat' & `treat_idx' > 0 {
        local legend_items `"`legend_items' `treat_idx' "Treated""'
    }
    if `has_control' & `control_idx' > 0 {
        local legend_items `"`legend_items' `control_idx' "Control""'
    }
    
    local graph_cmd `"`graph_cmd' legend(order(`legend_items') ring(0) col(1) pos(2) region(fcolor(none) lpattern(blank)))"'
    
    // Titles
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    local graph_cmd `"`graph_cmd' xtitle(`"`xtitle'"')"'
    local graph_cmd `"`graph_cmd' ytitle(`"`ytitle'"')"'
    
    // X-axis labels
    local graph_cmd `"`graph_cmd' xlabel(`xlabel_list', grid)"'
    
    // Y-axis grid
    local graph_cmd `"`graph_cmd' ylabel(, grid)"'
    
    // Apply scheme
    local graph_cmd "`graph_cmd' scheme(`scheme')"
    
    // =========================================================================
    // Execute graph command
    // =========================================================================
    
    `graph_cmd'
    
    // =========================================================================
    // Task 12: Save .gph
    // =========================================================================
    
    if "`save'" != "" {
        if !regexm("`save'", "\.gph$") {
            local save "`save'.gph"
        }
        graph save "`save'", replace
        di as text "graph saved to `save'"
    }
    
    // =========================================================================
    // Task 13: Export PNG/EPS/PDF
    // =========================================================================
    
    if "`export'" != "" {
        // Validate supported format
        local ext = ""
        if regexm("`export'", "\.([a-zA-Z]+)$") {
            local ext = regexs(1)
        }
        if "`ext'" != "" {
            local ext = lower("`ext'")
            if !inlist("`ext'", "png", "eps", "pdf", "tif") {
                di as error "pte: unsupported export format '.`ext''"
                di as error "  Supported formats: .png, .eps, .pdf, .tif"
                exit 198
            }
        }
        graph export "`export'", width(`width') height(`height') replace
        di as text "graph exported to `export'"
    }
    
    // =========================================================================
    // Task 14: Restore BEFORE setting return values
    // =========================================================================
    
    restore
    
    // Set r() return values (after restore, using locals saved earlier)
    return local graph_type "evolution"
    return local graph_cmd `"`graph_cmd'"'
    return local ntrange "`ntrange'"
    
    return scalar level = `level'
    return scalar nobs_total = `nobs_total'
    return scalar nobs_treat = `nobs_treat'
    return scalar nobs_control = `nobs_control'
    return scalar n_periods = `n_periods'
    
    // Per-period return values
    foreach nt of numlist `ntrange' {
        // Convert negative period names: replace "-" with "m"
        local suf = "`nt'"
        if `nt' < 0 {
            local abs_nt = abs(`nt')
            local suf = "m`abs_nt'"
        }
        
        // Treated group
        return scalar mean_treat_`suf' = `mean_treat_`suf''
        return scalar se_treat_`suf' = `se_treat_`suf''
        return scalar nobs_treat_`suf' = `nobs_treat_`suf''
        
        // Control group
        return scalar mean_control_`suf' = `mean_control_`suf''
        return scalar se_control_`suf' = `se_control_`suf''
        return scalar nobs_control_`suf' = `nobs_control_`suf''
    }
    
    // =========================================================================
    // Task 15: Summary display
    // =========================================================================
    
    di as text ""
    di as text "{bf:`title'}"
    di as text "{hline 70}"
    di as text "NT range:            `ntrange'"
    di as text "Confidence level:    `level'%"
    di as text "Total observations:  " %10.0fc `nobs_total'
    di as text "  Treated:           " %10.0fc `nobs_treat'
    di as text "  Control:           " %10.0fc `nobs_control'
    di as text ""
    
    // Table header
    di as text "{col 3}Period{col 14}Treated Mean(SE){col 38}Control Mean(SE){col 62}Diff"
    di as text "{hline 70}"
    
    // Table rows
    foreach nt of numlist `ntrange' {
        local suf = "`nt'"
        if `nt' < 0 {
            local abs_nt = abs(`nt')
            local suf = "m`abs_nt'"
        }
        
        local mt = `mean_treat_`suf''
        local st = `se_treat_`suf''
        local mc = `mean_control_`suf''
        local sc = `se_control_`suf''
        
        // Format treated
        if !missing(`mt') {
            local treat_str : di %7.4f `mt' " (" %5.4f `st' ")"
        }
        else {
            local treat_str "      .          "
        }
        
        // Format control
        if !missing(`mc') {
            local control_str : di %7.4f `mc' " (" %5.4f `sc' ")"
        }
        else {
            local control_str "      .          "
        }
        
        // Format difference
        if !missing(`mt') & !missing(`mc') {
            local diff = `mt' - `mc'
            local diff_str : di %7.4f `diff'
        }
        else {
            local diff_str "      ."
        }
        
        di as text "{col 3}" %4.0f `nt' "{col 14}`treat_str'{col 38}`control_str'{col 62}`diff_str'"
    }
    
    di as text "{hline 70}"
    
end
