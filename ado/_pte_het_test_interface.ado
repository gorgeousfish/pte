*! _pte_het_test_interface.ado
*! Interface to heterogeneity statistical tests
*! Computes Cochran's Q statistic and I-squared for heterogeneity testing

version 14.0
capture program drop _pte_het_test_interface
program define _pte_het_test_interface, rclass
    version 14.0
    syntax , ATT_matrix(name) SE_vector(name) N_groups(integer) [Level(cilevel)]
    
    // ================================================================
    // Set significance level from confidence level (default 95 -> alpha 0.05)
    // ================================================================
    if "`level'" == "" {
        local level = 95
    }
    local alpha = 1 - `level' / 100
    
    // ================================================================
    // Cochran's Q statistic
    // Q = sum(w_g * (ATT_g - ATT_pooled)^2)
    // w_g = 1 / SE_g^2 (inverse variance weight)
    // ================================================================
    
    local G = `n_groups'
    
    // Compute inverse-variance weighted pooled ATT (fixed-effects estimate)
    local sum_w = 0
    local sum_w_att = 0
    local G_valid = 0
    
    forvalues g = 1/`G' {
        local att_g = `att_matrix'[`g', 1]
        local se_g = `se_vector'[`g', 1]
        
        if !missing(`att_g') & !missing(`se_g') & `se_g' > 0 {
            local w_g = 1 / (`se_g'^2)
            local sum_w = `sum_w' + `w_g'
            local sum_w_att = `sum_w_att' + `w_g' * `att_g'
            local G_valid = `G_valid' + 1
        }
    }
    
    if `sum_w' == 0 {
        display as error "Cannot compute Q statistic: all SE are missing or zero"
        return scalar Q_stat = .
        return scalar Q_pvalue = .
        return scalar I2 = .
        exit
    }
    
    if `G_valid' < 2 {
        display as error "Cannot compute Q statistic: fewer than 2 valid groups"
        return scalar Q_stat = .
        return scalar Q_pvalue = .
        return scalar I2 = .
        return scalar df = 0
        exit
    }
    
    local att_pooled = `sum_w_att' / `sum_w'
    
    // Compute Q statistic
    local Q = 0
    forvalues g = 1/`G' {
        local att_g = `att_matrix'[`g', 1]
        local se_g = `se_vector'[`g', 1]
        
        if !missing(`att_g') & !missing(`se_g') & `se_g' > 0 {
            local w_g = 1 / (`se_g'^2)
            local Q = `Q' + `w_g' * (`att_g' - `att_pooled')^2
        }
    }
    
    // ================================================================
    // Degrees of freedom and p-value
    // ================================================================
    local df = `G_valid' - 1
    local Q_pvalue = chi2tail(`df', `Q')
    
    // ================================================================
    // I-squared heterogeneity measure
    // I^2 = max(0, (Q - df) / Q * 100)
    // ================================================================
    if `Q' > 0 {
        local I2 = max(0, (`Q' - `df') / `Q' * 100)
    }
    else {
        local I2 = 0
    }
    
    // ================================================================
    // Heterogeneity degree classification (Higgins & Thompson 2002)
    // ================================================================
    if `I2' < 25 {
        local hetero_degree "low"
    }
    else if `I2' < 50 {
        local hetero_degree "moderate-low"
    }
    else if `I2' < 75 {
        local hetero_degree "moderate-high"
    }
    else {
        local hetero_degree "high"
    }
    
    // ================================================================
    // Significance determination
    // ================================================================
    local hetero_sig = (`Q_pvalue' < `alpha')
    
    // ================================================================
    // Conclusion text generation (AC-024)
    // ================================================================
    local I2_fmt : display %9.1f `I2'
    local I2_fmt = strtrim("`I2_fmt'")
    
    if `hetero_sig' == 1 {
        local conclusion "Significant heterogeneity detected (p = `: display %6.4f `Q_pvalue'', I-squared = `I2_fmt'%, `hetero_degree' heterogeneity). Treatment effects differ significantly across groups at the `=`alpha'*100'% level."
    }
    else {
        local conclusion "No significant heterogeneity detected (p = `: display %6.4f `Q_pvalue'', I-squared = `I2_fmt'%, `hetero_degree' heterogeneity). Treatment effects are consistent across groups at the `=`alpha'*100'% level."
    }
    
    // ================================================================
    // Display formatted output (AC-023)
    // ================================================================
    display as text ""
    display as text "{hline 70}"
    display as text "Heterogeneity Test Results"
    display as text "{hline 70}"
    display as text ""
    display as text "  Number of valid groups (G):" _col(38) %10.0f `G_valid'
    display as text "  Pooled CATT estimate:" _col(38) %10.4f `att_pooled'
    display as text ""
    display as text "  Cochran's Q statistic:" _col(38) %10.4f `Q'
    display as text "  Degrees of freedom:" _col(38) %10.0f `df'
    display as text "  p-value:" _col(38) %10.4f `Q_pvalue'
    display as text ""
    display as text "  I-squared statistic:" _col(38) %9.1f `I2' "%"
    display as text "  Interpretation:" _col(38) "`hetero_degree' heterogeneity"
    display as text ""
    display as text "{hline 70}"
    if `hetero_sig' == 1 {
        display as text "  Conclusion: " as error "`conclusion'"
    }
    else {
        display as text "  Conclusion: " as result "`conclusion'"
    }
    display as text "{hline 70}"
    
    // ================================================================
    // Return results
    // ================================================================
    return scalar Q_stat = `Q'
    return scalar Q_pvalue = `Q_pvalue'
    return scalar I2 = `I2'
    return scalar df = `df'
    return scalar att_pooled = `att_pooled'
    return scalar CATT_pool = `att_pooled'
    return scalar hetero_sig = `hetero_sig'
    return scalar alpha = `alpha'
    
    return local hetero_degree "`hetero_degree'"
    return local conclusion "`conclusion'"
    
end
