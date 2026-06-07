*! _pte_compare_omega.ado
*! Compare omega statistics with replication code

version 14.0
capture program drop _pte_compare_omega
program define _pte_compare_omega
    version 14.0
    syntax, repl_mean(real) repl_sd(real) [tol(real 0.01)]
    
    // Verify _pte_omega exists
    capture confirm variable _pte_omega
    if _rc {
        di as error "[_pte_compare_omega] Variable _pte_omega not found"
        exit 111
    }
    
    di as text "{hline 60}"
    di as text "Omega Statistics Comparison (tol=`tol')"
    di as text "{hline 60}"
    
    // Compute pte omega statistics
    quietly summarize _pte_omega
    local pte_mean = r(mean)
    local pte_sd   = r(sd)
    local pte_n    = r(N)
    
    di as text "  pte:  mean=" %9.4f `pte_mean' "  sd=" %9.4f `pte_sd' "  N=`pte_n'"
    di as text "  repl: mean=" %9.4f `repl_mean' "  sd=" %9.4f `repl_sd'
    
    // Compare mean (absolute difference)
    _pte_assert_numeric, actual(`pte_mean') expected(`repl_mean') ///
        tol(`tol') type(absdif) msg("omega mean")
    
    // Compare sd (absolute difference)
    _pte_assert_numeric, actual(`pte_sd') expected(`repl_sd') ///
        tol(`tol') type(absdif) msg("omega sd")
    
    // Reasonableness check: omega should be in plausible range
    quietly summarize _pte_omega
    if r(min) < -20 | r(max) > 20 {
        di as error "[WARNING] omega range [" %6.2f r(min) ", " %6.2f r(max) ///
            "] seems extreme"
    }
    
    di as text "{hline 60}"
    di as result ">>> Omega statistics match within tolerance"
end
