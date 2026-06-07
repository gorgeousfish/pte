*! _pte_verify_e2_interface.ado
*! required by downstream ATT code.

version 14.0
capture program drop _pte_verify_e2_interface
program define _pte_verify_e2_interface, rclass
    version 14.0
    syntax [, verbose]
    
    local n_checks = 0
    local n_pass = 0
    local n_fail = 0
    local has_exact_omega = 0
    
    // Downstream code needs an exact numeric omega column, not an omega_*
    // shadow that Stata could reach through abbreviation matching.
    local ++n_checks
    capture confirm variable omega, exact
    if _rc == 0 {
        capture confirm numeric variable omega
        if _rc == 0 {
            local has_exact_omega = 1
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] exact numeric omega exists"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] exact omega exists but is not numeric"
        }
    }
    else {
        local ++n_fail
        di as error "  [FAIL] exact omega variable not found"
    }
    
    // A posted bridge with all-missing omega is observationally equivalent to
    // no realized productivity recovery at all.
    local ++n_checks
    if `has_exact_omega' {
        capture {
            quietly count if !missing(omega)
            assert r(N) > 0
        }
        if _rc == 0 {
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] omega has non-missing values"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] omega is all missing"
        }
    }
    else {
        local ++n_fail
        di as error "  [FAIL] omega non-missing check skipped because exact numeric omega is absent"
    }
    
    // The untreated law must be posted explicitly because ATT recursion reads
    // rho_0 rather than reconstructing it from earlier commands.
    local ++n_checks
    capture confirm matrix e(rho_0)
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] e(rho_0) matrix exists"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] e(rho_0) matrix not found"
    }
    
    // The untreated-law width must match the declared polynomial order.
    local ++n_checks
    capture {
        local p = e(omegapoly)
        assert colsof(e(rho_0)) == `p' + 1
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] e(rho_0) dimension = p+1"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] e(rho_0) dimension mismatch"
    }
    
    // The trimmed innovation scale is the canonical paper track used for ATT.
    local ++n_checks
    capture {
        assert e(sigma_eps_trim) >= 0
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] e(sigma_eps_trim) >= 0"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] e(sigma_eps_trim) missing or < 0"
    }
    
    // Keep the untrimmed scale available for raw-shock and diagnostics paths.
    local ++n_checks
    capture {
        assert e(sigma_eps) != .
    }
    if _rc == 0 {
        local ++n_pass
        if "`verbose'" != "" di as result "  [PASS] e(sigma_eps) exists"
    }
    else {
        local ++n_fail
        di as error "  [FAIL] e(sigma_eps) missing"
    }
    
    // The interface should reject only non-finite realized productivity, not
    // economically large but still valid magnitudes.
    // Extreme values can be diagnostically interesting, but the
    // interface contract should not reject otherwise valid omega objects on an
    // arbitrary magnitude threshold.
    local ++n_checks
    if `has_exact_omega' {
        capture quietly summarize omega if !missing(omega), meanonly
        if _rc == 0 & r(N) > 0 & r(min) < . & r(max) < . {
            local ++n_pass
            if "`verbose'" != "" {
                di as result "  [PASS] omega extrema are finite on the non-missing sample"
                if r(max) > 10 | r(min) < -10 {
                    di as text "  [NOTE] omega extends outside the typical [-10, 10] diagnostic range"
                }
            }
        }
        else {
            local ++n_fail
            di as error "  [FAIL] omega extrema are missing on the non-missing sample"
        }
    }
    else {
        local ++n_fail
        di as error "  [FAIL] omega extrema check skipped because exact numeric omega is absent"
    }
    
    // Summary
    di as text ""
    if `n_fail' == 0 {
        di as result "Omega recovery interface: `n_pass'/`n_checks' checks PASSED"
    }
    else {
        di as error "Omega recovery interface: `n_pass'/`n_checks' passed, `n_fail' FAILED"
    }
    
    return scalar n_checks = `n_checks'
    return scalar n_pass = `n_pass'
    return scalar n_fail = `n_fail'
end
