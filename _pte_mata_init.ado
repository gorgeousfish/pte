*! _pte_mata_init.ado
*! Compiles and loads all required Mata functions from .mata source files.
*! Usage:
*! [, force verbose nolog]
*! Options:
*! force   - Recompile even if functions already loaded
*! verbose - Display detailed progress information
*! nolog   - Suppress all output (silent mode)
*! Required Mata functions:
*! GMM_CLK()                  - GMM objective function (pte_gmm_clk.mata)
*! _pte_construct_gmm_matrices() - Matrix construction (pte_gmm_matrices.mata)
*! pte_setup_optimizer()      - Optimizer setup (pte_gmm_clk.mata)
*! pte_optimize_with_diagnostics() - Optimization driver (pte_gmm_clk.mata)
*! Optional Mata functions:
*! pte_simulate_paths()       - Path simulation (pte_simulate.mata)
*! pte_bootstrap_draw()       - Bootstrap resampling (pte_bootstrap.mata)
*! pte_mc_dgp()               - MC data generation (pte_mc_dgp.mata)
*! _pte_hetero_qtest_compute() - Cohort heterogeneity Q-test engine (pte_hetero_qtest.mata)
*! _pte_simulate_omega1()     - Divergent counterfactual omega^1 simulator (_pte_simulate_omega1.mata)

version 14.0
capture program drop _pte_mata_init
program define _pte_mata_init, rclass
    version 14.0

    syntax [, FORCE VERBOSE NOLOG]
    
    local had_ready_runtime 0
    local snapshot_dir ""
    local restored_runtime 0
    local restore_missing ""

    quietly _pte_mata_check
    if _rc == 0 & r(all_loaded) == 1 {
        local had_ready_runtime 1
    }

    // ================================================================
    // Step 1: Check if functions already loaded (skip if not forced)
    // Uses $PTE_MATA_INITIALIZED global + _pte_mata_check verification
    // ================================================================
    if "`force'" == "" {
        if "${PTE_MATA_INITIALIZED}" == "1" {
            quietly _pte_mata_check
            if r(all_loaded) == 1 {
                if "`nolog'" == "" & "`verbose'" != "" {
                    di as text "  All required Mata functions already loaded."
                }
                return scalar compiled = 0
                return scalar all_loaded = 1
                return scalar n_compiled = 0
                return scalar n_failed = 0
                exit
            }
        }
        else {
            // Global not set, but functions might exist from previous session
            quietly _pte_mata_check
            if r(all_loaded) == 1 {
                global PTE_MATA_INITIALIZED = "1"
                if "`nolog'" == "" & "`verbose'" != "" {
                    di as text "  All required Mata functions already loaded."
                }
                return scalar compiled = 0
                return scalar all_loaded = 1
                return scalar n_compiled = 0
                return scalar n_failed = 0
                exit
            }
        }
    }

    if "`force'" != "" & `had_ready_runtime' == 1 {
        tempname _pte_snapshot_id
        local snapshot_dir "`c(tmpdir)'/pte_mata_snapshot_`_pte_snapshot_id'"
        capture quietly _pte_mata_snapshot, dir("`snapshot_dir'") `verbose' `nolog'
        if _rc != 0 | r(n_failed) > 0 {
            if "`nolog'" == "" {
                di as error "pte error: cannot snapshot ready Mata runtime before force rebuild"
            }
            exit 601
        }
    }

    // Clean existing functions before compilation to avoid "already exists" errors
    capture _pte_mata_clean, all confirm

    // ================================================================
    // Step 2: Find and compile .mata files
    // ================================================================
    local n_compiled = 0
    local n_failed = 0
    local failed_files ""

    // Define file list: filename -> required/optional
    // Required files
    local mata_files "pte_gmm_clk.mata pte_gmm_matrices.mata"
    // Optional files (may not exist yet)
    local mata_optional "pte_simulate.mata pte_bootstrap.mata pte_mc_dgp.mata pte_hetero_qtest.mata _pte_simulate_omega1.mata"

    if "`nolog'" == "" & "`verbose'" != "" {
        di as text ""
        di as text "  Mata Function Initialization"
        di as text _dup(50) "-"
    }

    // Compile required files
    foreach f of local mata_files {
        _pte_mata_compile_file, file(`f') `verbose' `nolog'
        if r(success) == 1 {
            local ++n_compiled
        }
        else {
            local ++n_failed
            local failed_files "`failed_files' `f'"
        }
    }

    // Compile optional files (no error on missing)
    foreach f of local mata_optional {
        _pte_mata_compile_file, file(`f') `verbose' `nolog'
        if r(success) == 1 {
            local ++n_compiled
        }
        else if r(error_code) == 601 {
            if "`nolog'" == "" & "`verbose'" != "" {
                di as text "  [SKIP] `f' (not found, optional)"
            }
        }
        // Optional: other compilation failures remain non-fatal here.
    }

    // ================================================================
    // Step 3: Verify all required functions loaded
    // ================================================================
    quietly _pte_mata_check
    local all_ok = r(all_loaded)
    local rebuild_failed = (`all_ok' == 0)

    if "`nolog'" == "" & "`verbose'" != "" {
        di as text _dup(50) "-"
        di as text "  Compiled: `n_compiled'  Failed: `n_failed'"
        if `all_ok' {
            di as result "  All required Mata functions loaded successfully."
        }
        else {
            di as error "  WARNING: Some required functions missing."
            di as error "  Missing: `r(missing_funcs)'"
        }
    }

    if `rebuild_failed' {
        capture _pte_mata_clean, all confirm
        if `had_ready_runtime' == 1 & "`snapshot_dir'" != "" {
            capture quietly _pte_mata_restore_snapshot, dir("`snapshot_dir'") `verbose' `nolog'
            if _rc == 0 & r(ok) == 1 {
                local restored_runtime 1
                local all_ok = 1
            }
            else if _rc == 0 {
                local restore_missing `"`r(missing_objects)'"'
            }
        }
    }

    // Error if required functions missing
    if `rebuild_failed' {
        if `restored_runtime' == 1 & "`nolog'" == "" {
            di as text "  Restored previously ready Mata runtime after failed force rebuild."
        }
        else if `had_ready_runtime' == 1 & "`snapshot_dir'" != "" & "`nolog'" == "" {
            di as error "  WARNING: failed to fully restore the previous ready Mata runtime."
            if `"`restore_missing'"' != "" {
                di as error "  Missing after restore:`restore_missing'"
            }
        }
        di as error "pte error: Failed to compile required Mata files:`failed_files'"
        di as error "  Try: net install pte, replace"
        if "`snapshot_dir'" != "" {
            capture _pte_mata_snapshot_cleanup, dir("`snapshot_dir'")
        }
        exit 601
    }

    // Set global initialization flag (M.5: final verification)
    if `all_ok' {
        global PTE_MATA_INITIALIZED = "1"
    }

    if "`snapshot_dir'" != "" {
        capture _pte_mata_snapshot_cleanup, dir("`snapshot_dir'")
    }

    // Return values
    return scalar compiled = 1
    return scalar all_loaded = `all_ok'
    return scalar n_compiled = `n_compiled'
    return scalar n_failed = `n_failed'
end
