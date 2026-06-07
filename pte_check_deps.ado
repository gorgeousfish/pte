*! pte_check_deps.ado
*! Public dependency checker for pte package
*! Check all required and optional dependencies

version 14.0
capture program drop pte_check_deps
program define pte_check_deps, rclass
    version 14.0  // minimum for Mata optimize(); see AGENTS.md Stata code standards
    
    syntax [, DETAIL TREATDEPENDENT COMPARE NOTRIMeps]
    
    // ================================================================
    // Initialize counters
    // ================================================================
    
    local n_checks = 0
    local n_pass = 0
    local n_fail = 0
    local n_info = 0
    local stata_ver = c(stata_version)
    
    // ================================================================
    // Header
    // ================================================================
    
    di as text ""
    di as text "{hline 64}"
    di as text "PTE Package Dependency Check"
    di as text "{hline 64}"
    di as text ""
    
    // ================================================================
    // Info: moremata package
    // ----------------------------------------------------------------
    // The live public runtime no longer consumes moremata on the baseline
    // initialization chain. Keep surfacing visibility as environment info
    // because older local workflows may still carry it, but it is not part
    // of the public hard dependency gate.
    // ================================================================

    local n_info = `n_info' + 1
    local moremata_path ""
    capture mata: mata which mm_quantile()
    if _rc == 0 {
        capture findfile lmoremata.mlib
        if _rc == 0 {
            local moremata_path "`r(fn)'"
        }
        di as text "  [" as text "INFO" as text "] moremata package (currently optional)"
        di as text "         Current public runtime does not require moremata."
        if "`detail'" != "" & "`moremata_path'" != "" {
            di as text "         Location: " as result "`moremata_path'"
        }
    }
    else {
        di as text "  [" as text "INFO" as text "] moremata package (currently optional)"
        di as text "         Not installed; current public runtime does not require it."
    }
    
    // ================================================================
    // Info: winsor2 package
    // ----------------------------------------------------------------
    // The live public trim worker uses an internal deterministic 1%-99%
    // trimming path, so winsor2 is no longer a hard runtime dependency for
    // baseline pte estimation. Keep surfacing it as environment information
    // because the official DO replication scripts still call winsor2
    // directly.
    // ================================================================

    local n_info = `n_info' + 1
    capture which winsor2
    if _rc == 0 {
        di as text "  [" as text "INFO" as text "] winsor2 package (optional)"
        if "`detail'" != "" {
            capture findfile winsor2.ado
            if _rc == 0 {
                di as text "         Location: " as result "`r(fn)'"
            }
        }
        if "`notrimeps'" == "" {
            di as text "         Public pte uses its built-in deterministic trim worker."
        }
        else {
            di as text "         Available for DO-style replication scripts if needed."
        }
    }
    else {
        di as text "  [" as text "INFO" as text "] winsor2 package (optional)"
        if "`notrimeps'" == "" {
            di as text "         Not installed; public pte will use built-in trimming."
        }
        else {
            di as text "         Not installed; only DO-style replication scripts need it."
        }
    }
    
    // ================================================================
    // Check 1: Stata version >= 14.0
    // ================================================================
    
    local n_checks = `n_checks' + 1
    if `stata_ver' >= 14.0 {
        local n_pass = `n_pass' + 1
        di as text "  [" as result "PASS" as text "] Stata version `stata_ver' (>= 14.0)"
    }
    else {
        local n_fail = `n_fail' + 1
        di as text "  [" as error "FAIL" as text "] Stata version `stata_ver' (requires >= 14.0)"
        di as text "         Upgrade Stata to version 14.0 or later"
    }

    // ================================================================
    // Check 2: baseline Mata runtime readiness
    // ----------------------------------------------------------------
    // The baseline GMM Mata contract is required for public pte estimation,
    // but compare-only workflows dispatch through reghdfe/TWFE workers and
    // the method-specific compare Mata sources. When compare is the target
    // bundle, certifying the unrelated baseline runtime would over-gate the
    // public pte_compare entry chain.
    // ================================================================

    if "`compare'" == "" {
        local n_checks = `n_checks' + 1
        local mata_ready = 0
        local mata_init_rc = .
        local mata_missing ""

        capture quietly _pte_mata_check
        if _rc == 0 {
            local mata_missing `"`r(missing_funcs)'"'
            if r(all_loaded) == 1 {
                local mata_ready = 1
            }
        }

        if `mata_ready' == 0 {
            capture quietly _pte_mata_init, nolog
            local mata_init_rc = _rc
            capture quietly _pte_mata_check
            if _rc == 0 {
                local mata_missing `"`r(missing_funcs)'"'
                if `mata_init_rc' == 0 & r(all_loaded) == 1 {
                    local mata_ready = 1
                }
            }
        }

        if `mata_ready' == 1 {
            local n_pass = `n_pass' + 1
            di as text "  [" as result "PASS" as text "] baseline Mata runtime"
            if "`detail'" != "" {
                di as text "         Verified: GMM optimizer + matrix constructors"
            }
        }
        else {
            local n_fail = `n_fail' + 1
            di as text "  [" as error "FAIL" as text "] baseline Mata runtime"
            if !missing(`mata_init_rc') {
                di as text "         Initialization rc: " as error "`mata_init_rc'"
            }
            if `"`mata_missing'"' != "" {
                di as text "         Missing: " as error `"`mata_missing'"'
            }
            di as text "         Rebuild with: " as input "_pte_mata_init, force verbose"
        }
    }
    
    // ================================================================
    // Extended checks: treatdependent dependencies
    // ================================================================
    
    if "`treatdependent'" != "" {
        
        di as text ""
        di as text "  Treatment-Dependent Production Function Dependencies:"
        di as text ""
        
        // ============================================================
        // Check 4: prodest package (advisory only)
        // ============================================================
        
        capture which prodest
        if _rc == 0 {
            local n_info = `n_info' + 1
            di as text "  [" as text "INFO" as text "] prodest package (recommended; advisory only)"
            if "`detail'" != "" {
                capture findfile prodest.ado
                if _rc == 0 {
                    di as text "         Location: " as result "`r(fn)'"
                }
            }
            di as text "         Advisory package available; treatdependent gate still depends on endopolyprodest."
        }
        else {
            local n_info = `n_info' + 1
            di as text "  [" as text "INFO" as text "] prodest package (recommended; advisory only)"
            di as text "         Install with: " as input "ssc install prodest"
            di as text "         Current treatdependent gate remains satisfied when endopolyprodest is available."
        }
        
        // ============================================================
        // Check 5: endopolyprodest command
        // ============================================================
        
        local n_checks = `n_checks' + 1
        local endopoly_found = 0
        local endopoly_type = ""
        
        // 5a: Check permanent installation
        capture which endopolyprodest
        if _rc == 0 {
            local endopoly_found = 1
            local endopoly_type = "installed"
        }
        
        // 5b: Check session-defined (fallback)
        if `endopoly_found' == 0 {
            capture program list endopolyprodest
            if _rc == 0 {
                local endopoly_found = 1
                local endopoly_type = "session-defined"
            }
        }
        
        if `endopoly_found' == 1 {
            local n_pass = `n_pass' + 1
            di as text "  [" as result "PASS" as text "] endopolyprodest command (`endopoly_type')"
        }
        else {
            local n_fail = `n_fail' + 1
            di as text "  [" as error "FAIL" as text "] endopolyprodest command"
            di as text "         Load with: " as input "run treatpolyprodest.ado"
        }

        // The runnable treatdependent contract requires the upstream source
        // definitions plus the package-owned patch. A cold installed ado can
        // exist on adopath before its Mata companions are materialized, so
        // dependency checks must actively prepare the runtime contract instead
        // of checking only file presence.
        local n_checks = `n_checks' + 1
        local treatdep_prepare_rc = .
        local treatdep_patch_ready = 0
        local treatdep_patch_file ""
        local treatdep_patch_rc .
        local treatdep_source_loaded = 0
        local treatdep_source_file ""
        local treatdep_source_rc .
        local treatdep_contract_ready = 0
        local treatdep_missing ""

        capture quietly _pte_treatdep_prepare_runtime
        local treatdep_prepare_rc = _rc
        if `treatdep_prepare_rc' == 0 {
            capture local treatdep_patch_ready = r(patch_ready)
            if _rc != 0 | missing(`treatdep_patch_ready') {
                local treatdep_patch_ready = 0
            }
            local treatdep_patch_file `"`r(patch_file)'"'
            capture local treatdep_patch_rc = r(patch_rc)
            capture local treatdep_source_loaded = r(source_loaded)
            if _rc != 0 | missing(`treatdep_source_loaded') {
                local treatdep_source_loaded = 0
            }
            local treatdep_source_file `"`r(source_file)'"'
            capture local treatdep_source_rc = r(source_rc)
            capture local treatdep_contract_ready = r(ready)
            if _rc != 0 | missing(`treatdep_contract_ready') {
                local treatdep_contract_ready = 0
            }
            local treatdep_missing = `"`r(missing)'"'
        }
        else {
            local treatdep_patch_rc = `treatdep_prepare_rc'
            local treatdep_missing "(runtime prepare rc=`treatdep_prepare_rc')"
        }

        if `treatdep_patch_ready' == 1 {
            local n_pass = `n_pass' + 1
            di as text "  [" as result "PASS" as text "] PTE treatdependent Mata patch"
            if "`detail'" != "" {
                di as text "         Location: " as result `"`treatdep_patch_file'"'
                if `treatdep_source_loaded' == 1 & `"`treatdep_source_file'"' != "" {
                    di as text "         Source-loaded: " as result `"`treatdep_source_file'"'
                }
            }
        }
        else {
            local n_fail = `n_fail' + 1
            di as text "  [" as error "FAIL" as text "] PTE treatdependent Mata patch"
            if `"`treatdep_patch_file'"' == "" {
                di as text "         Expected file: " as input "_pte_mata_endopoly_patch.do"
            }
            else {
                di as text "         Failed to load: " as result `"`treatdep_patch_file'"'
                if !missing(`treatdep_patch_rc') {
                    di as text "         Return code: " as error "`treatdep_patch_rc'"
                }
            }
            if `"`treatdep_source_file'"' != "" & !missing(`treatdep_source_rc') {
                di as text "         Upstream source rc: " as error "`treatdep_source_rc'"
            }
            if !missing(`treatdep_prepare_rc') & `treatdep_prepare_rc' != 0 {
                di as text "         Runtime prepare rc: " as error "`treatdep_prepare_rc'"
            }
        }

        local n_checks = `n_checks' + 1
        if `treatdep_contract_ready' == 0 & `"`treatdep_missing'"' == "" {
            local treatdep_missing "(not returned)"
        }

        if `treatdep_contract_ready' == 1 {
            local n_pass = `n_pass' + 1
            di as text "  [" as result "PASS" as text "] treatdependent companion Mata objects"
            if "`detail'" != "" {
                di as text "         Verified: facf1() facf2() facf3() opt_mata()"
            }
        }
        else {
            local n_fail = `n_fail' + 1
            di as text "  [" as error "FAIL" as text "] treatdependent companion Mata objects"
            di as text "         Missing: " as error `"`treatdep_missing'"'
            di as text "         Load the official DO source: " as input "run treatpolyprodest.ado"
        }
    }

    // ================================================================
    // Extended checks: compare workflow dependencies
    // ================================================================

    if "`compare'" != "" {
        
        di as text ""
        di as text "  Compare Workflow Dependencies:"
        di as text ""
        
        // ============================================================
        // Check: reghdfe package for public TWFE comparison commands
        // ============================================================
        
        local n_checks = `n_checks' + 1
        capture which reghdfe
        if _rc == 0 {
            local n_pass = `n_pass' + 1
            di as text "  [" as result "PASS" as text "] reghdfe package"
            if "`detail'" != "" {
                capture findfile reghdfe.ado
                if _rc == 0 {
                    di as text "         Location: " as result "`r(fn)'"
                }
            }
        }
        else {
            local n_fail = `n_fail' + 1
            di as text "  [" as error "FAIL" as text "] reghdfe package"
            di as text "         Install with: " as input "ssc install reghdfe"
        }

        // Compare Methods I and II compile companion Mata source files at
        // runtime. Public dependency checks must therefore certify the same
        // live contract the workers consume: the source must be discoverable
        // via _pte_mata_findpath and it must compile successfully after the
        // worker-specific Mata symbols are dropped.
        foreach compare_bundle in ///
            "_pte_compare_expost_gmm.mata|_pte_model_expost()" ///
            "_pte_compare_endog_gmm.mata|_pte_model_endog()" {
            local n_checks = `n_checks' + 1
            gettoken compare_mata compare_funcs : compare_bundle, parse("|")
            local compare_funcs = subinstr(`"`compare_funcs'"', "|", "", .)
            local compare_drop_funcs "`compare_funcs'"
            if "`compare_mata'" == "_pte_compare_expost_gmm.mata" {
                local compare_drop_funcs "`compare_drop_funcs' _pte_gmm_expost()"
            }
            else if "`compare_mata'" == "_pte_compare_endog_gmm.mata" {
                local compare_drop_funcs "`compare_drop_funcs' _pte_gmm_endog()"
            }
            local compare_rc = .
            local compare_found = 0
            local compare_file ""
            local compare_symbols_ok = 1
            local compare_missing_funcs ""

            capture quietly _pte_mata_findpath, file(`compare_mata')
            if _rc == 0 & r(found) == 1 {
                local compare_found = 1
                local compare_file `"`r(filepath)'"'
            }

            if `compare_found' == 1 {
                foreach compare_func of local compare_drop_funcs {
                    capture mata: mata drop `compare_func'
                }
                capture quietly do `"`compare_file'"'
                local compare_rc = _rc
                if `compare_rc' == 0 {
                    foreach compare_func of local compare_funcs {
                        capture mata: mata describe `compare_func'
                        if _rc != 0 {
                            local compare_symbols_ok = 0
                            local compare_missing_funcs ///
                                `"`compare_missing_funcs' `compare_func'"'
                        }
                    }
                }
            }

            if `compare_found' == 1 & `compare_rc' == 0 & `compare_symbols_ok' == 1 {
                local n_pass = `n_pass' + 1
                di as text "  [" as result "PASS" as text "] compare Mata source `compare_mata'"
                if "`detail'" != "" {
                    di as text "         Location: " as result `"`compare_file'"'
                    di as text "         Compilable and exports the required compare worker-entry symbol"
                }
            }
            else {
                local n_fail = `n_fail' + 1
                di as text "  [" as error "FAIL" as text "] compare Mata source `compare_mata'"
                if `compare_found' == 0 {
                    di as text "         Required by public pte_compare Methods I and II."
                }
                else if `compare_rc' == 0 {
                    di as text "         Source compiled, but the required compare worker-entry symbol is missing:"
                    di as text "         " as error `"`compare_missing_funcs'"'
                }
                else {
                    di as text "         Source found but worker compilation failed (rc=`compare_rc')."
                }
            }
        }
    }
    
    // ================================================================
    // Summary
    // ================================================================
    
    di as text ""
    di as text "{hline 64}"
    
    if `n_fail' == 0 {
        di as result "All dependencies satisfied."
    }
    else {
        di as error "Dependencies missing. Install required packages above."
    }
    
    di as text "{hline 64}"
    
    if "`detail'" != "" {
        di as text ""
        di as text "  Summary: `n_pass'/`n_checks' required checks passed, `n_fail' failed, `n_info' advisory"
        di as text ""
    }
    
    // ================================================================
    // Return values
    // ================================================================
    
    return scalar all_satisfied = (`n_fail' == 0)
    return scalar n_missing = `n_fail'
    return scalar n_checks = `n_checks'
    
end
