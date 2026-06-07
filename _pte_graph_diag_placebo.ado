*! _pte_graph_diag_placebo.ado
*! Placebo test histogram

version 14.0
program define _pte_graph_diag_placebo, rclass
    version 14.0
    
    syntax , COEF(varname) REFVAL(real) [BINS(integer 20) ///
             TItle(string) XTItle(string) YTItle(string) ///
             SAVE(string) EXPORT(string) ///
             WIDTH(integer 800) HEIGHT(integer 600)]
    
    // =========================================
    // Step 1: Validate required parameters
    // (DD-014.5: coef() and refval() have no defaults, avoid misleading users)
    // coef and refval enforced by syntax
    // =========================================
    
    // =========================================
    // Step 2: Validate coef variable
    // =========================================
    capture confirm variable `coef'
    if _rc {
        di as error "pte_graph diagnose type(placebo): variable `coef' not found"
        exit 111
    }
    
    // =========================================
    // Step 3: Check data validity
    // =========================================
    qui count if !missing(`coef')
    local nobs = r(N)
    
    if `nobs' == 0 {
        di as error "no valid observations in `coef'"
        exit 2000
    }
    
    if `nobs' < 50 {
        di as text "{bf:Warning}: only `nobs' placebo replications, recommend >= 100"
    }
    
    // =========================================
    // Step 4: Compute statistics
    // =========================================
    qui sum `coef', detail
    local placebo_mean = r(mean)
    local placebo_sd = r(sd)
    local placebo_n = r(N)
    
    // =========================================
    // Step 5: Compute p-value (two-sided)
    // p = count(|coef| >= |refval|) / n
    // =========================================
    qui count if !missing(`coef') & abs(`coef') >= abs(`refval')
    local placebo_pval = r(N) / `placebo_n'
    
    // =========================================
    // Step 6: Set default titles
    // =========================================
    if `"`title'"' == "" local title "Placebo Test: Distribution of Coefficients"
    if `"`xtitle'"' == "" local xtitle "Regression Coefficient"
    if `"`ytitle'"' == "" local ytitle "Frequency"
    
    // =========================================
    // Step 7: Build histogram command
    // =========================================
    local graph_cmd "twoway"
    local graph_cmd "`graph_cmd' (hist `coef', bin(`bins') fc(gray%0) lc(black%60))"
    local graph_cmd "`graph_cmd', xline(`refval', lc(red) lw(0.8))"
    local graph_cmd `"`graph_cmd' xtitle(`"`xtitle'"')"'
    local graph_cmd `"`graph_cmd' ytitle(`"`ytitle'"')"'
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    local graph_cmd `"`graph_cmd' note("Red line: actual estimate = `refval'")"'
    local graph_cmd "`graph_cmd' legend(off)"
    
    // =========================================
    // Step 8: Execute plot
    // =========================================
    `graph_cmd'
    
    // =========================================
    // Step 9: Save/export
    // =========================================
    if "`save'" != "" {
        if !regexm("`save'", "\.gph$") {
            local save "`save'.gph"
        }
        graph save "`save'", replace
        di as text "graph saved to `save'"
    }
    
    if "`export'" != "" {
        graph export "`export'", width(`width') height(`height') replace
        di as text "graph exported to `export'"
    }
    
    // =========================================
    // Step 10: Return values
    // =========================================
    return local type "placebo"
    return scalar placebo_mean = `placebo_mean'
    return scalar placebo_sd = `placebo_sd'
    return scalar placebo_n = `placebo_n'
    return scalar placebo_pval = `placebo_pval'
    return scalar refval = `refval'
    
    // Display results
    di as text ""
    di as text "{bf:Placebo Test Results}"
    di as text "{hline 40}"
    di as text "Placebo replications: " %6.0f `placebo_n'
    di as text "Placebo mean:         " %9.4f `placebo_mean'
    di as text "Placebo std. dev.:    " %9.4f `placebo_sd'
    di as text "Actual estimate:      " %9.4f `refval'
    di as text "Two-sided p-value:    " %9.4f `placebo_pval'
    di as text "{hline 40}"
    if `placebo_pval' < 0.05 {
        di as result "Actual estimate is significantly different from placebo distribution"
    }
    else {
        di as text "Actual estimate is not significantly different from placebo distribution"
    }
end
