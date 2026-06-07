*! _pte_mata_clean.ado
*! Usage:
*! [, all confirm verbose]
*! Options:
*! all     - Drop all PTE Mata functions (required + optional)
*! confirm - Required safety flag (prevents accidental cleanup)
*! verbose - Display progress

version 14.0
capture program drop _pte_mata_clean
program define _pte_mata_clean
    version 14.0

    syntax [, ALL CONFIRM VERBOSE]

    if "`confirm'" == "" {
        di as error "pte error: _pte_mata_clean requires confirm option"
        di as error "  Usage: _pte_mata_clean, all confirm"
        exit 198
    }

    // Functions to drop - use single line to avoid /// continuation issues
    // pte_gmm_matrices.mata functions
    local funcs "_pte_gmm_matrices_signature _pte_construct_gmm_matrices _pte_get_X _pte_get_X_lag _pte_get_Z _pte_get_W _pte_get_PHI _pte_get_PHI_lag _pte_get_C _pte_get_TP_lag _pte_get_N _pte_get_omegapoly _pte_construct_omega_lag_pol _pte_verify_l1k_lag"
    // pte_gmm_clk.mata functions
    local funcs "`funcs' _pte_runtime_signature GMM_CLK MODEL_CLK MODEL_CLK_grid MODEL_CLK_multistart _pte_resolve_beta_init _pte_store_result _pte_report_result pte_setup_optimizer pte_execute_optimization pte_optimize_with_diagnostics generate_grid"

    if "`all'" != "" {
        // Keep force reload aligned with _pte_mata_init's optional compile set.
        local funcs "`funcs' pte_simulate_paths pte_bootstrap_draw pte_mc_dgp _pte_hetero_qtest_compute _pte_simulate_omega1"
    }

    local n_dropped = 0
    foreach func of local funcs {
        capture mata: mata drop `func'()
        if _rc == 0 {
            local ++n_dropped
            if "`verbose'" != "" {
                di as text "  [DROP] `func'()"
            }
        }
    }

    // Also drop the struct if it exists
    capture mata: mata drop OptimizationResult()
    
    // Clear initialization flag (M.5 counterpart)
    global PTE_MATA_INITIALIZED = ""
    
    if "`verbose'" != "" {
        di as text "  Dropped `n_dropped' Mata functions."
    }
end
