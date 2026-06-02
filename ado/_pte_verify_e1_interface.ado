*! _pte_verify_e1_interface.ado

version 14.0
capture program drop _pte_verify_e1_interface
program define _pte_verify_e1_interface, rclass
    version 14.0
    syntax [, verbose]
    
    local n_checks = 0
    local n_pass = 0
    local n_fail = 0
    
    // 1. _pte_phi variable exists
    local ++n_checks
    capture confirm variable _pte_phi
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] _pte_phi exists"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] _pte_phi variable not found"
    }
    
    // 2. _pte_phi has non-missing values
    local ++n_checks
    capture {
        quietly count if !missing(_pte_phi)
        assert r(N) > 0
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] _pte_phi has non-missing values"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] _pte_phi is all missing"
    }
    
    // 3. e(b) matrix exists
    local ++n_checks
    capture confirm matrix e(b)
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] e(b) matrix exists"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] e(b) matrix not found"
    }
    
    // 4. e(b) dimension correct for pfunc
    local ++n_checks
    capture {
        local pfunc "`e(pfunc)'"
        if "`pfunc'" == "cd" {
            assert colsof(e(b)) >= 2
        }
        else if "`pfunc'" == "translog" {
            assert colsof(e(b)) >= 5
        }
        else {
            assert colsof(e(b)) >= 2
        }
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] e(b) dimension correct"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] e(b) dimension incorrect for pfunc=`pfunc'"
    }
    
    // 5. _pte_mid variable exists
    local ++n_checks
    capture confirm variable _pte_mid, exact
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] _pte_mid exists"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] _pte_mid variable not found"
    }
    
    // 6. _pte_mid takes only valid values (0, 1, .)
    local ++n_checks
    capture {
        quietly count if !inlist(_pte_mid, 0, 1, .)
        assert r(N) == 0
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] _pte_mid values valid (0/1/.)"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] _pte_mid has invalid values"
    }
    
    // 7. e(pfunc) is valid
    local ++n_checks
    capture {
        local pfunc "`e(pfunc)'"
        assert inlist("`pfunc'", "cd", "translog")
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] e(pfunc) = `pfunc'"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] e(pfunc) invalid or missing"
    }
    
    // 8. e(omegapoly) is valid (1, 2, 3, or 4)
    local ++n_checks
    capture {
        assert inlist(e(omegapoly), 1, 2, 3, 4)
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] e(omegapoly) = `=e(omegapoly)'"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] e(omegapoly) invalid"
    }
    
    // 9. e(converged) exists
    local ++n_checks
    capture {
        assert e(converged) != .
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] e(converged) exists"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] e(converged) missing"
    }
    
    // 10. beta values are in reasonable range
    local ++n_checks
    capture {
        // For production function: beta_l in (-5, 5), beta_k in (-5, 5)
        local bl = e(b)[1,1]
        local bk = e(b)[1,2]
        assert `bl' > -5 & `bl' < 5
        assert `bk' > -5 & `bk' < 5
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] beta values in reasonable range"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] beta values out of reasonable range"
    }
    
    // Summary
    di as text ""
    if `n_fail' == 0 {
        di as result "Production function interface: `n_pass'/`n_checks' checks PASSED"
    }
    else {
        di as error "Production function interface: `n_pass'/`n_checks' passed, `n_fail' FAILED"
    }
    
    return scalar n_checks = `n_checks'
    return scalar n_pass = `n_pass'
    return scalar n_fail = `n_fail'
end
