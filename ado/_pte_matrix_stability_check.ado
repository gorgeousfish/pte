*! _pte_matrix_stability_check.ado
*! Matrix stability diagnostics
*! Wrapper for Mata pte_check_matrix_stability() and pte_condition_number()
*! Provides Stata-level interface for matrix stability checks.
*! Replication code has NO stability checks (pte improvement)

version 14.0
program define _pte_matrix_stability_check, rclass
    version 14.0
    
    syntax, Zmat(string) Wmat(string) [tolerance(real 1e-10) Verbose]
    
    // -----------------------------------------------------------------------
    // Validate inputs: confirm matrices exist
    // -----------------------------------------------------------------------
    confirm matrix `zmat'
    local n = rowsof(`zmat')
    local k = colsof(`zmat')
    
    if `n' == 0 | `k' == 0 {
        display as error "_pte_matrix_stability_check: empty Z matrix"
        return scalar is_stable = 0
        return scalar cond_num = .
        return scalar det_val = .
        return scalar rank_val = .
        return scalar min_eigenvalue = .
        exit
    }
    
    // -----------------------------------------------------------------------
    // Compute Z'Z and check stability via Mata
    // -----------------------------------------------------------------------
    local verbose_flag = ("`verbose'" != "")
    
    tempname ZtZ ZtZ_sym W_result
    
    mata: st_matrix("`ZtZ'", cross(st_matrix("`zmat'"), st_matrix("`zmat'")))
    
    // Force symmetry
    mata: st_matrix("`ZtZ_sym'", ///
        (st_matrix("`ZtZ'") + st_matrix("`ZtZ'")') / 2)
    
    // -----------------------------------------------------------------------
    // Check 1: Condition number
    // -----------------------------------------------------------------------
    mata: st_numscalar("r(cond_num)", ///
        pte_condition_number(st_matrix("`ZtZ_sym'")))
    local cond_num = r(cond_num)
    
    if `cond_num' > 1e12 {
        if `verbose_flag' {
            display as error ///
                "WARNING: cond(Z'Z) = " %12.2e `cond_num' " > 1e12, unstable"
        }
        return scalar is_stable = 0
        return scalar cond_num = `cond_num'
        return scalar det_val = .
        return scalar rank_val = .
        return scalar min_eigenvalue = .
        exit
    }
    
    if `cond_num' > 1e8 & `verbose_flag' {
        display as text ///
            "  Note: cond(Z'Z) = " %12.2e `cond_num' ///
            " > 1e8, moderate ill-conditioning"
    }
    
    // -----------------------------------------------------------------------
    // Check 2: Determinant
    // -----------------------------------------------------------------------
    mata: st_numscalar("r(det_val)", det(st_matrix("`ZtZ_sym'")))
    local det_val = r(det_val)
    
    if abs(`det_val') < `tolerance' {
        if `verbose_flag' {
            display as error ///
                "WARNING: det(Z'Z) = " %12.2e `det_val' ///
                " < " %12.2e `tolerance' ", near-singular"
        }
        return scalar is_stable = 0
        return scalar cond_num = `cond_num'
        return scalar det_val = `det_val'
        return scalar rank_val = .
        return scalar min_eigenvalue = .
        exit
    }
    
    // -----------------------------------------------------------------------
    // Check 3: Rank
    // -----------------------------------------------------------------------
    mata: st_numscalar("r(rank_val)", rank(st_matrix("`ZtZ_sym'")))
    local rank_val = r(rank_val)
    
    if `rank_val' < `k' {
        if `verbose_flag' {
            display as error ///
                "WARNING: rank(Z'Z) = " `rank_val' " < " `k' ", rank deficient"
        }
        return scalar is_stable = 0
        return scalar cond_num = `cond_num'
        return scalar det_val = `det_val'
        return scalar rank_val = `rank_val'
        return scalar min_eigenvalue = .
        exit
    }
    
    // -----------------------------------------------------------------------
    // Compute W = (Z'Z)^{-1} / N
    // -----------------------------------------------------------------------
    mata: st_matrix("`W_result'", invsym(st_matrix("`ZtZ_sym'")) / `n')
    
    // Force W symmetry
    mata: st_matrix("`W_result'", ///
        (st_matrix("`W_result'") + st_matrix("`W_result'")') / 2)
    
    // -----------------------------------------------------------------------
    // Check 4: Positive definiteness, Ridge fix if needed
    // -----------------------------------------------------------------------
    mata: st_numscalar("r(min_ev)", ///
        min(symeigenvalues(st_matrix("`W_result'"))))
    local min_ev = r(min_ev)
    
    if `min_ev' <= 0 {
        // Ridge adjustment: W = W + delta * I
        local ridge_delta = abs(`min_ev') + 1e-10
        mata: st_matrix("`W_result'", ///
            st_matrix("`W_result'") + `ridge_delta' * I(`k'))
        if `verbose_flag' {
            display as text ///
                "  Note: W not PD (min_eval=" %12.2e `min_ev' ///
                "), Ridge delta=" %12.2e `ridge_delta'
        }
    }
    
    // Store W result into the caller's matrix
    matrix `wmat' = `W_result'
    
    // -----------------------------------------------------------------------
    // Return results
    // -----------------------------------------------------------------------
    return scalar is_stable = 1
    return scalar cond_num = `cond_num'
    return scalar det_val = `det_val'
    return scalar rank_val = `rank_val'
    return scalar min_eigenvalue = `min_ev'
    
    if `verbose_flag' {
        display as text "  Matrix stability check: PASSED"
        display as text "    cond(Z'Z) = " %12.2e `cond_num'
        display as text "    det(Z'Z)  = " %12.2e `det_val'
        display as text "    rank(Z'Z) = " `rank_val' " (expected " `k' ")"
        display as text "    min(eig(W)) = " %12.2e `min_ev'
    }
end
