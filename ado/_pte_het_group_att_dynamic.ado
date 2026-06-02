*! _pte_het_group_att_dynamic.ado
*! Dynamic ATT by group and period
*! Computes ATT_g(l) for each group g and period l = 0..L

version 14.0
capture program drop _pte_het_group_att_dynamic
program define _pte_het_group_att_dynamic, rclass
    version 14.0
    syntax , BYvar(varname) GROUPs(string) TTvar(varname) NTvar(varname)
    
    // ================================================================
    // Determine max treatment period
    // ================================================================
    qui summarize `ntvar' if `ntvar' >= 0
    if r(N) == 0 {
        display as error "No observations with `ntvar' >= 0"
        exit 2000
    }
    local max_nt = r(max)
    local n_groups : word count `groups'
    local ncol = `max_nt' + 2  // columns: l=0..L + ATT(all)
    
    // ================================================================
    // Build dynamic ATT matrix: G x (L+2)
    // ================================================================
    tempname att_dynamic n_dynamic
    matrix `att_dynamic' = J(`n_groups', `ncol', .)
    matrix `n_dynamic' = J(`n_groups', `ncol', 0)
    
    // Column names: t0 t1 ... tL ATT_all
    local colnames ""
    forvalues l = 0/`max_nt' {
        local colnames "`colnames' t`l'"
    }
    local colnames "`colnames' ATT_all"
    matrix colnames `att_dynamic' = `colnames'
    matrix colnames `n_dynamic' = `colnames'
    
    // ================================================================
    // Loop over groups and periods
    // ================================================================
    local g_idx = 0
    foreach g of local groups {
        local ++g_idx
        
        // Period-specific ATT
        forvalues l = 0/`max_nt' {
            qui summarize `ttvar' if `byvar' == `g' & `ntvar' == `l' ///
                & !missing(`ttvar')
            if r(N) > 0 {
                matrix `att_dynamic'[`g_idx', `l'+1] = r(mean)
                matrix `n_dynamic'[`g_idx', `l'+1] = r(N)
                if r(N) < 5 {
                    display as text ///
                        "Warning: Group `g', period `l' has " ///
                        r(N) " obs (< 5)"
                }
            }
        }
        
        // Overall ATT for this group
        qui summarize `ttvar' if `byvar' == `g' & `ntvar' >= 0 ///
            & !missing(`ttvar')
        if r(N) > 0 {
            matrix `att_dynamic'[`g_idx', `ncol'] = r(mean)
            matrix `n_dynamic'[`g_idx', `ncol'] = r(N)
        }
    }
    
    // ================================================================
    // Return results
    // ================================================================
    return matrix att_dynamic = `att_dynamic'
    return matrix n_dynamic = `n_dynamic'
    return scalar max_nt = `max_nt'
    return scalar n_groups = `n_groups'
    
end
