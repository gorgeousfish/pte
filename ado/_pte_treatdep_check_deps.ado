*! _pte_treatdep_check_deps.ado
*! Dependency Check for treatdependent

version 14.0
capture program drop _pte_treatdep_check_deps
program define _pte_treatdep_check_deps, rclass
    version 14.0  // minimum for Mata optimize(); see AGENTS.md Stata code standards
    
    syntax [, DETAIL]
    
    // ================================================================
    // Initialize local variables
    // ================================================================
    
    local prodest_found = 0
    local endopoly_found = 0
    local patch_ready = 0
    local stata_version_ok = 0
    local all_passed = 0
    local stata_ver = c(stata_version)
    
    // ================================================================
    // Check if _pte_error is available (graceful degradation)
    // ================================================================
    
    local has_pte_error = 0
    capture which _pte_error
    if _rc == 0 {
        local has_pte_error = 1
    }
    
    // ================================================================
    // Detail mode header
    // ================================================================
    
    if "`detail'" != "" {
        di as text ""
        di as text "{hline 64}"
        di as text "Dependency Check for treatdependent"
        di as text "{hline 64}"
        di as text ""
    }
    
    // ================================================================
    // Check 1: prodest base package (advisory)
    // Detect whether prodest is installed via SSC. Treatdependent can still
    // proceed when the official endopolyprodest source is already loaded into
    // the current session, so this is informational rather than a hard gate.
    // ================================================================
    
    capture which prodest
    if _rc == 0 {
        local prodest_found = 1
        if "`detail'" != "" {
            di as text "Check 1: prodest base package ................ " as result "PASS" as text " (found)"
        }
    }
    else {
        local prodest_found = 0
        if "`detail'" != "" {
            di as text "Check 1: prodest base package ................ " as text "INFO" as text " (not found; advisory only)"
        }
    }

    // ================================================================
    // Check 2: endopolyprodest command
    // Detect endopolyprodest availability: either permanently installed
    // or loaded into the current session via run treatpolyprodest.ado.
    // ================================================================
    
    local endopoly_permanent = 0
    local endopoly_session = 0
    
    // 2a: Check permanent installation
    capture which endopolyprodest
    if _rc == 0 {
        local endopoly_permanent = 1
        local endopoly_found = 1
    }
    
    // 2b: Check session-defined (fallback)
    if `endopoly_permanent' == 0 {
        capture program list endopolyprodest
        if _rc == 0 {
            local endopoly_session = 1
            local endopoly_found = 1
        }
    }
    
    // Display result
    if "`detail'" != "" {
        if `endopoly_permanent' == 1 {
            di as text "Check 2: endopolyprodest command ............. " as result "PASS" as text " (permanently installed)"
        }
        else if `endopoly_session' == 1 {
            di as text "Check 2: endopolyprodest command ............. " as result "PASS" as text " (session-defined)"
            di as text "         Note: Consider permanent installation for reliability"
        }
        else {
            di as text "Check 2: endopolyprodest command ............. " as error "FAIL" as text " (not found)"
        }
    }
    
    // Handle missing endopolyprodest
    if `endopoly_found' == 0 {
        // Set partial return values before exit
        return scalar prodest_found = `prodest_found'
        return scalar endopolyprodest_found = 0
        return scalar treatdep_patch_ready = 0
        return scalar stata_version = `stata_ver'
        return scalar stata_version_ok = .
        return scalar all_checks_passed = 0
        
        if `has_pte_error' {
            _pte_error, errcode(199) ///
                msg("endopolyprodest command not found") ///
                suggestion("Load with: run treatpolyprodest.ado")
        }
        else {
            di as error "Error: endopolyprodest command not found"
            di as error "Load with: run treatpolyprodest.ado"
            if `prodest_found' == 0 {
                di as text "Note: prodest is also not installed, but it is not required once endopolyprodest is loaded."
            }
            exit 199
        }
    }

    // ================================================================
    // Check 3: Materialize the runnable treatdependent contract
    // Cold installed ado files can be visible on adopath before their Mata
    // companions are source-loaded. Prepare the upstream contract first, then
    // apply the package-owned patch, so the gate matches actual executability.
    // ================================================================

    quietly _pte_treatdep_prepare_runtime
    local patch_ready = r(patch_ready)
    local patch_file `"`r(patch_file)'"'
    local patch_rc = r(patch_rc)
    local source_loaded = r(source_loaded)
    local source_file `"`r(source_file)'"'
    local source_rc = r(source_rc)

    if "`detail'" != "" {
        if `patch_ready' == 1 {
            di as text "Check 3: treatdependent Mata patch ........... " as result "PASS" as text " (loaded)"
            if `source_loaded' == 1 & `"`source_file'"' != "" {
                di as text "         Upstream source-loaded from ......... " as result `"`source_file'"'
            }
        }
        else if `"`patch_file'"' == "" {
            di as text "Check 3: treatdependent Mata patch ........... " as error "FAIL" as text " (not found)"
        }
        else {
            di as text "Check 3: treatdependent Mata patch ........... " as error "FAIL" as text " (rc = `patch_rc')"
        }
    }

    if `patch_ready' != 1 {
        return scalar prodest_found = `prodest_found'
        return scalar endopolyprodest_found = `endopoly_found'
        return scalar treatdep_patch_ready = 0
        return scalar stata_version = `stata_ver'
        return scalar stata_version_ok = .
        return scalar all_checks_passed = 0

        if `has_pte_error' {
            _pte_error, errcode(601) ///
                msg("treatdependent Mata compatibility patch failed to load") ///
                suggestion("Verify that _pte_mata_endopoly_patch.do is on adopath and loadable")
        }
        else {
            di as error "Error: treatdependent Mata compatibility patch failed to load"
            if `"`patch_file'"' == "" {
                di as error "Expected file: _pte_mata_endopoly_patch.do"
            }
            else {
                di as error "Patch file: `patch_file'"
                if !missing(`patch_rc') {
                    di as error "Return code: `patch_rc'"
                }
            }
            if `"`source_file'"' != "" & !missing(`source_rc') {
                di as error "Upstream source rc: `source_rc'"
            }
            exit 601
        }
    }

    local contract_ready = 0
    capture local contract_ready = r(ready)
    if missing(`contract_ready') local contract_ready = 0
    local missing_contract = `"`r(missing)'"'
    if `contract_ready' == 0 & `"`missing_contract'"' == "" {
        local missing_contract "(not returned)"
    }

    if "`detail'" != "" {
        if `contract_ready' == 1 {
            di as text "Check 4: companion Mata objects .............. " as result "PASS" as text " (facf1/facf2/facf3/opt_mata)"
        }
        else {
            di as text "Check 4: companion Mata objects .............. " as error "FAIL" as text " (missing: `missing_contract')"
        }
    }

    if `contract_ready' != 1 {
        return scalar prodest_found = `prodest_found'
        return scalar endopolyprodest_found = `endopoly_found'
        return scalar treatdep_patch_ready = `patch_ready'
        return scalar stata_version = `stata_ver'
        return scalar stata_version_ok = .
        return scalar all_checks_passed = 0

        if `has_pte_error' {
            _pte_error, errcode(601) ///
                msg("treatdependent companion Mata objects are missing") ///
                suggestion("Load treatpolyprodest.ado so facf1()/facf2() are available before PTE patches facf3()/opt_mata()")
        }
        else {
            di as error "Error: treatdependent companion Mata objects are missing"
            di as error "Missing: `missing_contract'"
            di as error "Load treatpolyprodest.ado so facf1()/facf2() are available before applying the PTE patch."
            exit 601
        }
    }

    // ================================================================
    // Check 5: Stata version >= 14.0
    // Mata optimization functions used in the treatdependent stack require 14.0+
    // ================================================================
    
    if `stata_ver' >= 14.0 {
        local stata_version_ok = 1
        if "`detail'" != "" {
            di as text "Check 5: Stata version >= 14.0 ............... " as result "PASS" as text " (version `stata_ver')"
        }
    }
    else {
        local stata_version_ok = 0
        if "`detail'" != "" {
            di as text "Check 5: Stata version >= 14.0 ............... " as error "FAIL" as text " (version `stata_ver')"
        }
        
        // Set partial return values before exit
        return scalar prodest_found = `prodest_found'
        return scalar endopolyprodest_found = `endopoly_found'
        return scalar treatdep_patch_ready = `patch_ready'
        return scalar stata_version = `stata_ver'
        return scalar stata_version_ok = 0
        return scalar all_checks_passed = 0
        
        if `has_pte_error' {
            // E-009: Stata version below minimum requirement
            _pte_error, errcode(9) ///
                msg("Stata version too old for treatdependent (requires 14.0+, current: `stata_ver')") ///
                suggestion("Upgrade Stata to 14.0+ or use standard pte without treatdependent")
        }
        else {
            // E-009: Stata version below minimum requirement
            di as error "Error: Stata version too old for treatdependent"
            di as error "Requires Stata 14.0+, current version: `stata_ver'"
            di as error "Upgrade Stata or use standard pte without treatdependent"
            exit 9
        }
    }
    
    // ================================================================
    // All checks passed
    // ================================================================
    
    local all_passed = (`endopoly_found' == 1) & (`patch_ready' == 1) & ///
        (`contract_ready' == 1) & (`stata_version_ok' == 1)
    
    if "`detail'" != "" {
        di as text ""
        if `all_passed' {
            di as result "All dependency checks PASSED"
        }
        else {
            di as error "Some dependency checks FAILED"
        }
        if `prodest_found' == 0 & `all_passed' {
            di as text "Note: prodest is absent; continuing because endopolyprodest is available."
        }
        di as text "{hline 64}"
        di as text ""
    }
    
    // ================================================================
    // Set return values
    // ================================================================
    
    return scalar prodest_found = `prodest_found'
    return scalar endopolyprodest_found = `endopoly_found'
    return scalar treatdep_patch_ready = `patch_ready'
    return scalar treatdep_contract_ready = `contract_ready'
    return scalar stata_version = `stata_ver'
    return scalar stata_version_ok = `stata_version_ok'
    return scalar all_checks_passed = `all_passed'
    
end
