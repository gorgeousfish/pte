*! _pte_het_contribution.ado
*! Calculate contribution rates to total ATT
*! Formula: Contribution_g = (n_g/N) * ATT_g / |ATT_total| * 100

version 14.0
capture program drop _pte_het_contribution
program define _pte_het_contribution, rclass
    version 14.0
    syntax , ATT_matrix(name) TOTAL_att(real) TOTAL_n(integer) ///
             [TOLerance(real 1e-6)]
    
    local G = rowsof(`att_matrix')
    
    tempname contribution
    matrix `contribution' = J(`G', 1, .)
    
    // ================================================================
    // Check if total ATT is near zero (tiered boundary handling)
    //   |ATT| > tolerance:       normal calculation
    //   |ATT| in (1e-8, tol]:   warn + calculate + mark unreliable
    //   |ATT| < 1e-8:           warn + set missing
    // ================================================================
    local abs_att = abs(`total_att')
    local is_unreliable = 0
    
    if `abs_att' < 1e-8 {
        display as text "Warning: Total ATT is essentially zero (" ///
            %12.2e `total_att' ")"
        display as text "Contribution rates set to missing"
        
        forvalues g = 1/`G' {
            matrix `contribution'[`g', 1] = .
        }
        
        return matrix contribution = `contribution'
        return scalar sum_contribution = .
        return scalar is_valid = 0
        exit
    }
    
    if `abs_att' <= `tolerance' {
        display as text "Warning: Total ATT is near zero (" ///
            %9.6f `total_att' "), below tolerance " %9.2e `tolerance'
        display as text "Contribution rates computed but marked unreliable"
        local is_unreliable = 1
    }
    
    // ================================================================
    // Compute contribution rates (absolute-value denominator)
    //   Contribution_g = (n_g / N) * ATT_g / |ATT_total| * 100
    //   Consistent with paper Table 2 sign convention
    // ================================================================
    local abs_total_att = abs(`total_att')
    
    forvalues g = 1/`G' {
        local att_g = `att_matrix'[`g', 1]
        local n_g   = `att_matrix'[`g', 3]
        
        if missing(`att_g') | `n_g' == 0 {
            matrix `contribution'[`g', 1] = .
        }
        else {
            local share_g  = `n_g' / `total_n'
            local contrib_g = (`share_g') * `att_g' / `abs_total_att' * 100
            matrix `contribution'[`g', 1] = `contrib_g'
        }
    }
    
    // ================================================================
    // Verify: sum(contribution) ~ sign(ATT_total) * 100%
    // ================================================================
    local sum_contrib = 0
    forvalues g = 1/`G' {
        local c = `contribution'[`g', 1]
        if !missing(`c') {
            local sum_contrib = `sum_contrib' + `c'
        }
    }
    
    local expected_sum = cond(`total_att' > 0, 100, -100)
    if abs(`sum_contrib' - `expected_sum') > 0.5 {
        display as text "Warning: Contribution sum = " ///
            %6.1f `sum_contrib' "%, expected " ///
            %6.1f `expected_sum' "%"
    }
    
    // ================================================================
    // Return results
    // ================================================================
    return matrix contribution = `contribution'
    return scalar sum_contribution = `sum_contrib'
    return scalar is_valid = 1
    return scalar is_unreliable = `is_unreliable'
    
end
