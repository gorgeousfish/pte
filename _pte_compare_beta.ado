*! _pte_compare_beta.ado
*! Compare beta parameters with replication code

version 14.0
capture program drop _pte_compare_beta
program define _pte_compare_beta
    version 14.0
    syntax, repl_beta_l(real) repl_beta_k(real) ///
        [repl_beta_ll(real 0) repl_beta_kk(real 0) repl_beta_lk(real 0) ///
         tol(real 1e-4) pfunc(string)]
    
    // Default pfunc from the live estimation metadata.
    // The package publishes normalized e(prodfunc), while some older callers
    // still retain the legacy e(pfunc) alias.
    if "`pfunc'" == "" {
        local pfunc "`e(prodfunc)'"
        if "`pfunc'" == "" {
            local pfunc "`e(pfunc)'"
        }
        if "`pfunc'" == "" {
            di as error "[_pte_compare_beta] No pfunc specified and neither e(prodfunc) nor e(pfunc) found"
            exit 198
        }
    }
    
    // Verify e(b) exists
    capture confirm matrix e(b)
    if _rc {
        di as error "[_pte_compare_beta] e(b) matrix not found"
        exit 301
    }
    
    di as text "{hline 60}"
    di as text "Beta Parameter Comparison (pfunc=`pfunc', tol=`tol')"
    di as text "{hline 60}"
    
    // Compare beta_l (free variable coefficient)
    local pte_beta_l = e(b)[1, 1]
    _pte_assert_numeric, actual(`pte_beta_l') expected(`repl_beta_l') ///
        tol(`tol') msg("beta_l")
    
    // Compare beta_k (state variable coefficient)
    local pte_beta_k = e(b)[1, 2]
    _pte_assert_numeric, actual(`pte_beta_k') expected(`repl_beta_k') ///
        tol(`tol') msg("beta_k")
    
    // Translog: additional parameters
    if "`pfunc'" == "translog" {
        local ncols = colsof(e(b))
        if `ncols' < 5 {
            di as error "[_pte_compare_beta] Translog requires 5 beta params, got `ncols'"
            exit 503
        }
        
        local pte_beta_ll = e(b)[1, 3]
        _pte_assert_numeric, actual(`pte_beta_ll') expected(`repl_beta_ll') ///
            tol(`tol') msg("beta_ll")
        
        local pte_beta_kk = e(b)[1, 4]
        _pte_assert_numeric, actual(`pte_beta_kk') expected(`repl_beta_kk') ///
            tol(`tol') msg("beta_kk")
        
        local pte_beta_lk = e(b)[1, 5]
        _pte_assert_numeric, actual(`pte_beta_lk') expected(`repl_beta_lk') ///
            tol(`tol') msg("beta_lk")
    }
    
    di as text "{hline 60}"
    di as result ">>> Beta parameters match within tolerance"
end
