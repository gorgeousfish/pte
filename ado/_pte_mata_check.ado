*! _pte_mata_check.ado
*! Usage:
*! [, verbose]
*! Returns:
*! r(all_loaded)      - 1 if all required runtime objects loaded, 0 otherwise
*! r(missing_count)   - Number of missing required runtime objects
*! r(missing_funcs)   - Space-separated list of missing function names
*! r(struct_loaded)   - 1 if OptimizationResult() struct is loaded
*! r(missing_objects) - Space-separated list of missing functions/structs

version 14.0
capture program drop _pte_mata_check
program define _pte_mata_check, rclass
    version 14.0

    syntax [, VERBOSE]

    // Required Mata functions that must be present.
    // This readiness gate must cover the full optimizer entry contract, not
    // just low-level evaluator/accessor symbols; otherwise partial preload
    // states can skip autoload and fail later on missing MODEL_CLK* workers.
    // Note: avoid /// continuation with quoted strings (causes parsing issues)
    local required_funcs "_pte_runtime_signature GMM_CLK MODEL_CLK MODEL_CLK_grid MODEL_CLK_multistart pte_setup_optimizer pte_execute_optimization pte_optimize_with_diagnostics generate_grid _pte_resolve_beta_init _pte_store_result _pte_report_result _pte_gmm_matrices_signature _pte_construct_gmm_matrices _pte_get_N _pte_get_X _pte_get_X_lag _pte_get_Z _pte_get_W _pte_get_PHI _pte_get_PHI_lag _pte_get_C _pte_get_TP_lag _pte_construct_omega_lag_pol"

    // Optional Mata functions (informational only)
    local optional_funcs "pte_simulate_paths pte_bootstrap_draw pte_mc_dgp _pte_hetero_qtest_compute _pte_simulate_omega1"

    local missing_count = 0
    local missing_funcs ""
    local missing_objects ""

    // Rebuild mlib index so newly added adopath entries are visible
    quietly mata: mata mlib index

    // Check required functions
    // Check both .mlib (mata which) and in-memory (mata describe).
    foreach func of local required_funcs {
        local _found 0
        capture mata: mata which `func'()
        if _rc == 0 {
            local _found 1
        }
        else {
            capture mata: mata describe `func'()
            if _rc == 0 {
                local _found 1
            }
        }
        if `_found' == 0 {
            local ++missing_count
            local missing_funcs "`missing_funcs' `func'"
            local missing_objects "`missing_objects' `func'"
            if "`verbose'" != "" {
                di as error "  [MISSING] `func'()"
            }
        }
        else {
            if "`verbose'" != "" {
                di as text "  [OK]      `func'()"
            }
        }
    }

    local struct_loaded = 0
    capture mata: mata which OptimizationResult()
    if _rc == 0 {
        local struct_loaded = 1
    }
    else {
        capture mata: mata describe OptimizationResult()
        if _rc == 0 {
            local struct_loaded = 1
        }
    }
    if `struct_loaded' == 0 {
        local ++missing_count
        local missing_objects "`missing_objects' OptimizationResult"
        if "`verbose'" != "" {
            di as error "  [MISSING] OptimizationResult()"
        }
    }
    else if "`verbose'" != "" {
        di as text "  [OK]      OptimizationResult()"
    }

    local runtime_signature_ok = 0
    local runtime_signature ""
    capture mata: st_local("runtime_signature", _pte_runtime_signature())
    if _rc == 0 & `"`runtime_signature'"' == "pte_gmm_runtime_v1" {
        local runtime_signature_ok = 1
        if "`verbose'" != "" {
            di as text "  [OK]      _pte_runtime_signature() = `runtime_signature'"
        }
    }
    else {
        if "`verbose'" != "" {
            if _rc == 0 {
                di as error "  [MISMATCH] _pte_runtime_signature() = `runtime_signature'"
            }
            else {
                di as error "  [MISSING] _pte_runtime_signature() payload"
            }
        }
        if strpos(" `missing_objects' ", " runtime_signature ") == 0 {
            local ++missing_count
            local missing_objects "`missing_objects' runtime_signature"
        }
    }

    local gmm_matrices_signature_ok = 0
    local gmm_matrices_signature ""
    capture mata: st_local("gmm_matrices_signature", _pte_gmm_matrices_signature())
    if _rc == 0 & `"`gmm_matrices_signature'"' == "pte_gmm_matrices_v2_11args" {
        local gmm_matrices_signature_ok = 1
        if "`verbose'" != "" {
            di as text "  [OK]      _pte_gmm_matrices_signature() = `gmm_matrices_signature'"
        }
    }
    else {
        if "`verbose'" != "" {
            if _rc == 0 {
                di as error "  [MISMATCH] _pte_gmm_matrices_signature() = `gmm_matrices_signature'"
            }
            else {
                di as error "  [MISSING] _pte_gmm_matrices_signature() payload"
            }
        }
        if strpos(" `missing_objects' ", " gmm_matrices_signature ") == 0 {
            local ++missing_count
            local missing_objects "`missing_objects' gmm_matrices_signature"
        }
    }

    // Baseline readiness must certify semantics as well as names. A forged
    // preload can spoof the package signature string and export same-name
    // stubs, so probe the deterministic CD/translog grid contract that the
    // optimizer wrapper consumes at entry. This stays lightweight while
    // fail-closing fake or stale same-name runtimes before public pte/pte_check_deps
    // accept them as baseline-ready.
    local grid_semantics_ok = 0
    local grid_cd_rows ""
    local grid_cd_cols ""
    local grid_cd_11 ""
    local grid_cd_52 ""
    local grid_tl_rows ""
    local grid_tl_cols ""
    local grid_tl_11 ""
    local grid_tl_25 ""
    capture mata: st_local("grid_cd_rows", strofreal(rows(generate_grid((0.5, 0.5), 0))))
    capture mata: st_local("grid_cd_cols", strofreal(cols(generate_grid((0.5, 0.5), 0))))
    capture mata: st_local("grid_cd_11", strofreal(generate_grid((0.5, 0.5), 0)[1,1]))
    capture mata: st_local("grid_cd_52", strofreal(generate_grid((0.5, 0.5), 0)[5,2]))
    capture mata: st_local("grid_tl_rows", strofreal(rows(generate_grid((1, 2, 3, 4, 5), 1))))
    capture mata: st_local("grid_tl_cols", strofreal(cols(generate_grid((1, 2, 3, 4, 5), 1))))
    capture mata: st_local("grid_tl_11", strofreal(generate_grid((1, 2, 3, 4, 5), 1)[1,1]))
    capture mata: st_local("grid_tl_25", strofreal(generate_grid((1, 2, 3, 4, 5), 1)[2,5]))

    if `"`grid_cd_rows'"' != "" & `"`grid_cd_cols'"' != "" & ///
        `"`grid_cd_11'"' != "" & `"`grid_cd_52'"' != "" & ///
        `"`grid_tl_rows'"' != "" & `"`grid_tl_cols'"' != "" & ///
        `"`grid_tl_11'"' != "" & `"`grid_tl_25'"' != "" {
        if real(`"`grid_cd_rows'"') == 5 & real(`"`grid_cd_cols'"') == 2 & ///
            abs(real(`"`grid_cd_11'"') - 0.5) <= 1e-12 & ///
            abs(real(`"`grid_cd_52'"') - 0.6) <= 1e-12 & ///
            real(`"`grid_tl_rows'"') == 5 & real(`"`grid_tl_cols'"') == 5 & ///
            abs(real(`"`grid_tl_11'"') - 1) <= 1e-12 & ///
            abs(real(`"`grid_tl_25'"') - 6) <= 1e-12 {
            local grid_semantics_ok = 1
        }
    }

    if `grid_semantics_ok' == 0 {
        if "`verbose'" != "" {
            di as error "  [MISMATCH] generate_grid() semantics do not match the package-owned baseline runtime"
        }
        if strpos(" `missing_objects' ", " generate_grid_semantics ") == 0 {
            local ++missing_count
            local missing_objects "`missing_objects' generate_grid_semantics"
        }
    }
    else if "`verbose'" != "" {
        di as text "  [OK]      generate_grid() semantics"
    }

    // Check optional functions (informational)
    if "`verbose'" != "" {
        foreach func of local optional_funcs {
            capture mata: mata describe `func'()
            if _rc == 0 {
                di as text "  [OK]      `func'()"
            }
            else {
                di as text "  [SKIP]    `func'() (optional)"
            }
        }
    }

    // Set return values
    local all_loaded = (`missing_count' == 0)
    return scalar all_loaded = `all_loaded'
    return scalar missing_count = `missing_count'
    return scalar struct_loaded = `struct_loaded'
    return scalar runtime_signature_ok = `runtime_signature_ok'
    return scalar gmm_matrices_signature_ok = `gmm_matrices_signature_ok'
    return scalar grid_semantics_ok = `grid_semantics_ok'
    return local missing_funcs "`missing_funcs'"
    return local missing_objects "`missing_objects'"
    return local runtime_signature "`runtime_signature'"
end
