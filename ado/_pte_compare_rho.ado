*! _pte_compare_rho.ado
*! Compare rho coefficients with replication code

version 14.0
capture program drop _pte_compare_rho
program define _pte_compare_rho
    version 14.0
    syntax, repl_rho(numlist) [tol(real 1e-4)]
    
    // Verify e(rho_0) exists
    capture confirm matrix e(rho_0)
    if _rc {
        di as error "[_pte_compare_rho] e(rho_0) matrix not found"
        exit 301
    }
    
    di as text "{hline 60}"
    di as text "Rho Coefficient Comparison (tol=`tol')"
    di as text "{hline 60}"
    
    // Count expected coefficients
    local n_repl : word count `repl_rho'
    local n_pte  = colsof(e(rho_0))
    
    if `n_repl' != `n_pte' {
        di as error "[_pte_compare_rho] Dimension mismatch: repl=`n_repl' pte=`n_pte'"
        exit 503
    }
    
    // Compare each rho coefficient
    local j = 1
    foreach r of local repl_rho {
        local pte_rho = e(rho_0)[1, `j']
        local idx = `j' - 1
        _pte_assert_numeric, actual(`pte_rho') expected(`r') ///
            tol(`tol') msg("rho_`idx'")
        local ++j
    }
    
    di as text "{hline 60}"
    di as result ">>> Rho coefficients match within tolerance"
end
