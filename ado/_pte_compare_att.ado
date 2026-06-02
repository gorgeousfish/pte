*! _pte_compare_att.ado
*! Compare ATT estimates with replication code

version 14.0
capture program drop _pte_compare_att
program define _pte_compare_att
    version 14.0
    syntax, repl_att(numlist) [tol(real 0.05)]
    
    // Verify e(att) exists
    capture confirm matrix e(att)
    if _rc {
        di as error "[_pte_compare_att] e(att) matrix not found"
        exit 301
    }
    
    di as text "{hline 60}"
    di as text "ATT Estimate Comparison (tol=`tol')"
    di as text "{hline 60}"
    
    // Count expected ATT values
    local n_repl : word count `repl_att'
    local n_pte  = colsof(e(att))
    
    if `n_repl' != `n_pte' {
        di as error "[_pte_compare_att] Dimension mismatch: repl=`n_repl' pte=`n_pte'"
        di as error "  (repl provides `n_repl' ATT values, pte has `n_pte' columns)"
        exit 503
    }
    
    // Compare each ATT value
    local j = 1
    foreach a of local repl_att {
        local pte_att = e(att)[1, `j']
        if `j' == `n_pte' {
            local label "ATT_avg"
        }
        else {
            local idx = `j' - 1
            local label "ATT_`idx'"
        }
        _pte_assert_numeric, actual(`pte_att') expected(`a') ///
            tol(`tol') type(absdif) msg("`label'")
        local ++j
    }
    
    // Reasonableness: ATT should be in plausible range for productivity
    // Typical ATT for productivity treatment: -2 to +2 in log points
    local att_avg = e(att)[1, `n_pte']
    if abs(`att_avg') > 5 {
        di as error "[WARNING] ATT_avg=" %6.3f `att_avg' " seems extreme (>5 log points)"
    }
    
    di as text "{hline 60}"
    di as result ">>> ATT estimates match within tolerance"
end
