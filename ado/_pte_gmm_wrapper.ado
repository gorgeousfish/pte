*! _pte_gmm_wrapper.ado
*! Bridge from the Stata orchestration layer to the CLK Mata optimizer.
*! Expects _pte_gmm_matrices to have already populated the cached views that
*! exclude transition-period observations (mid==1) and use phi net of controls.

version 14.0
capture program drop _pte_gmm_wrapper
program define _pte_gmm_wrapper, rclass
    version 14.0

    // Parse the production-function shape and the order of the untreated
    // productivity law of motion that will be concentrated out inside Mata.
    syntax , PRODFUNC(string) OMEGAPOLY(integer) [MULTISTART NOLOG MAXiter(integer 10000) ///
        TOLerance(real 1e-6) INIT(numlist) GRID]

    // Restrict the wrapper to the two production-function parameterizations
    // implemented by the cached design matrices.
    if !inlist("`prodfunc'", "cd", "translog") {
        di as error "{bf:_pte_gmm_wrapper}: prodfunc must be 'cd' or 'translog'"
        di as error "  Specified: `prodfunc'"
        exit 198
    }

    // The paper and replication code use low-order polynomials for hbar_0;
    // the wrapper keeps that contract explicit before Mata allocates moments.
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "{bf:_pte_gmm_wrapper}: omegapoly must be between 1 and 4"
        di as error "  Specified: `omegapoly'"
        exit 198
    }

    // omegapoly governs the separate productivity evolution regression, not the
    // Cobb-Douglas versus translog choice in the production function itself.

    // Bound the relative convergence tolerance to keep the Nelder-Mead path
    // within the same numerical regime as the reference implementation.
    if `tolerance' > 0.01 {
        di as text "{bf:Note}: tolerance(`tolerance') truncated to 1e-5 (max 1e-5)"
        local tolerance = 0.00001
    }
    if `tolerance' <= 0 {
        di as text "{bf:Note}: tolerance must be positive, using default 1e-6"
        local tolerance = 1e-6
    }

    // Custom initial values must match the dimensionality of the active
    // production function because Mata reads them as a full beta vector.
    if "`init'" != "" {
        local n_init : word count `init'
        local expected_n = cond("`prodfunc'" == "cd", 2, 5)
        if `n_init' != `expected_n' {
            di as error "{bf:_pte_gmm_wrapper}: init() requires `expected_n' values for `prodfunc'"
            di as error "  Provided: `n_init' values"
            exit 198
        }
    }

    // Reconfirm that the package-wide Mata namespace is live before calling
    // MODEL_CLK* helpers. This avoids failing midway after Stata-side setup has
    // already built the matrix cache.
    // Reuse the package-wide Mata readiness gate so partial preload states
    // cannot slip past this wrapper and fail later on missing MODEL_CLK*.
    // If not ready, derive mata/ path from this ado file's own location
    // (c(pwd) is unreliable; profile.do may change it).
    local _gmm_ok 0
    capture quietly _pte_mata_check
    if _rc == 0 & r(all_loaded) == 1 {
        local _gmm_ok 1
    }
    
    if "`_gmm_ok'" != "1" {
        // Recompile through the shared initializer so stale Mata symbols are
        // dropped consistently instead of leaving a half-loaded namespace.
        capture quietly _pte_mata_init, force nolog
        if _rc != 0 | r(all_loaded) != 1 {
            di as error "{bf:_pte_gmm_wrapper}: Cannot load mata/pte_gmm_clk.mata"
            di as error "  Ensure Mata functions are loaded before calling this module"
            di as error "  Current working directory: `c(pwd)'"
            exit 601
        }
    }

    // The optimizer reads globals populated by _pte_gmm_matrices. Failing
    // closed here is safer than letting Mata evaluate with empty views.
    mata: st_local("matrices_exist", strofreal(!missing(_pte_get_N()) & _pte_get_N() > 0))
    if "`matrices_exist'" != "1" {
        di as error "{bf:_pte_gmm_wrapper}: GMM matrices not found"
        di as error "  Please run _pte_gmm_matrices first"
        exit 498
    }

    // Mata reads these macros to choose the criterion layout and optimization
    // controls without duplicating Stata-side parsing logic.
    local prodfunc "`prodfunc'"
    local omegapoly `omegapoly'
    local maxiter `maxiter'
    local tolerance `tolerance'

    // Report the numerical contract that is about to be handed to Mata so the
    // caller can see whether grid or multistart changed the search path.
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "GMM Optimization"
        di as text "{hline 60}"
        di as text _col(3) "Production function:" _col(40) as result "`prodfunc'"
        di as text _col(3) "Omega polynomial order:" _col(40) as result `omegapoly'
        if "`multistart'" != "" {
            di as text _col(3) "Multi-start strategy:" _col(40) as result "enabled"
        }
        if "`grid'" != "" {
            di as text _col(3) "Grid search:" _col(40) as result "enabled"
        }
        di as text _col(3) "Tolerance:" _col(40) as result %12.2e `tolerance'
        if "`init'" != "" {
            di as text _col(3) "Custom init values:" _col(40) as result "`init'"
        }
    }

    // Persist custom starting values in a named matrix because the Mata
    // optimizer accesses it directly when custom seeding is requested.
    if "`init'" != "" {
        local n_init : word count `init'
        tempname init_mat
        matrix `init_mat' = J(1, `n_init', .)
        forvalues i = 1/`n_init' {
            matrix `init_mat'[1, `i'] = real(word("`init'", `i'))
        }
        matrix beta_init_custom = `init_mat'
        local use_custom_init 1
    }
    else {
        local use_custom_init 0
    }

    // Choose among the supported search strategies. All three end up solving
    // the same concentrated-out criterion; only the starting-path logic varies.
    if "`grid'" != "" {
        // Deterministic fallback used when the caller wants reproducible
        // exploration over a fixed lattice of beta starting points.
        mata: MODEL_CLK_grid()
    }
    else if "`multistart'" != "" {
        // Random restarts help when the criterion surface is flat or locally
        // irregular, but they do not alter the moment conditions themselves.
        mata: MODEL_CLK_multistart()
    }
    else {
        // Lean path that mirrors the single-start reference workflow.
        mata: MODEL_CLK()
    }

    // Mata materializes beta, criterion value, and convergence diagnostics in
    // shared Stata objects; copy them out immediately before any later code can
    // overwrite those names.
    matrix beta = beta
    scalar fval = fval
    scalar converged = converged
    scalar iterations = iterations

    // Non-convergence and very long runs are surfaced separately because a
    // finite fval alone does not tell the caller whether the simplex settled.
    if converged == 0 {
        _pte_convergence_warning `=fval' `=iterations' `maxiter'
    }
    else if iterations > 5000 {
        // A large iteration count usually signals a flat criterion or weak
        // curvature around the optimum rather than an outright failure.
        di as text ""
        di as text "Note: Optimization used `=iterations' iterations (> 5000)"
        di as text "Results are valid but may indicate a flat objective function"
        di as text "Consider: checking data quality or simplifying the model"
    }

    // Verify the returned beta vector against the active parameterization before
    // downstream productivity recovery interprets individual coefficients.
    local expected_cols = cond("`prodfunc'" == "cd", 2, 5)
    if colsof(beta) != `expected_cols' {
        di as error "{bf:_pte_gmm_wrapper}: beta dimension mismatch"
        di as error "  Expected: `expected_cols', Got: " colsof(beta)
        exit 503
    }

    // The GMM quadratic form should be weakly nonnegative when W is positive
    // semidefinite. A negative value indicates numerical corruption upstream.
    if fval < 0 {
        di as error "{bf:_pte_gmm_wrapper}: negative criterion value (fval = " fval ")"
        di as error "  This indicates a numerical error"
        exit 504
    }

    // Missing betas would make omega recovery ill-defined and usually mean the
    // optimizer exited through an invalid parameter path.
    mata: st_local("beta_missing", strofreal(missing(st_matrix("beta"))))
    if "`beta_missing'" != "0" {
        di as error "{bf:_pte_gmm_wrapper}: beta contains missing values"
        exit 504
    }

    // Echo the estimated coefficients so callers can compare the final point
    // estimate against the stage-one seeds without opening the return matrix.
    if "`nolog'" == "" {
        di as text ""
        di as text "Optimization Results:"
        di as text _col(3) "Converged:" _col(40) as result cond(converged, "Yes", "No")
        di as text _col(3) "Final criterion (fval):" _col(40) as result %12.8f fval
        
        di as text ""
        di as text "Parameter Estimates:"
        if "`prodfunc'" == "cd" {
            di as text _col(3) "beta_l:" _col(40) as result %12.8f beta[1,1]
            di as text _col(3) "beta_k:" _col(40) as result %12.8f beta[1,2]
        }
        else {
            di as text _col(3) "beta_l:" _col(40) as result %12.8f beta[1,1]
            di as text _col(3) "beta_k:" _col(40) as result %12.8f beta[1,2]
            di as text _col(3) "beta_ll:" _col(40) as result %12.8f beta[1,3]
            di as text _col(3) "beta_kk:" _col(40) as result %12.8f beta[1,4]
            di as text _col(3) "beta_lk:" _col(40) as result %12.8f beta[1,5]
        }
        di as text "{hline 60}"
        di as text ""
    }

    // Return only the optimization outputs owned by this wrapper; the matrix
    // cache remains in Mata for later omega recovery and diagnostics.
    return matrix beta = beta
    return scalar fval = fval
    return scalar converged = converged
    return scalar iterations = iterations
    return scalar omegapoly = `omegapoly'
    return local prodfunc "`prodfunc'"

end
