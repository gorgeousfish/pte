*! _pte_het_output.ado
*! Format and display heterogeneity analysis results
*! Displays Table 2 style output for industry-level treatment effects

version 14.0
capture program drop _pte_het_output
program define _pte_het_output
    version 14.0
    syntax , MATRIX(name) LABELS(string) LEVEL(real) [test] [NBOOT(string)] ///
             [TITLE(string)] [BYVAR(varname)]
    
    local G = rowsof(`matrix') - 1
    local ncol = colsof(`matrix')
    local has_contrib = (`ncol' == 4)
    local matrix_rownames : rownames `matrix'
    if `"`title'"' == "" {
        if "`byvar'" != "" {
            local by_label : variable label `byvar'
            if `"`by_label'"' == "" {
                local by_label "`byvar'"
            }
            gettoken by_label_clean by_label_rest : by_label, quotes
            if `"`by_label_clean'"' != "" {
                local by_label `"`by_label_clean'"'
            }
            local title `"`by_label'-level Treatment Effects on Productivity"'
        }
        else {
            local title "Heterogeneity Treatment Effects on Productivity"
        }
    }
    mata: st_local("title", subinstr(st_local("title"), char(96) + char(34), "", .))
    mata: st_local("title", subinstr(st_local("title"), char(34) + char(39), "", .))
    mata: st_local("title", subinstr(st_local("title"), char(34) + char(34), char(34), .))
    
    local width_label = 30
    local width_num = 12
    
    // ================================================================
    // Table header
    // ================================================================
    display as text ""
    display as text "{hline 79}"
    display as text _col(15) `"`macval(title)'"'
    display as text "{hline 79}"
    
    if `has_contrib' {
        display as text %-`width_label's "" _col(`width_label') "{c |}" ///
           _col(`=`width_label'+2') %~`width_num's "ATT" ///
           _col(`=`width_label'+`width_num'+2') %~`width_num's "SE" ///
           _col(`=`width_label'+2*`width_num'+2') %~`width_num's "Contrib(%)" ///
           _col(`=`width_label'+3*`width_num'+2') %~`width_num's "N"
    }
    else {
        display as text %-`width_label's "" _col(`width_label') "{c |}" ///
           _col(`=`width_label'+2') %~`width_num's "ATT" ///
           _col(`=`width_label'+`width_num'+2') %~`width_num's "SE" ///
           _col(`=`width_label'+2*`width_num'+2') %~`width_num's "N"
    }
    
    display as text "{hline `width_label'}{c +}{hline `=`ncol'*`width_num'+5'}"
    
    // ================================================================
    // Data rows
    // ================================================================
    local labels_work `"`labels'"'
    forvalues g = 1/`G' {
        // Get label
        gettoken lbl labels_work : labels_work, quotes
        if `"`lbl'"' == "" {
            local lbl : word `g' of `matrix_rownames'
        }
        mata: st_local("lbl", subinstr(st_local("lbl"), char(96) + char(34), "", .))
        mata: st_local("lbl", subinstr(st_local("lbl"), char(34) + char(39), "", .))
        mata: st_local("lbl", subinstr(st_local("lbl"), char(34) + char(34), char(34), .))
        
        // Get data values
        local att = `matrix'[`g', 1]
        local se = `matrix'[`g', 2]
        if `has_contrib' {
            local contrib = `matrix'[`g', 3]
            local n = `matrix'[`g', 4]
        }
        else {
            local n = `matrix'[`g', 3]
        }
        
        // Compute significance stars
        local stars = ""
        if !missing(`se') & `se' > 0 {
            local t = abs(`att' / `se')
            if `t' > 2.576 local stars = "***"
            else if `t' > 1.96 local stars = "**"
            else if `t' > 1.645 local stars = "*"
        }
        
        // Display row
        if `has_contrib' {
            display as text %-`width_label's `"`macval(lbl)'"' _col(`width_label') "{c |}" ///
               as result %`width_num'.4f `att' "`stars'" ///
               as result %`width_num'.4f `se' ///
               as result %`width_num'.1f `contrib' ///
               as result %`width_num'.0f `n'
        }
        else {
            display as text %-`width_label's `"`macval(lbl)'"' _col(`width_label') "{c |}" ///
               as result %`width_num'.4f `att' "`stars'" ///
               as result %`width_num'.4f `se' ///
               as result %`width_num'.0f `n'
        }
    }
    
    // ================================================================
    // Total row
    // ================================================================
    display as text "{hline `width_label'}{c +}{hline `=`ncol'*`width_num'+5'}"
    
    local total_row = `G' + 1
    local att = `matrix'[`total_row', 1]
    local se = `matrix'[`total_row', 2]
    if `has_contrib' {
        local contrib = `matrix'[`total_row', 3]
        local n = `matrix'[`total_row', 4]
        
        display as text %-`width_label's "Total" _col(`width_label') "{c |}" ///
           as result %`width_num'.4f `att' ///
           as result %`width_num'.4f `se' ///
           as result %`width_num'.1f `contrib' ///
           as result %`width_num'.0f `n'
    }
    else {
        local n = `matrix'[`total_row', 3]
        
        display as text %-`width_label's "Total" _col(`width_label') "{c |}" ///
           as result %`width_num'.4f `att' ///
           as result %`width_num'.4f `se' ///
           as result %`width_num'.0f `n'
    }
    
    // ================================================================
    // Footer
    // ================================================================
    display as text "{hline 79}"
    display as text "* p < 0.10, ** p < 0.05, *** p < 0.01"
    if "`nboot'" != "" {
        capture confirm number `nboot'
        if _rc != 0 {
            di as error "nboot() must be numeric when specified"
            exit 198
        }
        local nboot_value = real("`nboot'")
        if !missing(`nboot_value') & `nboot_value' > 0 {
            display as text "Bootstrap SE (`nboot_value' replications)"
        }
        else {
            display as text "SE inherited from stored group summary; bootstrap replication count not posted"
        }
    }
    else {
        display as text "SE inherited from stored group summary; bootstrap replication count not posted"
    }
    
    // ================================================================
    // Heterogeneity test results (if test option specified)
    // ================================================================
    if "`test'" != "" {
        display as text ""
        display as text "Heterogeneity Test:"
        display as text "{hline 79}"
        
        if !missing(e(Q_stat)) {
            local Q = e(Q_stat)
            local Q_p = e(Q_pvalue)
            local I2 = e(I2)
            local df = e(df)
            
            display as text "Cochran's Q = " as result %8.2f `Q' ///
               as text ", df = " as result `df' ///
               as text ", p = " as result %6.4f `Q_p'
            
            // I-squared interpretation
            local i2_interp = "low"
            if `I2' >= 25 & `I2' < 50 local i2_interp = "moderate"
            if `I2' >= 50 & `I2' < 75 local i2_interp = "substantial"
            if `I2' >= 75 local i2_interp = "considerable"
            
            display as text "I-squared = " as result %5.1f `I2' "%" ///
               as text " (`i2_interp' heterogeneity)"
            
            // Conclusion
            if `Q_p' < 0.05 {
                display as text "Conclusion: " as result ///
                    "Significant heterogeneity detected at 5% level"
            }
            else if `Q_p' < 0.10 {
                display as text "Conclusion: " as result ///
                    "Marginally significant heterogeneity at 10% level"
            }
            else {
                display as text "Conclusion: " as result ///
                    "No significant heterogeneity detected"
            }
        }
        else {
            display as text "Heterogeneity test results not available"
        }
        
        display as text "{hline 79}"
    }
    
end
