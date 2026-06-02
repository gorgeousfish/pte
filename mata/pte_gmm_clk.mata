*! version 1.0.0  03Feb2026
*! GMM optimizer for the CLK production-function estimator.
*!
*! This Mata module evaluates the Theorem 3.1 criterion after the ado layer
*! has already removed first-panel observations and transition periods with
*! D_t != D_{t-1}. The moment condition is therefore enforced only on stable
*! treatment states, matching the paper and the reference DO files.
*!
*! For each candidate beta, the evaluator:
*!   1. Recovers realized productivity omega_t(beta) = phi_t - X_t beta.
*!   2. Rebuilds the lagged evolution basis OMEGA_LAG_POL.
*!   3. Concentrates out the evolution coefficients g_b by OLS.
*!   4. Forms the one-step GMM objective Q(beta) = (Z'xi)' W (Z'xi),
*!      where W = invsym(Z'Z) / N and xi is the implied evolution residual.

version 14.0

mata:

// ====================================================================
// Package-owned runtime signature.
// The baseline dependency gate must certify that the live symbols come from
// the PTE GMM bundle rather than from arbitrary same-name preloads.
// ====================================================================
string scalar _pte_runtime_signature()
{
    return("pte_gmm_runtime_v1")
}

// ====================================================================
// OptimizationResult stores the optimizer payload returned to Stata.
// The numeric contract is intentionally minimal so the ado layer can decide
// whether to fail closed, retry with alternative starts, or just report.
// ====================================================================
struct OptimizationResult {
    real matrix betas       // Parameter estimates (CD: 1x2, Translog: 1x5)
    real scalar fval        // Final objective function value Q(beta_hat) >= 0
    real scalar converged   // Convergence flag {0, 1}
    real scalar iterations  // Number of iterations in [1, maxiter]
    real scalar rc          // Optimizer return code {0, 1, >=2}
}

// ====================================================================
// Configure the Nelder-Mead optimizer used by the reference implementation.
// The evaluator is derivative-free because g_b is concentrated out inside
// the criterion, so we only need function values.
// ====================================================================
transmorphic scalar pte_setup_optimizer(
    pointer(function) evaluator,
    real matrix init,
    real scalar maxiter,
    real scalar tol,
    real scalar simplex_delta)
{
    transmorphic scalar S
    S = optimize_init()
    optimize_init_evaluator(S, evaluator)
    optimize_init_evaluatortype(S, "d0")
    optimize_init_technique(S, "nm")
    optimize_init_conv_maxiter(S, maxiter)
    optimize_init_conv_nrtol(S, tol)
    optimize_init_nmsimplexdeltas(S, simplex_delta)
    optimize_init_which(S, "min")
    optimize_init_params(S, init)
    return(S)
}

// ====================================================================
// Run optimize() once and copy the fresh result into a stable structure.
// ====================================================================
struct OptimizationResult scalar pte_execute_optimization(transmorphic scalar S)
{
    struct OptimizationResult scalar result
    result.rc = _optimize(S)
    result.converged = (result.rc == 0) ? 1 : 0
    result.betas = optimize_result_params(S)
    result.fval = optimize_result_value(S)
    result.iterations = optimize_result_iterations(S)
    return(result)
}

// ====================================================================
// Generate deterministic fallback starts.
// CD uses a fixed low-dimensional grid; Translog perturbs the OLS anchor so
// retries stay close to a locally meaningful scale.
// ====================================================================
real matrix generate_grid(real matrix init, real scalar is_translog)
{
    real matrix grid
    
    if (is_translog) {
        // Translog: perturb around OLS initial values
        grid = init \
               init :* 1.2 \
               init :* 0.8 \
               init :* 1.1 \
               init :* 0.9
    }
    else {
        // CD: fixed grid points (first row = default (0.5, 0.5))
        grid = (0.5, 0.5) \
               (0.3, 0.3) \
               (0.7, 0.7) \
               (0.4, 0.4) \
               (0.6, 0.6)
    }
    return(grid)
}

// ====================================================================
// Main optimization wrapper with optional deterministic fallback starts.
// ====================================================================
struct OptimizationResult scalar pte_optimize_with_diagnostics(
    pointer(function) evaluator,
    real matrix init,
    real scalar maxiter,
    real scalar tol,
    real scalar simplex_delta,
    real scalar use_grid,
    real scalar is_translog)
{
    struct OptimizationResult scalar result, best_result, try_result
    transmorphic scalar S
    real matrix grid
    real scalar i, n_grid, best_fval
    
    // ================================================================
    // Step 1: Primary optimization attempt
    // ================================================================
    S = pte_setup_optimizer(evaluator, init, maxiter, tol, simplex_delta)
    result = pte_execute_optimization(S)
    
    // ================================================================
    // Step 2: Check convergence and handle failure
    // ================================================================
    if (result.converged == 1) {
        // A converged optimizer is still unusable if the stored criterion is invalid.
        if (result.fval == . | result.fval < 0) {
            errprintf("Error 504: Invalid objective function value (fval = %g)\n", result.fval)
            exit(504)
        }
        return(result)
    }
    
    // ================================================================
    // Step 3: Multi-start strategy (if grid enabled)
    // ================================================================
    if (use_grid) {
        printf("{txt}Primary optimization did not converge (rc=%g)\n", result.rc)
        printf("{txt}Attempting multi-start grid search...\n")
        
        grid = generate_grid(init, is_translog)
        n_grid = rows(grid)
        best_fval = .
        best_result = result  // fallback to primary result
        
        for (i = 1; i <= n_grid; i++) {
            S = pte_setup_optimizer(evaluator, grid[i, .], maxiter, tol, simplex_delta)
            try_result = pte_execute_optimization(S)
            
            if (try_result.converged == 1) {
                if (best_fval == . | try_result.fval < best_fval) {
                    best_fval = try_result.fval
                    best_result = try_result
                    printf("{txt}  Grid point %g: converged, fval = %g\n", i, try_result.fval)
                }
            }
            else {
                printf("{txt}  Grid point %g: did not converge (rc=%g)\n", i, try_result.rc)
            }
        }
        
        // Return the best converged retry, otherwise fail closed.
        if (best_result.converged == 1) {
            printf("{txt}Best result from grid search: fval = %g\n", best_result.fval)
            return(best_result)
        }
        
        // All grid points failed
        errprintf("\nError 430: GMM optimization failed to converge\n")
        errprintf("  All %g grid starting points failed\n", n_grid)
        errprintf("  Consider: checking data quality, increasing maxiter, or simplifying model\n")
        exit(430)
    }
    
    // ================================================================
    // Step 4: No grid - return with warning (do not exit)
    // ================================================================
    printf("\n{err}Warning: GMM optimization did not converge (rc=%g)\n", result.rc)
    printf("{err}  Final criterion value: %g\n", result.fval)
    printf("{err}  Iterations: %g / %g\n", result.iterations, maxiter)
    printf("{err}  Consider: init(), grid, maxiter(), tolerance()\n\n")
    
    // Even a warning path should not publish a missing criterion value.
    if (result.fval == .) {
        errprintf("Error 504: Objective function value is missing\n")
        exit(504)
    }
    
    return(result)
}

// ====================================================================
// GMM evaluator used by optimize().
// ====================================================================
// The signature matches optimize() and the reference DO files exactly.
// `todo', `g', and `H' are placeholders because Nelder-Mead only consumes
// the scalar criterion value. Upstream code must supply matrices that already
// exclude transition periods; this function does not re-filter the sample.
// ====================================================================

void GMM_CLK(real scalar todo, real rowvector betas, 
             real scalar crit, real rowvector g, real matrix H)
{
    // ================================================================
    // Local matrix names follow the notation in the paper/DO code so the
    // concentrated-out mapping between productivity and evolution moments
    // remains easy to audit.
    // ================================================================
    real matrix PHI, PHI_LAG, Z, W, X, X_lag, C, TP_lag
    real matrix OMEGA, OMEGA_lag, OMEGA_LAG_POL
    real matrix OMEGA_TP_lag, OMEGA2_lag, OMEGA2_TP_lag
    real matrix OMEGA3_lag, OMEGA3_TP_lag, OMEGA4_lag, OMEGA4_TP_lag
    real matrix OLtOL, ZtZ
    real colvector g_b, XI
    real scalar det_ZtZ, cond_ZtZ, det_OLtOL, N
    real scalar omegapoly
    string scalar prodfunc
    
    // ================================================================
    // Read the active production-function specification from Stata locals.
    // ================================================================
    prodfunc = st_local("prodfunc")
    omegapoly = strtoreal(st_local("omegapoly"))
    
    // ================================================================
    // Pull the matrices prepared by pte_gmm_matrices.mata. Those matrices are
    // the post-filter sample, so rows(X) is the GMM estimation sample size.
    // ================================================================
    PHI = _pte_get_PHI()
    PHI_LAG = _pte_get_PHI_lag()
    X = _pte_get_X()
    X_lag = _pte_get_X_lag()
    Z = _pte_get_Z()
    C = _pte_get_C()
    TP_lag = _pte_get_TP_lag()
    
    N = rows(X)
    
    // ================================================================
    // [3] Z'Z numerical stability checks
    //
    // Official DO implementation uses one-step GMM:
    //   W = invsym(Z'Z) / N
    // with no absolute det(Z'Z) threshold. A fixed determinant cutoff is
    // scale-sensitive: rescaling a full-rank Z by c changes det(Z'Z) by
    // c^(2K) but does not change identification. Therefore we avoid any
    // absolute det threshold and instead use a scale-invariant condition
    // number diagnostic. Extremely ill-conditioned Z'Z is treated as a
    // true numerical singularity.
    // ================================================================
    ZtZ = cross(Z, Z)
    cond_ZtZ = cond(ZtZ)

    // Strict guard: numerically singular / unusable Z'Z
    // (scale-invariant, consistent with double-precision limits)
    if (cond_ZtZ == . | cond_ZtZ > 1e16) {
        errprintf("\nError 504: Z'Z matrix is numerically singular or ill-conditioned\n")
        errprintf("  cond(Z'Z) = %g (threshold: 1e16)\n", cond_ZtZ)
        errprintf("\nPossible causes:\n")
        errprintf("  1. Multicollinearity in instruments\n")
        errprintf("  2. Insufficient sample size (N=%g, K=%g)\n", N, cols(Z))
        errprintf("  3. Lack of variation after transition exclusion\n")
        exit(504)
    }

    // Warning only (do not abort)
    if (cond_ZtZ > 1e8) {
        printf("\nWarning: Z'Z condition number = %12.2e\n", cond_ZtZ)
        printf("  Results may have reduced numerical precision\n\n")
    }
    
    // ================================================================
    // One-step GMM weight matrix from the official DO implementation.
    // ================================================================
    W = invsym(ZtZ) / N
    
    // ================================================================
    // Recover current and lagged realized productivity implied by beta.
    // Phi has already had non-input controls removed upstream, so subtracting
    // X*beta here isolates the latent productivity term used in Theorem 3.1.
    // ================================================================
    OMEGA = PHI - X * betas'
    OMEGA_lag = PHI_LAG - X_lag * betas'
    
    // ================================================================
    // Build the lagged evolution basis used to approximate h_bar_0 and h_bar_1.
    // Interaction columns use lagged treatment status because the stable-state
    // moment condition conditions on D_t = D_{t-1}; the switching-period law
    // is intentionally left unidentified here.
    // ================================================================
    OMEGA_TP_lag = OMEGA_lag :* TP_lag
    
    if (omegapoly == 1) {
        // 4 columns: (1, omega_lag, omega_lag*D_lag, D_lag)
        OMEGA_LAG_POL = (C, OMEGA_lag, OMEGA_TP_lag, TP_lag)
    }
    else if (omegapoly == 2) {
        // 6 columns: add the quadratic untreated/treated evolution terms.
        OMEGA2_lag = OMEGA_lag :* OMEGA_lag
        OMEGA2_TP_lag = OMEGA2_lag :* TP_lag
        OMEGA_LAG_POL = (C, OMEGA_lag, OMEGA_TP_lag, OMEGA2_lag, OMEGA2_TP_lag, TP_lag)
    }
    else if (omegapoly == 3) {
        // 8 columns: add cubic terms for richer h_bar_d dynamics.
        OMEGA2_lag = OMEGA_lag :* OMEGA_lag
        OMEGA2_TP_lag = OMEGA2_lag :* TP_lag
        OMEGA3_lag = OMEGA2_lag :* OMEGA_lag
        OMEGA3_TP_lag = OMEGA3_lag :* TP_lag
        OMEGA_LAG_POL = (C, OMEGA_lag, OMEGA_TP_lag, OMEGA2_lag, OMEGA2_TP_lag, 
                        OMEGA3_lag, OMEGA3_TP_lag, TP_lag)
    }
    else if (omegapoly == 4) {
        // 10 columns: add quartic terms for the highest supported order.
        OMEGA2_lag = OMEGA_lag :* OMEGA_lag
        OMEGA2_TP_lag = OMEGA2_lag :* TP_lag
        OMEGA3_lag = OMEGA2_lag :* OMEGA_lag
        OMEGA3_TP_lag = OMEGA3_lag :* TP_lag
        OMEGA4_lag = OMEGA3_lag :* OMEGA_lag
        OMEGA4_TP_lag = OMEGA4_lag :* TP_lag
        OMEGA_LAG_POL = (C, OMEGA_lag, OMEGA_TP_lag, OMEGA2_lag, OMEGA2_TP_lag, 
                        OMEGA3_lag, OMEGA3_TP_lag, OMEGA4_lag, OMEGA4_TP_lag, TP_lag)
    }
    else {
        errprintf("Error: Invalid omegapoly value %g (expected 1, 2, 3, or 4)\n", omegapoly)
        exit(503)
    }
    
    // ================================================================
    // Concentrate out the evolution coefficients at every criterion evaluation.
    // This is the key reduction: optimize() searches over beta only, while g_b
    // is recomputed by closed-form OLS from the current implied productivity.
    // ================================================================
    OLtOL = cross(OMEGA_LAG_POL, OMEGA_LAG_POL)
    det_OLtOL = det(OLtOL)
    
    if (det_OLtOL < 1e-10) {
        // Fall back to a Moore-Penrose inverse when the OLS normal equations
        // are nearly singular instead of publishing explosive coefficients.
        g_b = pinv(OLtOL) * cross(OMEGA_LAG_POL, OMEGA)
    }
    else {
        // Standard closed-form OLS update.
        g_b = invsym(OLtOL) * cross(OMEGA_LAG_POL, OMEGA)
    }
    
    // ================================================================
    // Xi is the stable-state evolution residual; the criterion penalizes its
    // sample moments against the instrument set Z.
    // ================================================================
    XI = OMEGA - OMEGA_LAG_POL * g_b
    crit = (cross(Z, XI)' * W * cross(Z, XI))[1,1]
}


// ====================================================================
// Resolve starting values in the same order the ado layer promises users:
// explicit init() override, then live stored estimates, then package defaults.
// ====================================================================
real rowvector _pte_resolve_beta_init(string scalar prodfunc)
{
    real rowvector beta_init
    real scalar use_custom_init

    use_custom_init = strtoreal(st_local("use_custom_init"))
    if (use_custom_init == .) use_custom_init = 0

    if (use_custom_init == 1 & st_matrix("beta_init_custom") != J(0, 0, .)) {
        beta_init = st_matrix("beta_init_custom")
    }
    else if (prodfunc == "cd") {
        if (st_matrix("e(b)") != J(0, 0, .)) {
            beta_init = st_matrix("e(b)")[1, 1..2]
        }
        else {
            beta_init = (0.5, 0.5)
        }

        if (cols(beta_init) != 2) {
            errprintf("Error 503: CD initial values dimension mismatch\n")
            errprintf("  Expected: 2, Got: %g\n", cols(beta_init))
            exit(503)
        }

        if (missing(beta_init) > 0) {
            printf("Warning: CD initial values contain missing, using defaults (0.5, 0.5)\n")
            beta_init = (0.5, 0.5)
        }
    }
    else {
        if (st_matrix("beta0") != J(0, 0, .)) {
            beta_init = st_matrix("beta0")
        }
        else if (st_matrix("e(b)") != J(0, 0, .)) {
            beta_init = st_matrix("e(b)")[1, 1..5]
        }
        else {
            errprintf("Error 503: Translog initial values not found\n")
            errprintf("  Please provide beta0 matrix or run OLS regression first\n")
            exit(503)
        }

        if (cols(beta_init) != 5) {
            errprintf("Error 503: Translog initial values dimension mismatch\n")
            errprintf("  Expected: 5, Got: %g\n", cols(beta_init))
            exit(503)
        }

        if (missing(beta_init) > 0) {
            errprintf("Error 504: Initial values contain missing values\n")
            exit(504)
        }

        if (max(abs(beta_init)) > 10) {
            printf("Warning: Large initial values detected (max = %g)\n", max(abs(beta_init)))
        }
    }

    return(beta_init)
}

// ====================================================================
// Publish the selected optimizer path back to Stata scalars/matrices.
// ====================================================================
void _pte_store_result(struct OptimizationResult scalar result)
{
    st_matrix("beta", result.betas)
    st_numscalar("fval", result.fval)
    st_numscalar("converged", result.converged)
    st_numscalar("iterations", result.iterations)
}

// ====================================================================
// Display only the final path summary; detailed retries are printed upstream.
// ====================================================================
void _pte_report_result(struct OptimizationResult scalar result)
{
    real scalar i

    if (result.converged) {
        printf("\nGMM optimization converged successfully\n")
        printf("  Final criterion value: %g\n", result.fval)
        printf("  Parameters: ")
        for (i = 1; i <= cols(result.betas); i++) {
            printf("%9.6f ", result.betas[i])
        }
        printf("\n")
    }
    else {
        printf("\nWarning: GMM optimization did not converge\n")
        printf("  Final criterion value: %g\n", result.fval)
        printf("  Consider trying different starting values\n")
    }
}

// ====================================================================
// Single-start path that mirrors the lean reference workflow.
// ====================================================================
void MODEL_CLK()
{
    struct OptimizationResult scalar result
    real rowvector beta_init
    string scalar prodfunc
    real scalar maxiter, tol, is_translog

    prodfunc = st_local("prodfunc")
    maxiter = strtoreal(st_local("maxiter"))
    if (maxiter == . | maxiter <= 0) maxiter = 10000
    tol = strtoreal(st_local("tolerance"))
    if (tol == . | tol <= 0) tol = 1e-6
    is_translog = (prodfunc == "translog")

    beta_init = _pte_resolve_beta_init(prodfunc)
    result = pte_optimize_with_diagnostics(&GMM_CLK(), beta_init, maxiter, tol, 0.00001, 0, is_translog)

    _pte_store_result(result)
    _pte_report_result(result)
}

// ====================================================================
// Deterministic retry path used when the caller wants bounded fallback search.
// ====================================================================
void MODEL_CLK_grid()
{
    struct OptimizationResult scalar result
    real rowvector beta_init
    string scalar prodfunc
    real scalar maxiter, tol, is_translog

    prodfunc = st_local("prodfunc")
    maxiter = strtoreal(st_local("maxiter"))
    if (maxiter == . | maxiter <= 0) maxiter = 10000
    tol = strtoreal(st_local("tolerance"))
    if (tol == . | tol <= 0) tol = 1e-6
    is_translog = (prodfunc == "translog")

    beta_init = _pte_resolve_beta_init(prodfunc)
    result = pte_optimize_with_diagnostics(&GMM_CLK(), beta_init, maxiter, tol, 0.00001, 1, is_translog)

    _pte_store_result(result)
    _pte_report_result(result)
}

// ====================================================================
// Randomized retry path for harder surfaces where a fixed grid is too narrow.
// ====================================================================
void MODEL_CLK_multistart()
{
    transmorphic S
    struct OptimizationResult scalar result
    real rowvector init, beta_init
    real scalar try_num, max_tries, i
    string scalar prodfunc
    real scalar maxiter, tol

    prodfunc = st_local("prodfunc")
    maxiter = strtoreal(st_local("maxiter"))
    if (maxiter == . | maxiter <= 0) maxiter = 10000
    tol = strtoreal(st_local("tolerance"))
    if (tol == . | tol <= 0) tol = 1e-6
    max_tries = 5

    beta_init = _pte_resolve_beta_init(prodfunc)

    result.converged = 0
    result.fval = .
    result.iterations = 0
    result.betas = beta_init

    for (try_num = 1; try_num <= max_tries; try_num++) {
        S = optimize_init()
        optimize_init_evaluator(S, &GMM_CLK())
        optimize_init_evaluatortype(S, "d0")
        optimize_init_technique(S, "nm")
        optimize_init_conv_maxiter(S, maxiter)
        optimize_init_conv_nrtol(S, tol)
        optimize_init_which(S, "min")
        optimize_init_nmsimplexdeltas(S, 0.00001)

        if (try_num == 1) {
            init = beta_init
        }
        else if (try_num == 2) {
            init = J(1, cols(beta_init), 0)
        }
        else if (try_num == 3) {
            init = J(1, cols(beta_init), 0.3)
        }
        else {
            init = beta_init + runiform(1, cols(beta_init)) * 0.2 :- 0.1
        }

        optimize_init_params(S, init)
        result = pte_execute_optimization(S)

        if (result.converged) {
            printf("Converged at try %g with init = (", try_num)
            for (i = 1; i <= cols(init); i++) {
                printf("%g", init[i])
                if (i < cols(init)) printf(", ")
            }
            printf(")\n")
            break
        }
    }

    if (!result.converged) {
        errprintf("Error 430: GMM optimization failed to converge after %g tries\n", max_tries)
        exit(430)
    }

    _pte_store_result(result)
    _pte_report_result(result)
}

end
