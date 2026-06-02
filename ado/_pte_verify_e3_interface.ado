*! _pte_verify_e3_interface.ado
*! Fix: Bug 19 [Confirmed-20260311-VERIFY-E3-CONTRACT]
*! - Auto-detect bootstrap vs non-bootstrap result paths
*! - Non-bootstrap: check matrix e(att), matrix e(att_se), scalar e(ATT_avg)
*! - Bootstrap: check matrix e(att_se), matrix e(att_ci_lower/upper), scalar e(bootstrap)
*! - Fix false-pass on missing objects (att_se positive, nboot)

version 14.0
capture program drop _pte_verify_e3_interface
program define _pte_verify_e3_interface, rclass
    version 14.0
    syntax [, verbose attperiods(integer -1)]
    
    local n_checks = 0
    local n_pass = 0
    local n_fail = 0
    // ================================================================
    // Step 0: Auto-detect bootstrap vs non-bootstrap result path
    // Bootstrap path: scalar e(bootstrap) > 0 AND matrix e(att_se)
    // Non-bootstrap path: matrix e(att) AND matrix e(att_se)
    // ================================================================
    local expected_cols = .
    local attperiods_conflict = 0
    local attperiods_source ""
    local _pte_has_attperiods = (`attperiods' != -1)
    local is_bootstrap = 0
    capture confirm scalar e(bootstrap)
    if _rc == 0 {
        if e(bootstrap) > 0 & !missing(e(bootstrap)) {
            local is_bootstrap = 1
        }
    }

    // Prefer the live result object's explicit event-time support when it is
    // available. Bootstrap workers may only expose the horizon as a scalar
    // maximum, so accept that fallback only on bootstrap results.
    capture confirm matrix e(attperiods)
    if _rc == 0 {
        local expected_cols = colsof(e(attperiods)) + 1
        local attperiods_from_matrix = colsof(e(attperiods)) - 1
        local attperiods_source "e(attperiods)"
        if `_pte_has_attperiods' & `attperiods' != `attperiods_from_matrix' {
            local attperiods_conflict = 1
        }
    }
    else if `_pte_has_attperiods' {
        local expected_cols = `attperiods' + 2
        local attperiods_source "attperiods()"
    }
    else if `is_bootstrap' {
        capture confirm scalar e(attperiods)
        if _rc == 0 & !missing(e(attperiods)) {
            local expected_cols = e(attperiods) + 2
            local attperiods_source "scalar e(attperiods)"
        }
    }
    
    if "`verbose'" != "" {
        if `is_bootstrap' {
            di as text "  [INFO] Detected: Bootstrap result path"
        }
        else {
            di as text "  [INFO] Detected: Non-bootstrap (point estimate) result path"
        }
    }
    
    // ================================================================
    // Check 1: e(att) matrix exists (common to both paths)
    // Non-bootstrap: matrix e(att) is the primary ATT row vector
    // Bootstrap: matrix e(att) may or may not exist; result_table_raw is primary
    // ================================================================
    local ++n_checks
    if `is_bootstrap' {
        // In bootstrap path, either matrix e(att) or matrix e(result_table_raw) should exist
        capture confirm matrix e(att)
        local _has_att_mat = (_rc == 0)
        capture confirm matrix e(result_table_raw)
        local _has_rtab = (_rc == 0)
        if `_has_att_mat' | `_has_rtab' {
            local ++n_pass
            if "`verbose'" != "" {
                if `_has_att_mat' {
                    di as result "  [PASS] e(att) matrix exists (bootstrap path)"
                }
                else {
                    di as result "  [PASS] e(result_table_raw) matrix exists (bootstrap path)"
                }
            }
        }
        else {
            local ++n_fail
            di as error "  [FAIL] Neither e(att) nor e(result_table_raw) found (bootstrap path)"
        }
    }
    else {
        capture confirm matrix e(att)
        if _rc == 0 {
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] e(att) matrix exists"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(att) matrix not found"
        }
    }
    
    // ================================================================
    // Check 2: e(att) dimension (non-bootstrap only)
    // Dimension = attperiods + 2 (ell=0..L + avg)
    // ================================================================
    local ++n_checks
    if !`is_bootstrap' {
        if `attperiods_conflict' {
            local ++n_fail
            di as error "  [FAIL] attperiods() conflicts with matrix e(attperiods)"
        }
        else if missing(`expected_cols') {
            local ++n_fail
            di as error "  [FAIL] cannot infer ATT support: provide attperiods() or post matrix e(attperiods)"
        }
        else {
            capture {
                assert colsof(e(att)) == `expected_cols'
            }
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(att) cols = `expected_cols' (`attperiods_source')"
            }
            else {
                local ++n_fail
                di as error "  [FAIL] e(att) dimension mismatch (expected `expected_cols')"
            }
        }
    }
    else {
        // Bootstrap path: dimension check on result_table_raw or att_se
        capture confirm matrix e(att_se)
        if _rc == 0 {
            if `attperiods_conflict' {
                local ++n_fail
                di as error "  [FAIL] attperiods() conflicts with matrix e(attperiods)"
            }
            else if missing(`expected_cols') {
                local ++n_fail
                di as error "  [FAIL] cannot infer ATT support: provide attperiods() or post matrix e(attperiods)"
            }
            else {
                capture {
                    assert colsof(e(att_se)) == `expected_cols'
                }
                if _rc == 0 {
                    local ++n_pass
                    if "`verbose'" != "" di as result "  [PASS] e(att_se) cols = `expected_cols' (bootstrap, `attperiods_source')"
                }
                else {
                    local ++n_fail
                    di as error "  [FAIL] e(att_se) dimension mismatch (expected `expected_cols', bootstrap)"
                }
            }
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(att_se) matrix not found (bootstrap path)"
        }
    }
    
    // ================================================================
    // Check 3: SE information exists (path-dependent)
    // Both paths publish dynamic SE in matrix e(att_se)
    // Non-bootstrap may also publish scalar e(att_se_overall)
    // ================================================================
    local ++n_checks
    local _se_exists = 0
    if `is_bootstrap' {
        capture confirm matrix e(att_se)
        if _rc == 0 {
            local _se_exists = 1
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] e(att_se) matrix exists (bootstrap)"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(att_se) matrix not found (expected for bootstrap)"
        }
    }
    else {
        capture confirm matrix e(att_se)
        if _rc == 0 {
            local _se_exists = 1
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] e(att_se) matrix exists (non-bootstrap)"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(att_se) matrix not found (non-bootstrap)"
        }
    }
    
    // ================================================================
    // Check 4: SE values are nonnegative (only if SE object exists)
    // Guard: skip if prerequisite object is missing
    // ================================================================
    local ++n_checks
    if `_se_exists' {
        if `is_bootstrap' {
            // Bootstrap: legal degenerate draws imply zero SE, but negative or
            // missing SE still indicates a broken interface object.
            capture {
                mata: st_numscalar("__se_has_missing", hasmissing(st_matrix("e(att_se)")))
                mata: st_numscalar("__se_min", min(st_matrix("e(att_se)")))
                assert scalar(__se_has_missing) == 0
                assert scalar(__se_min) >= 0
            }
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(att_se) all nonnegative (bootstrap)"
            }
            else {
                local ++n_fail
                di as error "  [FAIL] e(att_se) contains missing or negative values (bootstrap)"
            }
            capture scalar drop __se_has_missing
            capture scalar drop __se_min
        }
        else {
            capture {
                mata: st_numscalar("__se_has_missing", hasmissing(st_matrix("e(att_se)")))
                mata: st_numscalar("__se_min", min(st_matrix("e(att_se)")))
                assert scalar(__se_has_missing) == 0
                assert scalar(__se_min) >= 0
            }
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(att_se) all nonnegative (non-bootstrap)"
            }
            else {
                local ++n_fail
                di as error "  [FAIL] e(att_se) contains missing or negative values (non-bootstrap)"
            }
            capture scalar drop __se_has_missing
            capture scalar drop __se_min
        }
    }
    else {
        // SE object missing: explicit SKIP, NOT a false pass
        local ++n_fail
        di as error "  [FAIL] SE check skipped: prerequisite SE object not found"
    }
    
    // ================================================================
    // Check 5: CI lower bound (bootstrap only)
    // Non-bootstrap: check att_table or att_sd exists instead
    // ================================================================
    local ++n_checks
    local _ci_lower_exists = 0
    if `is_bootstrap' {
        capture confirm matrix e(att_ci_lower)
        if _rc == 0 {
            local _ci_lower_exists = 1
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] e(att_ci_lower) exists (bootstrap)"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(att_ci_lower) not found (expected for bootstrap)"
        }
    }
    else {
        // Non-bootstrap: CI matrices are not expected
        // Check att_table instead as the primary display structure
        capture confirm matrix e(att_table)
        if _rc == 0 {
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] e(att_table) exists (non-bootstrap)"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(att_table) not found (expected for non-bootstrap)"
        }
    }
    
    // ================================================================
    // Check 6: CI upper bound (bootstrap only)
    // Non-bootstrap: check ATT_avg scalar exists
    // ================================================================
    local ++n_checks
    local _ci_upper_exists = 0
    if `is_bootstrap' {
        capture confirm matrix e(att_ci_upper)
        if _rc == 0 {
            local _ci_upper_exists = 1
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] e(att_ci_upper) exists (bootstrap)"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(att_ci_upper) not found (expected for bootstrap)"
        }
    }
    else {
        // Non-bootstrap: check scalar ATT_avg
        capture confirm scalar e(ATT_avg)
        if _rc == 0 {
            if !missing(e(ATT_avg)) {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(ATT_avg) = `=e(ATT_avg)' (non-bootstrap)"
            }
            else {
                local ++n_fail
                di as error "  [FAIL] e(ATT_avg) is missing (non-bootstrap)"
            }
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(ATT_avg) scalar not found (non-bootstrap)"
        }
    }
    
    // ================================================================
    // Check 7: CI ordering (bootstrap only) / ATT consistency (non-bootstrap)
    // Guard: only run CI ordering if both CI matrices exist
    // ================================================================
    local ++n_checks
    if `is_bootstrap' {
        if `_ci_lower_exists' & `_ci_upper_exists' {
            capture {
                mata: st_numscalar("__ci_lo_has_missing", hasmissing(st_matrix("e(att_ci_lower)")))
                mata: st_numscalar("__ci_hi_has_missing", hasmissing(st_matrix("e(att_ci_upper)")))
                mata: st_numscalar("__ci_ok", ///
                    all(st_matrix("e(att_ci_upper)") :>= st_matrix("e(att_ci_lower)")))
                assert scalar(__ci_lo_has_missing) == 0
                assert scalar(__ci_hi_has_missing) == 0
                assert scalar(__ci_ok) == 1
            }
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] CI ordering correct (lower <= upper)"
            }
            else {
                local ++n_fail
                di as error "  [FAIL] CI ordering violated or CI endpoints contain missing values"
            }
            capture scalar drop __ci_lo_has_missing
            capture scalar drop __ci_hi_has_missing
            capture scalar drop __ci_ok
        }
        else {
            // CI matrices missing: cannot check ordering
            local ++n_fail
            di as error "  [FAIL] CI ordering check skipped: CI matrices not found"
        }
    }
    else {
        capture confirm matrix e(attperiods)
        local _has_ap_matrix = (_rc == 0)
        if `_has_ap_matrix' {
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] e(attperiods) matrix exists (non-bootstrap)"
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(attperiods) matrix not found (non-bootstrap)"
        }
    }
    
    // ================================================================
    // Check 8: Bootstrap replications / Config (path-dependent)
    // Bootstrap: scalar e(bootstrap) > 0 (NOT e(nboot))
    // Non-bootstrap: scalar e(omegapoly) exists
    // Guard: must check !missing() to prevent false-pass on system missing
    // ================================================================
    local ++n_checks
    if `is_bootstrap' {
        capture confirm scalar e(bootstrap)
        if _rc == 0 {
            if e(bootstrap) > 0 & !missing(e(bootstrap)) {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(bootstrap) = `=e(bootstrap)'"
            }
            else {
                local ++n_fail
                di as error "  [FAIL] e(bootstrap) <= 0 or missing"
            }
        }
        else {
            // Try legacy name e(breps)
            capture confirm scalar e(breps)
            if _rc == 0 & !missing(e(breps)) & e(breps) > 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(breps) = `=e(breps)'"
            }
            else {
                local ++n_fail
                di as error "  [FAIL] e(bootstrap) / e(breps) not found or invalid"
            }
        }
    }
    else {
        // Non-bootstrap: check e(omegapoly) exists as config sanity
        capture confirm scalar e(omegapoly)
        if _rc == 0 {
            if !missing(e(omegapoly)) {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(omegapoly) = `=e(omegapoly)'"
            }
            else {
                local ++n_fail
                di as error "  [FAIL] e(omegapoly) is missing"
            }
        }
        else {
            local ++n_fail
            di as error "  [FAIL] e(omegapoly) not found"
        }
    }
    
    // ================================================================
    // Summary
    // ================================================================
    di as text ""
    local _path_label = cond(`is_bootstrap', "bootstrap", "non-bootstrap")
    if `n_fail' == 0 {
        di as result "ATT estimation interface (`_path_label'): `n_pass'/`n_checks' checks PASSED"
    }
    else {
        di as error "ATT estimation interface (`_path_label'): `n_pass'/`n_checks' passed, `n_fail' FAILED"
    }
    
    return scalar n_checks = `n_checks'
    return scalar n_pass = `n_pass'
    return scalar n_fail = `n_fail'
    return scalar is_bootstrap = `is_bootstrap'
end
