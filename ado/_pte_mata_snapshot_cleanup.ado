*! _pte_mata_snapshot_cleanup.ado
*! Remove temporary .mo snapshot files created for transactional Mata rebuilds

version 14.0
capture program drop _pte_mata_snapshot_cleanup
program define _pte_mata_snapshot_cleanup
    version 14.0

    syntax, DIR(string)

    local objs "_pte_construct_gmm_matrices _pte_get_X _pte_get_X_lag _pte_get_Z _pte_get_W _pte_get_PHI _pte_get_PHI_lag _pte_get_C _pte_get_TP_lag _pte_get_N _pte_get_omegapoly _pte_construct_omega_lag_pol _pte_verify_l1k_lag GMM_CLK MODEL_CLK MODEL_CLK_grid MODEL_CLK_multistart _pte_resolve_beta_init _pte_store_result _pte_report_result pte_setup_optimizer pte_execute_optimization pte_optimize_with_diagnostics generate_grid pte_simulate_paths pte_bootstrap_draw pte_mc_dgp _pte_hetero_qtest_compute _pte_simulate_omega1 OptimizationResult"

    foreach obj of local objs {
        capture erase "`dir'/`obj'.mo"
    }

    capture adopath - "`dir'"
end
