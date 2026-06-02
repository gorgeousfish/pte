*! _pte_het_matrix.ado
*! Construct final result matrix for heterogeneity analysis

version 14.0
capture program drop _pte_het_matrix
program define _pte_het_matrix, rclass
    version 14.0
    syntax , ATTMAT(name) SEVEC(name) [CONTRIB(name)] ///
             TOTATT(real) TOTSE(real) TOTN(integer) ///
             LABELS(string)

    local G = rowsof(`attmat')
    local has_contrib = ("`contrib'" != "")
    
    // =========================================================================
    // Build result matrix: (G+1) rows x 4 or 3 columns
    // =========================================================================
    local ncol = cond(`has_contrib', 4, 3)
    
    tempname result
    matrix `result' = J(`G' + 1, `ncol', .)
    
    if `has_contrib' {
        matrix colnames `result' = ATT SE Contribution N
    }
    else {
        matrix colnames `result' = ATT SE N
    }
    
    // =========================================================================
    // Fill group data rows
    // =========================================================================
    forvalues g = 1/`G' {
        // ATT from column 1
        matrix `result'[`g', 1] = `attmat'[`g', 1]
        // SE from sevec
        matrix `result'[`g', 2] = `sevec'[`g', 1]
        // Contribution and N
        if `has_contrib' {
            matrix `result'[`g', 3] = `contrib'[`g', 1]
            matrix `result'[`g', 4] = `attmat'[`g', 3]
        }
        else {
            matrix `result'[`g', 3] = `attmat'[`g', 3]
        }
    }
    
    // =========================================================================
    // Add Total row
    // =========================================================================
    local total_row = `G' + 1
    matrix `result'[`total_row', 1] = `totatt'
    matrix `result'[`total_row', 2] = `totse'

    if `has_contrib' {
        local contrib_all_missing = 1
        forvalues g = 1/`=rowsof(`contrib')' {
            if !missing(`contrib'[`g', 1]) {
                local contrib_all_missing = 0
            }
        }
        if `contrib_all_missing' {
            matrix `result'[`total_row', 3] = .
        }
        else {
            matrix `result'[`total_row', 3] = cond(`totatt' > 0, 100, -100)
        }
        matrix `result'[`total_row', 4] = `totn'
    }
    else {
        matrix `result'[`total_row', 3] = `totn'
    }
    
    // =========================================================================
    // Set row names from labels
    // =========================================================================
    local rownames ""
    local g_idx = 0
    foreach lbl of local labels {
        local ++g_idx
        // Clean label: matrix rownames cannot contain spaces or quotes
        local lbl_clean = subinstr("`lbl'", " ", "_", .)
        local lbl_clean = subinstr("`lbl_clean'", `"""', "", .)
        local rownames "`rownames' `lbl_clean'"
    }
    local rownames "`rownames' Total"
    
    matrix rownames `result' = `rownames'
    
    // =========================================================================
    // Return results
    // =========================================================================
    return matrix result = `result'
    return local rownames = "`rownames'"
    return scalar n_groups = `G'
    
end
