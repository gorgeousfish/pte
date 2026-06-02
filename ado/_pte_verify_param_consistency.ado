*! _pte_verify_param_consistency.ado
*! Cross-EPIC parameter consistency

version 14.0
capture program drop _pte_verify_param_consistency
program define _pte_verify_param_consistency, rclass
    version 14.0
    syntax, omegapoly_e1(integer) pfunc_e1(string) ///
        [omegapoly_e2(integer -1) omegapoly_e3(integer -1) verbose]
    
    local n_checks = 0
    local n_pass = 0
    local n_fail = 0
    
    // 1. omegapoly consistency: E1 vs current e()
    local ++n_checks
    capture {
        assert e(omegapoly) == `omegapoly_e1'
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] omegapoly consistent (=`omegapoly_e1')"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] omegapoly mismatch: E1=`omegapoly_e1' current=`=e(omegapoly)'"
    }
    
    // 2. pfunc consistency: E1 vs current e()
    local ++n_checks
    capture {
        assert "`e(pfunc)'" == "`pfunc_e1'"
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] pfunc consistent (=`pfunc_e1')"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] pfunc mismatch: E1=`pfunc_e1' current=`e(pfunc)'"
    }
    
    // 3. If E2 omegapoly provided, check E1 vs E2
    if `omegapoly_e2' != -1 {
        local ++n_checks
        if `omegapoly_e1' == `omegapoly_e2' {
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] omegapoly E1=E2 (=`omegapoly_e1')"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] omegapoly E1=`omegapoly_e1' != E2=`omegapoly_e2'"
        }
    }
    
    // 4. If E3 omegapoly provided, check E1 vs E3
    if `omegapoly_e3' != -1 {
        local ++n_checks
        if `omegapoly_e1' == `omegapoly_e3' {
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] omegapoly E1=E3 (=`omegapoly_e1')"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] omegapoly E1=`omegapoly_e1' != E3=`omegapoly_e3'"
        }
    }
    
    // Summary
    di as text ""
    if `n_fail' == 0 {
        di as result "Parameter consistency: `n_pass'/`n_checks' checks PASSED"
    }
    else {
        di as error "Parameter consistency: `n_pass'/`n_checks' passed, `n_fail' FAILED"
    }
    
    return scalar n_checks = `n_checks'
    return scalar n_pass = `n_pass'
    return scalar n_fail = `n_fail'
end
