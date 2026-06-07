*! _pte_het_group_att.ado
*! Calculate group-level ATT for heterogeneity analysis
*! Computes ATT, SD, and N for each group defined by a discrete variable

version 14.0
capture program drop _pte_het_group_att
program define _pte_het_group_att, rclass
    version 14.0
    
    // =========================================================================
    // Syntax parsing
    // =========================================================================
    syntax , BYvar(varname) GROUPs(string) TTvar(varname) NTvar(varname) ///
        [TREATvar(varname)]

    local treated_condition ""
    if "`treatvar'" != "" {
        local treated_condition " & `treatvar' == 1"
    }
    
    // =========================================================================
    // Step 1: Count groups and initialize result matrix
    // =========================================================================
    local n_groups : word count `groups'
    
    tempname att_matrix
    matrix `att_matrix' = J(`n_groups', 3, .)
    matrix colnames `att_matrix' = ATT SD N
    
    // =========================================================================
    // Step 2: Loop over each group, compute mean/sd/N of TT
    //   Filter: byvar == g & ntvar >= 0 & !missing(ttvar)
    //     tabstat omg_tt if nt>=0, by(nt) stat(mean/sd/N)
    // =========================================================================
    local g_idx = 0
    local total_n_weighted = 0
    local sum_att_n = 0
    
    foreach g of local groups {
        local ++g_idx
        
        // Summarize TT for this group with nt >= 0 filter
        quietly summarize `ttvar' if `byvar' == `g' & `ntvar' >= 0 ///
            & !missing(`ttvar')`treated_condition'
        
        if r(N) == 0 {
            // Empty group: set to missing and warn
            display as text "Warning: no valid observations in group `g'" ///
                " (nt >= 0 & non-missing TT), setting to missing"
            matrix `att_matrix'[`g_idx', 1] = .
            matrix `att_matrix'[`g_idx', 2] = .
            matrix `att_matrix'[`g_idx', 3] = 0
        }
        else {
            // Store group-level statistics
            matrix `att_matrix'[`g_idx', 1] = r(mean)
            matrix `att_matrix'[`g_idx', 2] = r(sd)
            matrix `att_matrix'[`g_idx', 3] = r(N)
            
            // Accumulate for weighted average consistency check
            local total_n_weighted = `total_n_weighted' + r(N)
            local sum_att_n = `sum_att_n' + r(mean) * r(N)
        }
    }
    
    // =========================================================================
    // Step 3: Compute overall (total) ATT across the grouped sample
    //   Keep the total row on the same support as the reported group rows:
    //   valid TT observations with nt >= 0 and a nonmissing by-variable.
    // =========================================================================
    quietly summarize `ttvar' if `ntvar' >= 0 & !missing(`ttvar') ///
        & !missing(`byvar')`treated_condition'
    
    local total_att = r(mean)
    local total_sd  = r(sd)
    local total_n   = r(N)
    
    // =========================================================================
    // Step 4: Verify weighted average consistency
    //   sum(ATT_g * N_g) / sum(N_g) should equal total_att
    //   This is a sanity check; small floating-point differences are expected
    // =========================================================================
    if `total_n_weighted' > 0 {
        local weighted_att = `sum_att_n' / `total_n_weighted'
        local att_diff = abs(`weighted_att' - `total_att')
        if `att_diff' > 1e-8 {
            display as text "Note: weighted average ATT across groups" ///
                " differs from direct calculation by " ///
                %12.2e `att_diff'
            display as text "  Weighted avg: " %12.8f `weighted_att'
            display as text "  Direct calc:  " %12.8f `total_att'
        }
    }
    
    // =========================================================================
    // Step 5: Return results
    // =========================================================================
    return matrix att_matrix = `att_matrix'
    return scalar total_att = `total_att'
    return scalar total_sd  = `total_sd'
    return scalar total_n   = `total_n'
    
end
