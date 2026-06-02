*! _pte_mata_restore_snapshot.ado
*! Transactional restore helper for _pte_mata_init, force

version 14.0
capture program drop _pte_mata_restore_snapshot
program define _pte_mata_restore_snapshot, rclass
    version 14.0

    syntax, DIR(string) [VERBOSE NOLOG]

    local funcs "_pte_construct_gmm_matrices _pte_get_X _pte_get_X_lag _pte_get_Z _pte_get_W _pte_get_PHI _pte_get_PHI_lag _pte_get_C _pte_get_TP_lag _pte_get_N _pte_get_omegapoly _pte_construct_omega_lag_pol _pte_verify_l1k_lag GMM_CLK MODEL_CLK MODEL_CLK_grid MODEL_CLK_multistart _pte_resolve_beta_init _pte_store_result _pte_report_result pte_setup_optimizer pte_execute_optimization pte_optimize_with_diagnostics generate_grid pte_simulate_paths pte_bootstrap_draw pte_mc_dgp _pte_hetero_qtest_compute _pte_simulate_omega1"
    local structs "OptimizationResult"
    local restored_funcs ""
    local restored_structs ""
    local failed_objects ""
    local struct_loaded = 0

    adopath ++ "`dir'"

    foreach func of local funcs {
        capture confirm file "`dir'/`func'.mo"
        if _rc == 0 {
            capture mata: mata drop `func'()
            capture mata: _pte_mata_restore_ptr = &`func'()
            if _rc == 0 {
                local restored_funcs "`restored_funcs' `func'"
            }
            else {
                local failed_objects "`failed_objects' `func'"
            }
        }
    }

    foreach obj of local structs {
        capture confirm file "`dir'/`obj'.mo"
        if _rc == 0 {
            capture mata: mata drop `obj'()
            capture mata: `obj'()
            if _rc == 0 {
                capture mata: mata describe `obj'()
            }
            if _rc == 0 {
                local restored_structs "`restored_structs' `obj'"
                local struct_loaded = 1
            }
            else {
                local failed_objects "`failed_objects' `obj'"
            }
        }
    }

    capture mata: mata drop _pte_mata_restore_ptr
    capture noisily adopath - "`dir'"

    quietly _pte_mata_check
    local all_loaded = r(all_loaded)
    local missing_funcs `"`r(missing_funcs)'"'
    local n_restored_funcs : word count `restored_funcs'
    local n_restored_structs : word count `restored_structs'
    local n_failed : word count `failed_objects'

    if `all_loaded' == 1 {
        global PTE_MATA_INITIALIZED = "1"
    }
    else {
        global PTE_MATA_INITIALIZED = ""
    }

    if "`nolog'" == "" & "`verbose'" != "" {
        di as text "  Snapshot restored: `n_restored_funcs' functions, `n_restored_structs' structs"
        if `"`missing_funcs'"' != "" {
            di as text "  Missing after restore: `missing_funcs'"
        }
        if `n_failed' > 0 {
            di as error "  Restore failures:`failed_objects'"
        }
    }

    return scalar ok = (`n_failed' == 0 & `all_loaded' == 1 & `struct_loaded' == 1)
    return scalar all_loaded = `all_loaded'
    return scalar struct_loaded = `struct_loaded'
    return scalar n_restored_funcs = `n_restored_funcs'
    return scalar n_restored_structs = `n_restored_structs'
    return scalar n_failed = `n_failed'
    return local restored_funcs "`restored_funcs'"
    return local restored_structs "`restored_structs'"
    return local failed_objects "`failed_objects'"
    return local missing_funcs "`missing_funcs'"
end
