*! _pte_tl_estimate.ado
*! Internal translog estimator for the baseline CLK path.
*! Keeps the mixed-lag instrument l1k_lag = L.lnl * lnk used in the paper,
*! so current capital remains paired with lagged labor in Z.

version 14.0
capture program drop _pte_tl_estimate
program define _pte_tl_estimate, eclass
    version 14.0

    // Parse the estimation contract before any helper-derived variables are read.
    syntax, depvar(name) free(name) state(name) proxy(name) ///
        treatment(name) [control(varlist) id(varname) t(varname) ///
        pooled by(varname) omegapoly(integer 3) maxiter(integer 10000) ///
        TOLerance(real 1e-6) INIT(numlist) GRID ///
        NODIAGnose NOLOG]

    // ----------------------------------------------------------------
    // 0a: Check xtset panel structure
    // ----------------------------------------------------------------
    capture _xt, trequired
    if _rc {
        di as error "{bf:_pte_tl_estimate}: data not xtset"
        di as error "  Please run: {bf:xtset} {it:panelvar timevar} before estimation"
        exit 459
    }

    // Retrieve panel variable names from xtset
    local panelvar "`r(ivar)'"
    local timevar "`r(tvar)'"

    // Override with user-specified id/t if provided
    if "`id'" != "" {
        local panelvar "`id'"
    }
    if "`t'" != "" {
        local timevar "`t'"
    }

    // ----------------------------------------------------------------
    // 0b: Validate all required variables exist and are numeric
    // ----------------------------------------------------------------
    foreach var in `depvar' `free' `state' `proxy' `treatment' {
        capture confirm variable `var', exact
        if _rc {
            di as error "{bf:_pte_tl_estimate}: variable {bf:`var'} not found"
            exit 111
        }
        capture confirm numeric variable `var'
        if _rc {
            di as error "{bf:_pte_tl_estimate}: variable {bf:`var'} is not numeric"
            exit 109
        }
    }

    // The transition helper may arrive under the package name or the legacy alias.
    local midvar "_pte_mid"
    capture confirm variable `midvar'
    if _rc {
        local midvar "mid"
        capture confirm variable `midvar'
        if _rc {
            di as error "{bf:_pte_tl_estimate}: neither {bf:_pte_mid} nor legacy {bf:mid} found"
            di as error "  Run {bf:_pte_transition} first"
            exit 111
        }
    }

    // ----------------------------------------------------------------
    // 0d: Validate treatment is binary (0/1)
    // ----------------------------------------------------------------
    qui count if !inlist(`treatment', 0, 1) & !mi(`treatment')
    if r(N) > 0 {
        di as error "{bf:_pte_tl_estimate}: treatment variable {bf:`treatment'} must be binary (0/1)"
        di as error "  Found `r(N)' non-binary observations"
        exit 450
    }

    // ----------------------------------------------------------------
    // 0e: Validate optional control variables
    // ----------------------------------------------------------------
    if "`control'" != "" {
        foreach var of local control {
            capture confirm variable `var'
            if _rc {
                di as error "{bf:_pte_tl_estimate}: control variable {bf:`var'} not found"
                exit 111
            }
        }
    }

    // ----------------------------------------------------------------
    // 0f: Validate by() variable if pooled mode
    // ----------------------------------------------------------------
    if "`by'" != "" {
        capture confirm variable `by'
        if _rc {
            di as error "{bf:_pte_tl_estimate}: by() variable {bf:`by'} not found"
            exit 111
        }
    }

    // by() is only admissible in by-industry mode when the estimation sample
    // has already been narrowed to one level.
    if "`pooled'" == "" & "`by'" != "" {
        local by_guard_vars "`depvar' `free' `state' `proxy' `treatment' `by'"
        if "`control'" != "" {
            local by_guard_vars "`by_guard_vars' `control'"
        }
        local by_guard_args : subinstr local by_guard_vars " " ", ", all
        quietly levelsof `by' if !missing(`by_guard_args'), ///
            local(by_levels)
        local n_by_levels : word count `by_levels'
        if `n_by_levels' == 0 {
            di as error "{bf:_pte_tl_estimate}: by() has no nonmissing levels in the estimation sample"
            exit 498
        }
        if `n_by_levels' > 1 {
            di as error "{bf:_pte_tl_estimate}: by-industry mode requires exactly one by() level in the estimation sample"
            di as error "  Current sample contains `n_by_levels' by() levels"
            di as error "  Either subset to one industry or add {bf:pooled}"
            exit 498
        }
    }

    // omegapoly changes only the productivity-law approximation, not the
    // translog input polynomial itself.
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "{bf:_pte_tl_estimate}: omegapoly must be between 1 and 4"
        di as error "  Specified: `omegapoly'"
        exit 198
    }


    // ================================================================
    // Log header
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "Translog Parameter Estimation"
        di as text "{hline 60}"
        di as text _col(3) "Dependent variable:" _col(40) as result "`depvar'"
        di as text _col(3) "Free variable (labor):" _col(40) as result "`free'"
        di as text _col(3) "State variable (capital):" _col(40) as result "`state'"
        di as text _col(3) "Proxy variable (materials):" _col(40) as result "`proxy'"
        di as text _col(3) "Treatment variable:" _col(40) as result "`treatment'"
        di as text _col(3) "Panel variable:" _col(40) as result "`panelvar'"
        di as text _col(3) "Time variable:" _col(40) as result "`timevar'"
        if "`pooled'" != "" {
            di as text _col(3) "Estimation mode:" _col(40) as result "pooled"
            if "`by'" != "" {
                di as text _col(3) "Industry variable:" _col(40) as result "`by'"
            }
        }
        else {
            di as text _col(3) "Estimation mode:" _col(40) as result "by-industry"
        }
        di as text _col(3) "Omega polynomial order:" _col(40) as result "`omegapoly'"
        di as text _col(3) "Max iterations:" _col(40) as result "`maxiter'"
        di as text "{hline 60}"
    }

    // Generate the fixed cubic proxy basis plus the mixed-lag instrument pieces
    // required by the translog moment stack.
    if "`nolog'" == "" {
        di as text ""
        di as text "Phase 1: Polynomial variable generation..."
    }

    _pte_polyvar, free(`free') proxy(`proxy') state(`state') ///
        pfunc(translog) poly(3) genlag

    local polyvars "`r(polyvars)'"
    local n_polyvars = r(n_polyvars)

    if "`nolog'" == "" {
        di as text "  Generated `n_polyvars' polynomial variables"
    }


    // Fit phi on the full sample. The pooled DO path omits l3/m3/k3 and uses
    // industry-specific grouped-time controls; the by-industry path uses one
    // grouped-time trend and retains the full cubic basis.
    if "`nolog'" == "" {
        di as text ""
        di as text "Phase 2: First-stage regression..."
    }

    // Determine control variables and estimation mode for _pte_stage1
    local stage1_opts "depvar(`depvar') pfunc(translog)"
    if "`control'" != "" {
        local stage1_opts "`stage1_opts' control(`control')"
    }

    if "`pooled'" != "" {
        // Pooled translog matches the DO design: one grouped-time interaction
        // per industry in place of a common trend.
        capture drop _pte_t
        qui egen _pte_t = group(`timevar')
        local t_vars ""
        if "`by'" != "" {
            qui levelsof `by', local(ind_levels)
            local num_ind : word count `ind_levels'
            tempvar _pte_by_group
            qui egen long `_pte_by_group' = group(`by') if !missing(`by')

            // Grouped time must match the scale used by the stage-1 and GMM helpers.
            capture drop _pte_t
            qui egen _pte_t = group(`timevar')

            // These controls are later removed from phi after prediction.
            local j = 0
            foreach ind_val of local ind_levels {
                local ++j
                capture drop _pte_t`j'
                qui gen double _pte_t`j' = _pte_t * (`_pte_by_group' == `j')
                label variable _pte_t`j' "PTE internal time trend for industry `ind_val'"
                local t_vars "`t_vars' _pte_t`j'"
            }

            if "`nolog'" == "" {
                di as text "  Generated `num_ind' industry time trends: `t_vars'"
            }
        }
        else {
            // Without by(), grouped time remains the only time control.
            local t_vars "_pte_t"
        }

        // _pte_stage1 interprets pooled mode from the absence of byindustry.
        local stage1_opts "`stage1_opts' tvars(`t_vars')"
    }
    else {
        // By-industry translog uses one grouped-time control, matching the
        // industry-specific DO estimator.
        capture drop _pte_t
        qui egen _pte_t = group(`timevar')
        label variable _pte_t "PTE internal time trend (grouped)"
        local stage1_opts "`stage1_opts' tvars(_pte_t) byindustry"
    }

    // Diagnostics are optional but should stay attached to the same stage-1 call.
    if "`nodiagnose'" != "" {
        local stage1_opts "`stage1_opts' nodiagnose"
    }

    // Transition rows remain in stage 1 and are filtered only in GMM.
    _pte_stage1, `stage1_opts'

    // Later helpers reuse r(), so save stage-1 results immediately.
    local r2_stage1 = r(r2_stage1)
    local n_stage1 = r(n_stage1)
    local stage1_ctrl_names : colnames r(beta_controls)
    tempname stage1_beta_controls
    matrix `stage1_beta_controls' = r(beta_controls)
    matrix colnames `stage1_beta_controls' = `stage1_ctrl_names'
    local beta_t = .
    local beta_t_col : list posof "t" in stage1_ctrl_names
    if `beta_t_col' < 1 {
        local beta_t_col : list posof "_pte_t" in stage1_ctrl_names
    }
    if `beta_t_col' >= 1 {
        local beta_t = `stage1_beta_controls'[1, `beta_t_col']
    }

    if "`nolog'" == "" {
        di as text "  First-stage R-squared: " as result %8.4f `r2_stage1'
        di as text "  First-stage N: " as result %8.0fc `n_stage1'
    }


    // ================================================================
    // Phase 3: GMM matrix construction
    //
    // Translog-specific matrices:
    //   X:     N x 5 (lnl, lnk, l2, k2, l1k1)
    //   X_lag: N x 5 (lnl_lag, lnk_lag, l2_lag, k2_lag, l1k1_lag)
    //   Z:     N x 7 (const, lnl_lag, lnk, l2_lag, k2, l1k_lag, t)
    //
    // CRITICAL: l1k_lag = L.lnl * lnk (mixed-lag, NOT L.lnl * L.lnk)
    //   Capital is state variable (decided at t-1), so current lnk in Z
    //
    // OMEGA_LAG_POL: 2 + 2*omegapoly columns (default 8 for omegapoly=3)
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "Phase 3: GMM matrix construction..."
    }

    _pte_gmm_matrices, phi(phi) lnl(`free') lnk(`state') ///
        treatpost(`treatment') mid(`midvar') t(_pte_t) ///
        id(`panelvar') time(`timevar') prodfunc(translog) ///
        omegapoly(`omegapoly') lsq(l2) ksq(k2) lk(l1k1)

    // Capture GMM matrix results
    local N_gmm = r(N)
    local cols_X = r(cols_X)
    local cols_Z = r(cols_Z)
    local cols_OLP = r(cols_OLP)
    local cond_ZZ = r(cond_ZZ)

    if "`nolog'" == "" {
        di as text "  GMM sample size: " as result %8.0fc `N_gmm'
        di as text "  X matrix columns: " as result `cols_X' " (expected 5)"
        di as text "  Z matrix columns: " as result `cols_Z' " (expected 7)"
        di as text "  OMEGA_LAG_POL columns: " as result `cols_OLP'
    }

    // Validate matrix dimensions
    if `cols_X' != 5 {
        di as error "{bf:_pte_tl_estimate}: X matrix has `cols_X' columns (expected 5)"
        exit 503
    }
    if `cols_Z' != 7 {
        di as error "{bf:_pte_tl_estimate}: Z matrix has `cols_Z' columns (expected 7)"
        exit 503
    }

    // Minimum sample size check
    if `N_gmm' < 50 {
        di as error "{bf:_pte_tl_estimate}: insufficient observations for GMM estimation"
        di as error "  GMM sample size: `N_gmm' (minimum: 50)"
        di as error "  Check data or transition period exclusion"
        exit 2001
    }


    // ================================================================
    // Phase 4: OLS initial values for GMM
    //
    // CRITICAL: Translog uses beta0 matrix (not e(b) directly)
    //   MODEL_CLK() reads st_matrix("beta0") for Translog
    //
    // OLS regression: depvar on lnl lnk l2 k2 l1k1 + controls
    // Extract first 5 coefficients as initial values
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "Phase 4: OLS initial values..."
    }

    // Verify Translog variables exist (from Phase 1)
    foreach var in l2 k2 l1k1 {
        capture confirm variable `var'
        if _rc {
            di as error "{bf:_pte_tl_estimate}: variable {bf:`var'} not found"
            di as error "  Phase 1 (polynomial generation) may have failed"
            exit 111
        }
    }

    local ols_controls ""
    if "`pooled'" != "" {
        // Pooled mode: include industry time trends in OLS
        if "`by'" != "" {
            local ols_controls "`t_vars'"
        }
        else {
            local ols_controls "_pte_t"
        }
    }
    else {
        // By-industry mode: simple OLS with time trend
        local ols_controls "_pte_t"
    }
    if "`control'" != "" {
        local ols_controls "`ols_controls' `control'"
        local ols_controls : list uniq ols_controls
    }
    qui reg `depvar' `free' `state' l2 k2 l1k1 `ols_controls'

    // Extract first 5 coefficients as beta0 (excluding controls and constant)
    // Order: beta_l, beta_k, beta_ll, beta_kk, beta_lk
    matrix beta0 = e(b)[1, 1..5]

    // Extract individual initial values for logging
    local beta_l_init  = beta0[1,1]
    local beta_k_init  = beta0[1,2]
    local beta_ll_init = beta0[1,3]
    local beta_kk_init = beta0[1,4]
    local beta_lk_init = beta0[1,5]

    if "`nolog'" == "" {
        di as text "  OLS initial beta_l:  " as result %10.6f `beta_l_init'
        di as text "  OLS initial beta_k:  " as result %10.6f `beta_k_init'
        di as text "  OLS initial beta_ll: " as result %10.6f `beta_ll_init'
        di as text "  OLS initial beta_kk: " as result %10.6f `beta_kk_init'
        di as text "  OLS initial beta_lk: " as result %10.6f `beta_lk_init'
    }

    // Validate initial values are not missing
    forvalues i = 1/5 {
        if missing(beta0[1, `i']) {
            di as error "{bf:_pte_tl_estimate}: OLS initial value `i' is missing"
            di as error "  Check for multicollinearity in input variables"
            exit 504
        }
    }


    // ================================================================
    // Phase 5: GMM optimization (Nelder-Mead)
    //
    // _pte_gmm_wrapper calls MODEL_CLK() in Mata which:
    //   1. Reads st_matrix("beta0") as initial values (set in Phase 4)
    //   2. Configures Nelder-Mead optimizer (simplex_deltas = 0.00001)
    //   3. Runs optimization with GMM_CLK() evaluator
    //   4. Stores results: beta matrix, fval scalar, converged scalar
    //
    // Translog: 5 parameters optimized simultaneously
    // OMEGA_LAG_POL: 2 + 2*omegapoly columns (default 8)
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "Phase 5: GMM optimization..."
    }

    // Build wrapper options
    local wrapper_opts "prodfunc(translog) omegapoly(`omegapoly') maxiter(`maxiter') tolerance(`tolerance')"
    if "`init'" != "" {
        local wrapper_opts "`wrapper_opts' init(`init')"
    }
    if "`grid'" != "" {
        local wrapper_opts "`wrapper_opts' grid"
    }
    if "`nolog'" != "" {
        local wrapper_opts "`wrapper_opts' nolog"
    }

    _pte_gmm_wrapper, `wrapper_opts'

    // Capture GMM results
    matrix _pte_beta = r(beta)
    local fval = r(fval)
    local converged = r(converged)
    local iterations = r(iterations)

    // Extract individual parameters
    local beta_l  = _pte_beta[1,1]
    local beta_k  = _pte_beta[1,2]
    local beta_ll = _pte_beta[1,3]
    local beta_kk = _pte_beta[1,4]
    local beta_lk = _pte_beta[1,5]

    if "`nolog'" == "" {
        di as text "  GMM beta_l:  " as result %10.6f `beta_l'
        di as text "  GMM beta_k:  " as result %10.6f `beta_k'
        di as text "  GMM beta_ll: " as result %10.6f `beta_ll'
        di as text "  GMM beta_kk: " as result %10.6f `beta_kk'
        di as text "  GMM beta_lk: " as result %10.6f `beta_lk'
        di as text "  Objective value: " as result %12.8e `fval'
        di as text "  Iterations: " as result %8.0f `iterations'
        di as text "  Converged: " as result cond(`converged', "Yes", "No")
    }


    // ================================================================
    // Phase 6: Parameter validation and e() storage
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "Phase 6: Parameter validation and storage..."
    }

    // ----------------------------------------------------------------
    // 6a: Parameter range warnings (do not abort)
    // Translog parameters have wider valid ranges than CD
    // ----------------------------------------------------------------
    if abs(`beta_l') > 5 {
        di as text "{bf:Warning}: beta_l = " %9.6f `beta_l' " has large magnitude"
    }
    if abs(`beta_k') > 5 {
        di as text "{bf:Warning}: beta_k = " %9.6f `beta_k' " has large magnitude"
    }

    // ----------------------------------------------------------------
    // 6b: Construct e(b) only
    // e(V) is intentionally omitted because this estimator does not yet
    // release an inferential covariance matrix.
    // ----------------------------------------------------------------
    tempname b

    matrix `b' = (`beta_l', `beta_k', `beta_ll', `beta_kk', `beta_lk')
    matrix colnames `b' = `free' `state' `free'_sq `state'_sq `free'_`state'

    // ----------------------------------------------------------------
    // 6c: Post results via ereturn
    // ----------------------------------------------------------------
    tempvar _pte_tl_sort _pte_tl_gap _pte_tl_delta_probe _pte_tl_esample
    qui gen long `_pte_tl_sort' = _n
    qui sort `panelvar' `timevar'
    qui by `panelvar' (`timevar'): gen double `_pte_tl_delta_probe' = ///
        `timevar' - `timevar'[_n-1] if _n > 1 & !mi(`timevar', `timevar'[_n-1])
    qui summarize `_pte_tl_delta_probe' if `_pte_tl_delta_probe' > 0, meanonly
    local _tl_tsdelta = r(min)
    if missing(`_tl_tsdelta') | `_tl_tsdelta' <= 0 {
        local _tl_tsdelta = 1
    }
    local _tl_tsdelta_tol = max(1e-10, abs(`_tl_tsdelta') * 1e-10)

    qui by `panelvar' (`timevar'): gen byte `_pte_tl_gap' = ///
        (abs((`timevar' - `timevar'[_n-1]) - `_tl_tsdelta') > `_tl_tsdelta_tol') if _n > 1
    qui by `panelvar' (`timevar'): replace `_pte_tl_gap' = 1 if _n == 1

    qui gen byte `_pte_tl_esample' = (`midvar' == 0)
    qui replace `_pte_tl_esample' = 0 if `_pte_tl_gap' == 1
    qui replace `_pte_tl_esample' = 0 if ///
        mi(phi) | mi(phi[_n-1]) | ///
        mi(`free') | mi(`free'[_n-1]) | ///
        mi(`state') | mi(`state'[_n-1]) | ///
        mi(`treatment') | mi(`treatment'[_n-1]) | ///
        mi(_pte_t) | ///
        mi(l2) | mi(l2[_n-1]) | ///
        mi(k2) | mi(k2[_n-1]) | ///
        mi(l1k1) | mi(l1k1[_n-1])
    qui sort `_pte_tl_sort'
    qui count if `_pte_tl_esample'
    local _N_post = r(N)

    ereturn post `b', esample(`_pte_tl_esample') obs(`_N_post')

    // Scalars
    ereturn scalar N = `N_gmm'
    ereturn scalar converged = `converged'
    ereturn scalar fval = `fval'
    ereturn scalar criterion = `fval'
    ereturn scalar iterations = `iterations'
    ereturn scalar r2_stage1 = `r2_stage1'
    ereturn scalar n_stage1 = `n_stage1'
    ereturn scalar rts = `beta_l' + `beta_k'
    ereturn scalar beta_l = `beta_l'
    ereturn scalar beta_k = `beta_k'
    ereturn scalar beta_ll = `beta_ll'
    ereturn scalar beta_kk = `beta_kk'
    ereturn scalar beta_lk = `beta_lk'
    ereturn scalar beta_t = `beta_t'
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar cols_X = `cols_X'
    ereturn scalar cols_Z = `cols_Z'
    ereturn scalar cols_OLP = `cols_OLP'
    ereturn scalar cond_ZZ = `cond_ZZ'

    // Macros
    ereturn local cmd "pte"
    ereturn local subcmd "tl_estimate"
    ereturn local pfunc "translog"
    ereturn local depvar "`depvar'"
    ereturn local free "`free'"
    ereturn local state "`state'"
    ereturn local proxy "`proxy'"
    ereturn local treatment "`treatment'"
    ereturn local panelvar "`panelvar'"
    ereturn local timevar "`timevar'"
    if "`pooled'" != "" {
        ereturn local mode "pooled"
        if "`by'" != "" {
            ereturn local byvar "`by'"
        }
    }
    else {
        ereturn local mode "by-industry"
    }

    // Store the full beta matrix from GMM (for downstream modules)
    ereturn matrix beta_gmm = _pte_beta


    // ================================================================
    // Phase 7: Results summary output
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "Translog Estimation Results"
        di as text "{hline 60}"
        di as text ""
        di as text _col(3) "Sample Information:"
        di as text _col(5) "First-stage observations:" _col(40) as result %10.0fc `n_stage1'
        di as text _col(5) "GMM observations:" _col(40) as result %10.0fc `N_gmm'
        di as text _col(5) "First-stage R-squared:" _col(40) as result %10.4f `r2_stage1'
        di as text ""
        di as text _col(3) "GMM Optimization:"
        di as text _col(5) "Objective function value:" _col(40) as result %12.8e `fval'
        di as text _col(5) "Converged:" _col(40) as result cond(`converged', "Yes", "No")
        di as text _col(5) "Omega polynomial order:" _col(40) as result `omegapoly'
        di as text _col(5) "Z'Z condition number:" _col(40) as result %12.4e `cond_ZZ'
        di as text ""
        di as text _col(3) "Parameter Estimates:"
        di as text _col(5) "beta_l  (labor):" _col(40) as result %10.6f `beta_l'
        di as text _col(5) "beta_k  (capital):" _col(40) as result %10.6f `beta_k'
        di as text _col(5) "beta_ll (labor^2):" _col(40) as result %10.6f `beta_ll'
        di as text _col(5) "beta_kk (capital^2):" _col(40) as result %10.6f `beta_kk'
        di as text _col(5) "beta_lk (labor*capital):" _col(40) as result %10.6f `beta_lk'
        if !missing(`beta_t') {
            di as text _col(5) "beta_t  (time trend):" _col(40) as result %10.6f `beta_t'
        }
        di as text ""
        di as text "{hline 60}"
        di as text ""
    }

end
