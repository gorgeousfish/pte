*! _pte_verify_ereturn_complete.ado
*! e() return value completeness check

version 14.0
capture program drop _pte_verify_ereturn_complete
program define _pte_verify_ereturn_complete, rclass
    version 14.0
    syntax [, verbose stage(string)]
    
    // Default: check all stages
    if "`stage'" == "" local stage "all"
    
    local n_checks = 0
    local n_pass = 0
    local n_fail = 0
    local missing_items ""
    
    // ---------------------------------------------------------------
    // required e() returns (production function estimation)
    // ---------------------------------------------------------------
    if inlist("`stage'", "all", "e1", "prodfunc") {
        // Scalars
        foreach s in N converged omegapoly {
            local ++n_checks
            capture {
                assert e(`s') != .
            }
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(`s') exists"
            }
            else {
                local ++n_fail
                local missing_items "`missing_items' e(`s')"
                if "`verbose'" != "" di as error "  [FAIL] e(`s') missing"
            }
        }
        
        // Matrices
        foreach m in b {
            local ++n_checks
            capture confirm matrix e(`m')
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(`m') matrix exists"
            }
            else {
                local ++n_fail
                local missing_items "`missing_items' e(`m')"
                if "`verbose'" != "" di as error "  [FAIL] e(`m') matrix missing"
            }
        }
        
        // Production-function type is published as e(prodfunc) by the live
        // E1 producer, with e(pfunc) retained only as a compatibility alias
        // on some higher-level wrappers.
        local ++n_checks
        local _pte_pf_type "`e(prodfunc)'"
        local _pte_pf_key "e(prodfunc)"
        if "`_pte_pf_type'" == "" {
            local _pte_pf_type "`e(pfunc)'"
            local _pte_pf_key "e(pfunc)"
        }
        if "`_pte_pf_type'" != "" {
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] `_pte_pf_key' = `_pte_pf_type'"
        }
        else {
            local ++n_fail
            local missing_items "`missing_items' e(prodfunc)|e(pfunc)"
            if "`verbose'" != "" di as error "  [FAIL] e(prodfunc)|e(pfunc) missing"
        }
    }
    
    // ---------------------------------------------------------------
    // required e() returns (omega recovery & evolution)
    // ---------------------------------------------------------------
    if inlist("`stage'", "all", "e2", "omega") {
        foreach s in sigma_eps sigma_eps_trim {
            local ++n_checks
            capture {
                assert e(`s') != .
            }
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(`s') exists"
            }
            else {
                local ++n_fail
                local missing_items "`missing_items' e(`s')"
                if "`verbose'" != "" di as error "  [FAIL] e(`s') missing"
            }
        }
        
        foreach m in rho_0 {
            local ++n_checks
            capture confirm matrix e(`m')
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(`m') matrix exists"
            }
            else {
                local ++n_fail
                local missing_items "`missing_items' e(`m')"
                if "`verbose'" != "" di as error "  [FAIL] e(`m') matrix missing"
            }
        }
    }
    
    // ---------------------------------------------------------------
    // required e() returns (ATT estimation & inference)
    // ---------------------------------------------------------------
    if inlist("`stage'", "all", "e3", "att") {
        local ++n_checks
        capture confirm matrix e(att)
        if _rc == 0 {
            local ++n_pass
            if "`verbose'" != "" di as result "  [PASS] e(att) matrix exists"
        }
        else {
            capture {
                assert e(att) != .
            }
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(att) scalar exists"
            }
            else {
                local ++n_fail
                local missing_items "`missing_items' e(att)"
                if "`verbose'" != "" di as error "  [FAIL] e(att) missing"
            }
        }

        foreach m in att_se {
            local ++n_checks
            capture confirm matrix e(`m')
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(`m') matrix exists"
            }
            else {
                local ++n_fail
                local missing_items "`missing_items' e(`m')"
                if "`verbose'" != "" di as error "  [FAIL] e(`m') matrix missing"
            }
        }
        
        local has_boot_count = 0
        local boot_reps = 0
        foreach s in nboot bootstrap breps {
            capture {
                assert e(`s') != .
            }
            if _rc == 0 {
                local has_boot_count = 1
                local boot_reps = e(`s')
                continue, break
            }
        }

        if `has_boot_count' & `boot_reps' > 0 {
            foreach m in att_ci_lower att_ci_upper {
                local ++n_checks
                capture confirm matrix e(`m')
                if _rc == 0 {
                    local ++n_pass
                    if "`verbose'" != "" di as result "  [PASS] e(`m') matrix exists"
                }
                else {
                    local ++n_fail
                    local missing_items "`missing_items' e(`m')"
                    if "`verbose'" != "" di as error "  [FAIL] e(`m') matrix missing"
                }
            }
        }
        
        foreach s in nsim {
            local ++n_checks
            capture {
                assert e(`s') != .
            }
            if _rc == 0 {
                local ++n_pass
                if "`verbose'" != "" di as result "  [PASS] e(`s') exists"
            }
            else {
                local ++n_fail
                local missing_items "`missing_items' e(`s')"
                if "`verbose'" != "" di as error "  [FAIL] e(`s') missing"
            }
        }
    }
    
    // Summary
    di as text ""
    if `n_fail' == 0 {
        di as result "e() completeness (`stage'): `n_pass'/`n_checks' PASSED"
    }
    else {
        di as error "e() completeness (`stage'): `n_pass'/`n_checks' passed, `n_fail' FAILED"
        di as error "  Missing:`missing_items'"
    }
    
    return scalar n_checks = `n_checks'
    return scalar n_pass = `n_pass'
    return scalar n_fail = `n_fail'
    return local missing_items "`missing_items'"
end
