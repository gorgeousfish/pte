*! _pte_compare_se.ado
*! Compare Bootstrap SE with replication code

version 14.0
capture program drop _pte_compare_se
program define _pte_compare_se
    version 14.0
    syntax, repl_se(numlist) [tol(real 0.10)]
    
    // Verify e(att_se) exists
    capture confirm matrix e(att_se)
    if _rc {
        di as error "[_pte_compare_se] e(att_se) matrix not found"
        exit 301
    }
    
    di as text "{hline 60}"
    di as text "Bootstrap SE Comparison (tol=`tol')"
    di as text "{hline 60}"
    
    // Count expected SE values
    local n_repl : word count `repl_se'
    local n_pte  = colsof(e(att_se))
    
    if `n_repl' != `n_pte' {
        di as error "[_pte_compare_se] Dimension mismatch: repl=`n_repl' pte=`n_pte'"
        exit 503
    }
    
    // Compare each SE value
    local j = 1
    foreach s of local repl_se {
        local pte_se = e(att_se)[1, `j']
        if `j' == `n_pte' {
            local label "SE_avg"
        }
        else {
            local idx = `j' - 1
            local label "SE_`idx'"
        }
        _pte_assert_numeric, actual(`pte_se') expected(`s') ///
            tol(`tol') type(absdif) msg("`label'")
        
        // Reasonableness: SE should be positive
        if `pte_se' <= 0 {
            di as error "[WARNING] `label'=" %9.6f `pte_se' " is non-positive"
        }
        local ++j
    }
    
    di as text "{hline 60}"
    di as result ">>> Bootstrap SE match within tolerance"
end
