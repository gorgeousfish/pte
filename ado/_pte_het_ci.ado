*! _pte_het_ci.ado
*! Calculate confidence intervals for group ATT
*! Normal-based CI: ATT_g +/- z_{alpha/2} * SE_g

version 14.0
capture program drop _pte_het_ci
program define _pte_het_ci, rclass
    version 14.0
    syntax , ATT_matrix(name) SE_vector(name) LEVEL(real)
    
    local G = rowsof(`att_matrix')
    
    // ================================================================
    // Validate dimension consistency
    // ================================================================
    if rowsof(`se_vector') != `G' {
        display as error "Dimension mismatch: ATT matrix has `G' rows," ///
            " SE vector has " rowsof(`se_vector') " rows"
        exit 503
    }
    
    // ================================================================
    // Compute critical value z_{alpha/2}
    // ================================================================
    local alpha = 1 - `level' / 100
    local z_crit = invnormal(1 - `alpha' / 2)
    
    // ================================================================
    // Compute CI for each group: [ATT_g - z*SE_g, ATT_g + z*SE_g]
    // ================================================================
    tempname ci_matrix
    matrix `ci_matrix' = J(`G', 2, .)
    matrix colnames `ci_matrix' = Lower Upper
    
    forvalues g = 1/`G' {
        local att_g = `att_matrix'[`g', 1]
        local se_g  = `se_vector'[`g', 1]
        
        if missing(`att_g') | missing(`se_g') {
            matrix `ci_matrix'[`g', 1] = .
            matrix `ci_matrix'[`g', 2] = .
        }
        else {
            matrix `ci_matrix'[`g', 1] = `att_g' - `z_crit' * `se_g'
            matrix `ci_matrix'[`g', 2] = `att_g' + `z_crit' * `se_g'
        }
    }
    
    // ================================================================
    // Return results
    // ================================================================
    return matrix ci_matrix = `ci_matrix'
    return scalar z_crit = `z_crit'
    
end
