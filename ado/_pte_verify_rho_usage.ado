*! _pte_verify_rho_usage.ado
*! Validates that counterfactual simulation uses ONLY rho coefficients
*! from e(rho_0), not gamma/delta treatment interaction terms.
*! Key principle (Assumption 4.1):
*! Counterfactual path uses h_bar_0 (untreated evolution) only:
*! omega_0 = rho_0 + rho_1*omega + rho_2*omega^2 + ... + eps0
*! No gamma or delta terms allowed.

version 14.0
capture program drop _pte_verify_rho_usage
program define _pte_verify_rho_usage, rclass
    version 14.0
    syntax [, VERBOSE STRICT]
    
    // Initialize counters
    local n_checks = 0
    local n_passed = 0
    local n_failed = 0
    local errors ""
    
    // ================================================================
    // Check 1: e(rho_0) existence
    // ================================================================
    local ++n_checks
    capture confirm matrix e(rho_0)
    if _rc != 0 {
        local ++n_failed
        local errors "`errors' [e(rho_0) not found]"
        if "`verbose'" != "" {
            di as error "  x Check 1 FAILED: e(rho_0) matrix not found"
        }
        // Cannot proceed without rho_0
        if "`strict'" != "" {
            di as error "[pte] Error: e(rho_0) not found. " ///
                "Run _pte_evolution first."
            exit 198
        }
        // Return early — remaining checks need rho_0
        return scalar verified = 0
        return scalar n_checks = `n_checks'
        return scalar n_passed = `n_passed'
        return scalar n_failed = `n_failed'
        return local errors "`errors'"
        exit
    }
    else {
        local ++n_passed
        if "`verbose'" != "" {
            di as text "  v Check 1 PASSED: e(rho_0) exists"
        }
    }
    
    // ================================================================
    // Check 2: e(omegapoly) existence
    // ================================================================
    local ++n_checks
    capture local p = e(omegapoly)
    if _rc != 0 | missing(`p') {
        local ++n_failed
        local errors "`errors' [e(omegapoly) not found]"
        if "`verbose'" != "" {
            di as error "  x Check 2 FAILED: e(omegapoly) not found"
        }
        if "`strict'" != "" {
            di as error "[pte] Error: e(omegapoly) not found."
            exit 198
        }
        return scalar verified = 0
        return scalar n_checks = `n_checks'
        return scalar n_passed = `n_passed'
        return scalar n_failed = `n_failed'
        return local errors "`errors'"
        exit
    }
    else {
        local ++n_passed
        if "`verbose'" != "" {
            di as text "  v Check 2 PASSED: e(omegapoly) = `p'"
        }
    }
    
    // ================================================================
    // Check 3: e(rho_0) dimension — colsof == omegapoly + 1
    // ================================================================
    local ++n_checks
    tempname Rho_0
    matrix `Rho_0' = e(rho_0)
    local expected_cols = `p' + 1
    local actual_cols = colsof(`Rho_0')
    local actual_rows = rowsof(`Rho_0')
    
    if `actual_cols' != `expected_cols' {
        local ++n_failed
        local errors "`errors' [dimension mismatch: cols=`actual_cols' expected=`expected_cols']"
        if "`verbose'" != "" {
            di as error "  x Check 3 FAILED: colsof(e(rho_0)) = `actual_cols', " ///
                "expected `expected_cols'"
        }
    }
    else if `actual_rows' != 1 {
        local ++n_failed
        local errors "`errors' [row mismatch: rows=`actual_rows' expected=1]"
        if "`verbose'" != "" {
            di as error "  x Check 3 FAILED: rowsof(e(rho_0)) = `actual_rows', " ///
                "expected 1"
        }
    }
    else {
        local ++n_passed
        if "`verbose'" != "" {
            di as text "  v Check 3 PASSED: dimension " ///
                "`actual_rows' x `actual_cols' (1 x `expected_cols')"
        }
    }
    
    // ================================================================
    // Check 4: Column names do not contain "gamma"
    // ================================================================
    local ++n_checks
    local colnames : colnames `Rho_0'
    if strpos("`colnames'", "gamma") != 0 {
        local ++n_failed
        local errors "`errors' [gamma in colnames]"
        if "`verbose'" != "" {
            di as error "  x Check 4 FAILED: 'gamma' found in e(rho_0) colnames"
            di as error "    colnames: `colnames'"
        }
    }
    else {
        local ++n_passed
        if "`verbose'" != "" {
            di as text "  v Check 4 PASSED: no 'gamma' in colnames"
        }
    }
    
    // ================================================================
    // Check 5: Column names do not contain "delta"
    // ================================================================
    local ++n_checks
    if strpos("`colnames'", "delta") != 0 {
        local ++n_failed
        local errors "`errors' [delta in colnames]"
        if "`verbose'" != "" {
            di as error "  x Check 5 FAILED: 'delta' found in e(rho_0) colnames"
            di as error "    colnames: `colnames'"
        }
    }
    else {
        local ++n_passed
        if "`verbose'" != "" {
            di as text "  v Check 5 PASSED: no 'delta' in colnames"
        }
    }
    
    // ================================================================
    // Check 6: e(rho_0) matches first p+1 columns of e(rho)
    // ================================================================
    local ++n_checks
    capture confirm matrix e(rho)
    if _rc == 0 {
        tempname Rho
        matrix `Rho' = e(rho)
        local rho_cols = colsof(`Rho')
        
        // e(rho) should have 2*(p+1) columns (rho + gamma/delta)
        local match = 1
        if `rho_cols' >= `expected_cols' {
            forvalues j = 1/`expected_cols' {
                if abs(`Rho_0'[1,`j'] - `Rho'[1,`j']) > 1e-10 {
                    local match = 0
                }
            }
        }
        else {
            local match = 0
        }
        
        if `match' == 0 {
            local ++n_failed
            local errors "`errors' [rho_0 vs rho mismatch]"
            if "`verbose'" != "" {
                di as error "  x Check 6 FAILED: e(rho_0) != e(rho)[1, 1..`expected_cols']"
            }
        }
        else {
            local ++n_passed
            if "`verbose'" != "" {
                di as text "  v Check 6 PASSED: e(rho_0) matches e(rho) first `expected_cols' cols"
            }
        }
    }
    else {
        // e(rho) not available — skip this check
        local ++n_passed
        if "`verbose'" != "" {
            di as text "  v Check 6 SKIPPED: e(rho) not available"
        }
    }
    
    // ================================================================
    // Summary
    // ================================================================
    local verified = (`n_failed' == 0)
    
    if "`verbose'" != "" {
        di as text ""
        di as text "{hline 50}"
        di as text "Rho Coefficient Usage Validation Summary"
        di as text "{hline 50}"
        di as text "  Total checks:  `n_checks'"
        di as text "  Passed:        `n_passed'"
        di as text "  Failed:        `n_failed'"
        if `verified' {
            di as text "  Result:        VERIFIED"
        }
        else {
            di as error "  Result:        FAILED"
            di as error "  Errors:       `errors'"
        }
        di as text "{hline 50}"
    }
    
    // STRICT mode: exit on failure
    if "`strict'" != "" & `verified' == 0 {
        di as error "[pte] Error: rho coefficient usage verification failed"
        di as error "[pte] Counterfactual simulation may use incorrect coefficients"
        di as error "[pte] Errors:`errors'"
        exit 198
    }
    
    // Return values
    return scalar verified = `verified'
    return scalar n_checks = `n_checks'
    return scalar n_passed = `n_passed'
    return scalar n_failed = `n_failed'
    return local errors "`errors'"
end
