*! _pte_mata_snapshot.ado
*! Transactional snapshot helper for _pte_mata_init, force

version 14.0
capture program drop _pte_mata_snapshot
program define _pte_mata_snapshot, rclass
    version 14.0

    syntax, DIR(string) [VERBOSE NOLOG]

    local funcs "_pte_construct_gmm_matrices _pte_get_X _pte_get_X_lag _pte_get_Z _pte_get_W _pte_get_PHI _pte_get_PHI_lag _pte_get_C _pte_get_TP_lag _pte_get_N _pte_get_omegapoly _pte_construct_omega_lag_pol _pte_verify_l1k_lag GMM_CLK MODEL_CLK MODEL_CLK_grid MODEL_CLK_multistart _pte_resolve_beta_init _pte_store_result _pte_report_result pte_setup_optimizer pte_execute_optimization pte_optimize_with_diagnostics generate_grid pte_simulate_paths pte_bootstrap_draw pte_mc_dgp _pte_hetero_qtest_compute _pte_simulate_omega1"
    local structs "OptimizationResult"
    local saved_funcs ""
    local saved_structs ""
    local failed_objects ""

    capture mkdir "`dir'"

    foreach func of local funcs {
        capture mata: mata describe `func'()
        if _rc == 0 {
            capture mata: mata mosave `func'(), dir("`dir'") replace
            if _rc == 0 {
                local saved_funcs "`saved_funcs' `func'"
            }
            else {
                local failed_objects "`failed_objects' `func'"
            }
        }
    }

    foreach obj of local structs {
        capture mata: mata describe `obj'()
        if _rc == 0 {
            capture mata: mata mosave `obj'(), dir("`dir'") replace
            if _rc == 0 {
                local saved_structs "`saved_structs' `obj'"
            }
            else {
                local failed_objects "`failed_objects' `obj'"
            }
        }
    }

    local n_saved_funcs : word count `saved_funcs'
    local n_saved_structs : word count `saved_structs'
    local n_failed : word count `failed_objects'

    if "`nolog'" == "" & "`verbose'" != "" {
        di as text "  Snapshot saved: `n_saved_funcs' functions, `n_saved_structs' structs"
        if `n_failed' > 0 {
            di as error "  Snapshot failures:`failed_objects'"
        }
    }

    return scalar ok = (`n_failed' == 0)
    return scalar n_saved_funcs = `n_saved_funcs'
    return scalar n_saved_structs = `n_saved_structs'
    return scalar n_failed = `n_failed'
    return local dir "`dir'"
    return local saved_funcs "`saved_funcs'"
    return local saved_structs "`saved_structs'"
    return local failed_objects "`failed_objects'"
end
