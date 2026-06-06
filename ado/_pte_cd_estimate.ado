*! _pte_cd_estimate.ado
*! Internal Cobb-Douglas estimator for the baseline CLK production-function path.
*! Accepts an optional precomputed phi so pooled stage-1 fits can be reused on
*! subset-specific GMM runs, matching the replication workflow.

version 14.0
capture program drop _pte_cd_estimate
program define _pte_cd_estimate, eclass
    version 14.0

    // Parse inputs before inspecting the panel state or helper variables.
    local _pte_cd_raw_opts `"`0'"'
    syntax [if] [in], depvar(name) free(name) state(name) proxy(name) ///
        treatment(name) [control(varlist) id(varname) t(varname) ///
        pooled by(varname) omegapoly(integer 1) maxiter(integer 10000) ///
        TOLerance(real 1e-6) INIT(numlist) GRID ///
        phi(varname) NODIAGnose NOLOG TOUSE(varname)]

    // ----------------------------------------------------------------
    // 0a: Check xtset panel structure
    // ----------------------------------------------------------------
    capture _xt, trequired
    if _rc {
        di as error "{bf:_pte_cd_estimate}: data not xtset"
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
    unab _pte_cd_allvars : _all

    // ----------------------------------------------------------------
    // 0b: Validate all required variables exist and are numeric
    // ----------------------------------------------------------------
    foreach var in `depvar' `free' `state' `proxy' `treatment' {
        local _pte_cd_has_required : list posof "`var'" in _pte_cd_allvars
        if !`_pte_cd_has_required' {
            di as error "{bf:_pte_cd_estimate}: variable {bf:`var'} not found"
            exit 111
        }
        capture confirm numeric variable `var'
        if _rc {
            di as error "{bf:_pte_cd_estimate}: variable {bf:`var'} is not numeric"
            exit 109
        }
    }

    marksample _pte_cd_ifin, novarlist
    tempvar _pte_cd_sample
    qui gen byte `_pte_cd_sample' = (`_pte_cd_ifin' != 0 & !missing(`_pte_cd_ifin'))
    if "`touse'" != "" {
        capture confirm variable `touse', exact
        if _rc {
            di as error "{bf:_pte_cd_estimate}: touse variable {bf:`touse'} not found"
            exit 111
        }
        capture confirm numeric variable `touse'
        if _rc {
            di as error "{bf:_pte_cd_estimate}: touse variable {bf:`touse'} must be numeric"
            exit 109
        }
        qui replace `_pte_cd_sample' = 0 if `touse' == 0 | missing(`touse')
    }
    markout `_pte_cd_sample' `depvar' `free' `state' `proxy' `treatment'

    // The transition helper may arrive under the package name or the legacy alias.
    local _pte_cd_has_mid : list posof "_pte_mid" in _pte_cd_allvars
    local _pte_cd_has_legacy_mid : list posof "mid" in _pte_cd_allvars
    if `_pte_cd_has_mid' {
        local midvar "_pte_mid"
    }
    else if `_pte_cd_has_legacy_mid' {
        local midvar "mid"
    }
    else {
        di as error "{bf:_pte_cd_estimate}: neither {bf:_pte_mid} nor legacy {bf:mid} found"
        di as error "  Run {bf:_pte_transition} first"
        exit 111
    }

    // ----------------------------------------------------------------
    // 0d: Validate treatment is binary (0/1)
    // ----------------------------------------------------------------
    qui count if `_pte_cd_sample' & !inlist(`treatment', 0, 1) & !mi(`treatment')
    if r(N) > 0 {
        di as error "{bf:_pte_cd_estimate}: treatment variable {bf:`treatment'} must be binary (0/1)"
        di as error "  Found `r(N)' non-binary observations"
        exit 450
    }

    // Theorem 3.1 requires transition periods to be computed from the same
    // treatment path consumed by this production-function call.
    capture noisily _pte_validate_mid_contract, midvar(`midvar') ///
        treatment(`treatment') panelvar(`panelvar') timevar(`timevar') ///
        touse(`_pte_cd_sample') context("_pte_cd_estimate")
    if _rc != 0 {
        local _pte_mid_contract_rc = _rc
        exit `_pte_mid_contract_rc'
    }

    // ----------------------------------------------------------------
    // 0e: Validate optional control variables
    // ----------------------------------------------------------------
    if "`control'" != "" {
        local _pte_cd_control_literal ""
        if regexm(`"`_pte_cd_raw_opts'"', "(^|[ ,])control[ ]*[(]([^)]*)[)]") {
            local _pte_cd_control_literal `"`=strtrim(regexs(2))'"'
        }
        if `"`_pte_cd_control_literal'"' != "" {
            foreach var of local _pte_cd_control_literal {
                local _pte_cd_has_control : list posof "`var'" in _pte_cd_allvars
                if !`_pte_cd_has_control' {
                    di as error "{bf:_pte_cd_estimate}: control variable {bf:`var'} not found"
                    exit 111
                }
            }
        }
        foreach var of local control {
            capture confirm variable `var', exact
            if _rc {
                di as error "{bf:_pte_cd_estimate}: control variable {bf:`var'} not found"
                exit 111
            }
        }
        markout `_pte_cd_sample' `control'
    }

    // ----------------------------------------------------------------
    // 0f: Validate by() variable if pooled mode
    // ----------------------------------------------------------------
    if "`by'" != "" {
        local _pte_cd_by_literal ""
        if regexm(`"`_pte_cd_raw_opts'"', "(^|[ ,])by[ ]*[(]([^)]*)[)]") {
            local _pte_cd_by_literal `"`=strtrim(regexs(2))'"'
        }
        if `"`_pte_cd_by_literal'"' != "" & `"`_pte_cd_by_literal'"' != `"`by'"' {
            local _pte_cd_has_by_literal : list posof "`_pte_cd_by_literal'" in _pte_cd_allvars
            if !`_pte_cd_has_by_literal' {
                di as error "{bf:_pte_cd_estimate}: by() variable {bf:`_pte_cd_by_literal'} not found"
                exit 111
            }
        }
        capture confirm variable `by', exact
        if _rc {
            di as error "{bf:_pte_cd_estimate}: by() variable {bf:`by'} not found"
            exit 111
        }
        markout `_pte_cd_sample' `by'
    }

    // by() is only admissible in by-industry mode when the active sample has
    // already been narrowed to one level.
    if "`pooled'" == "" & "`by'" != "" {
        local by_guard_vars "`depvar' `free' `state' `proxy' `treatment' `by'"
        if "`control'" != "" {
            local by_guard_vars "`by_guard_vars' `control'"
        }
        local by_guard_args : subinstr local by_guard_vars " " ", ", all
        quietly levelsof `by' if `_pte_cd_sample' & !missing(`by_guard_args'), ///
            local(by_levels)
        local n_by_levels : word count `by_levels'
        if `n_by_levels' == 0 {
            di as error "{bf:_pte_cd_estimate}: by() has no nonmissing levels in the estimation sample"
            exit 498
        }
        if `n_by_levels' > 1 {
            di as error "{bf:_pte_cd_estimate}: by-industry mode requires exactly one by() level in the estimation sample"
            di as error "  Current sample contains `n_by_levels' by() levels"
            di as error "  Either subset to one industry or add {bf:pooled}"
            exit 498
        }
    }

    // omegapoly controls the law of motion for recovered productivity only; it
    // does not change the Cobb-Douglas functional form or the fixed stage-1 basis.

    capture drop _pte_t
    qui egen double _pte_t = group(`timevar')
    label variable _pte_t "PTE internal time trend (grouped)"

    local t_vars ""
    if "`pooled'" != "" {
        if "`by'" != "" {
            qui levelsof `by', local(ind_levels)
            local num_ind : word count `ind_levels'
            tempvar _pte_by_group
            qui egen long `_pte_by_group' = group(`by') if !missing(`by')

            // Reuse the same grouped-time controls in both the internal stage-1
            // path and the optional phi() bridge.
            local j = 0
            foreach ind_val of local ind_levels {
                local ++j
                capture drop _pte_t`j'
                qui gen double _pte_t`j' = _pte_t * (`_pte_by_group' == `j')
                label variable _pte_t`j' "PTE internal time trend for industry `ind_val'"
                local t_vars "`t_vars' _pte_t`j'"
            }
        }
        else {
            local t_vars "_pte_t"
        }
    }


    // ================================================================
    // Log header
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "Cobb-Douglas Parameter Estimation"
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

    // Stage 1 may be skipped when phi() already contains the full-sample proxy
    // fit reused by downstream subset-specific GMM runs.

    if "`phi'" != "" {
        // The caller owns the first-stage regression in phi() mode.
        if "`nolog'" == "" {
            di as text ""
            di as text "Phase 1-2: Using pre-computed phi variable: `phi'"
        }

        // phi must be numeric because it enters Mata matrix assembly directly.
        capture confirm numeric variable `phi'
        if _rc {
            di as error "{bf:_pte_cd_estimate}: phi variable {bf:`phi'} is not numeric"
            exit 109
        }

        // Stage-1 fit statistics are unavailable when phi was supplied.
        local r2_stage1 = .
        local n_stage1 = .

        if "`nolog'" == "" {
            qui summarize `phi', meanonly
            di as text "  phi mean: " as result %10.4f r(mean) as text "  N: " as result r(N)
        }
    }
    else {
        // Standard mode reproduces the DO sequence: generate the fixed proxy basis,
        // estimate phi on the full sample, then hand stable rows to GMM.

        // Use the fixed cubic proxy basis from the paper/DO implementation.
        if "`nolog'" == "" {
            di as text ""
            di as text "Phase 1: Polynomial variable generation..."
        }

        _pte_polyvar, free(`free') proxy(`proxy') state(`state') ///
            pfunc(cd) poly(3) genlag

        local polyvars "`r(polyvars)'"
        local n_polyvars = r(n_polyvars)

        if "`nolog'" == "" {
            di as text "  Generated `n_polyvars' polynomial variables"
        }


        // Fit phi on the full sample; transition rows are excluded only when the
        // moment-condition matrices are formed.
        //
        // By-industry mode: reg lny l1* m1* k1* k2 l2 m2 k3 l3 m3 t
        //   -> 19 poly vars + 1 control (t)
        // Pooled mode: generate t1-tJ, then reg lny l1* m1* k1* k2* l2* m2* k3 l3 m3 t1-tJ
        //   -> 19 poly vars + J controls (t1..tJ)
        //
        // _pte_stage1 handles the distinction internally via byindustry option.
        // After this phase: phi and phi_raw variables exist in the dataset.
        // ================================================================
        if "`nolog'" == "" {
            di as text ""
            di as text "Phase 2: First-stage regression..."
        }

        // Determine control variables and estimation mode for _pte_stage1
        local stage1_opts "depvar(`depvar') pfunc(cd)"
        if "`control'" != "" {
            local stage1_opts "`stage1_opts' control(`control')"
        }

        if "`pooled'" != "" {
            // ============================================================
            // Pooled mode: generate industry-specific time trends t1-tJ
            //   forv j=1/J { g t`j' = t*(indid_adj==`j') }
            // These must exist BEFORE calling _pte_stage1 and must also be
            // reused by the pooled phi() bridge in phase 4.
            //
            // CRITICAL: Replication code uses t = group(year) (values 1-15),
            // NOT raw year values (2005-2019). Using raw year causes phi
            // subtraction to produce wildly wrong values (phi mean ~ -76
            // instead of ~19). We must use grouped time for the trends.
            // ============================================================
            if "`by'" != "" {
                if "`nolog'" == "" {
                    di as text "  Generated `num_ind' industry time trends: `t_vars'"
                }
            }
            else {
                // Pooled without by(): use the internal grouped time trend
                local t_vars "_pte_t"
            }

            // Pooled mode: no byindustry option, internal time controls via tvars()
            local stage1_opts "`stage1_opts' tvars(`t_vars')"
        }
        else {
            // ============================================================
            // By-industry mode: use simple time trend t as control
            //
            // CRITICAL: Replication code uses t = group(year) (values 1-15),
            // NOT raw year values. Must use grouped time for consistency.
            // ============================================================
            local stage1_opts "`stage1_opts' tvars(_pte_t) byindustry"
        }

        // Add diagnostic options
        if "`nodiagnose'" != "" {
            local stage1_opts "`stage1_opts' nodiagnose"
        }

        // Execute first-stage regression
        local stage1_opts "`stage1_opts' touse(`_pte_cd_sample')"
        _pte_stage1, `stage1_opts'

        // Capture first-stage results before they are overwritten
        local r2_stage1 = r(r2_stage1)
        local n_stage1 = r(n_stage1)

        if "`nolog'" == "" {
            di as text "  First-stage R-squared: " as result %8.4f `r2_stage1'
            di as text "  First-stage N: " as result %8.0fc `n_stage1'
        }
    } // end of standard mode (no phi)


    // ================================================================
    // Phase 3: GMM matrix construction
    //
    // _pte_gmm_matrices internally:
    //   1. preserve
    //   2. Generate lag variables (phi_lag, lnl_lag, lnk_lag, etc.)
    //   3. Drop first-period obs (_n==1) and transitions (mid==1)
    //   4. Construct Mata global matrices (X, X_lag, Z, W, PHI, etc.)
    //   5. restore
    //
    // After this phase: Mata globals are set, data is back to original.
    // IMPORTANT: GMM Z must use the same grouped time object as stage 1/OLS,
    // matching the reference workflow's t = group(year) convention.
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "Phase 3: GMM matrix construction..."
    }

    // Determine phi variable name for GMM matrices
    local phi_var "phi"
    if "`phi'" != "" {
        local phi_var "`phi'"
    }

    _pte_gmm_matrices, phi(`phi_var') lnl(`free') lnk(`state') ///
        treatpost(`treatment') mid(`midvar') t(_pte_t) ///
        id(`panelvar') time(`timevar') prodfunc(cd) omegapoly(`omegapoly') ///
        gmmsample(`_pte_cd_sample')

    // Capture GMM matrix results
    local N_gmm = r(N)
    local cols_X = r(cols_X)
    local cols_Z = r(cols_Z)
    local cols_OLP = r(cols_OLP)
    local cond_ZZ = r(cond_ZZ)

    if "`nolog'" == "" {
        di as text "  GMM sample size: " as result %8.0fc `N_gmm'
    }

    // Minimum sample size check
    if `N_gmm' < 50 {
        di as error "{bf:_pte_cd_estimate}: insufficient observations for GMM estimation"
        di as error "  GMM sample size: `N_gmm' (minimum: 50)"
        di as error "  Check data or transition period exclusion"
        exit 2001
    }


    // ================================================================
    // Phase 4: OLS initial values for GMM
    //
    // CRITICAL TIMING: This OLS regression must be the LAST regression
    // before calling _pte_gmm_wrapper, because MODEL_CLK() reads
    // e(b)[1, 1..2] as initial values for the optimizer.
    //
    // _pte_gmm_matrices uses preserve/restore, so e() is preserved.
    // But to be safe, we run OLS AFTER _pte_gmm_matrices returns.
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "Phase 4: OLS initial values..."
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
    qui reg `depvar' `free' `state' `ols_controls' if `_pte_cd_sample'

    // Extract OLS initial values for logging
    local beta_l_init = _b[`free']
    local beta_k_init = _b[`state']

    if "`nolog'" == "" {
        di as text "  OLS initial beta_l: " as result %10.6f `beta_l_init'
        di as text "  OLS initial beta_k: " as result %10.6f `beta_k_init'
    }

    // Validate OLS initial values are reasonable
    if `beta_l_init' <= 0 | `beta_l_init' >= 2 {
        if "`nolog'" == "" {
            di as text "  {bf:Note}: OLS beta_l = " %9.6f `beta_l_init' " outside typical range (0, 2)"
        }
    }
    if `beta_k_init' <= 0 | `beta_k_init' >= 2 {
        if "`nolog'" == "" {
            di as text "  {bf:Note}: OLS beta_k = " %9.6f `beta_k_init' " outside typical range (0, 2)"
        }
    }


    // ================================================================
    // Phase 5: GMM optimization (Nelder-Mead)
    //
    // _pte_gmm_wrapper calls MODEL_CLK() in Mata which:
    //   1. Reads e(b)[1, 1..2] as initial values (set in Phase 4)
    //   2. Configures Nelder-Mead optimizer (simplex_deltas = 0.00001)
    //   3. Runs optimization with GMM_CLK() evaluator
    //   4. Stores results: beta matrix, fval scalar, converged scalar
    //
    // _pte_gmm_wrapper reads Stata locals `prodfunc' and `omegapoly'
    // which are set by its own syntax parsing.
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "Phase 5: GMM optimization..."
    }

    // Build wrapper options
    local wrapper_opts "prodfunc(cd) omegapoly(`omegapoly') maxiter(`maxiter') tolerance(`tolerance')"
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
    local beta_l = _pte_beta[1,1]
    local beta_k = _pte_beta[1,2]
    local rts = `beta_l' + `beta_k'

    if "`nolog'" == "" {
        di as text "  GMM beta_l: " as result %10.6f `beta_l'
        di as text "  GMM beta_k: " as result %10.6f `beta_k'
        di as text "  Returns to scale: " as result %10.6f `rts'
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
    // 6a: Parameter range validation (warnings only, do not abort)
    // ----------------------------------------------------------------
    if `beta_l' <= 0 | `beta_l' >= 1 {
        di as text "{bf:Warning}: beta_l = " %9.6f `beta_l' " outside typical range (0, 1)"
    }
    if `beta_k' <= 0 | `beta_k' >= 1 {
        di as text "{bf:Warning}: beta_k = " %9.6f `beta_k' " outside typical range (0, 1)"
    }
    if `rts' <= 0.5 | `rts' >= 1.2 {
        di as text "{bf:Warning}: Returns to scale = " %9.6f `rts' " outside typical range (0.5, 1.2)"
    }

    // ----------------------------------------------------------------
    // 6b: Construct e(b) only
    // e(V) is intentionally omitted because this estimator does not yet
    // release an inferential covariance matrix.
    // ----------------------------------------------------------------
    tempname b

    matrix `b' = (`beta_l', `beta_k')
    matrix colnames `b' = `free' `state'

    // ----------------------------------------------------------------
    // 6c: Post results via ereturn
    // ----------------------------------------------------------------
    tempvar _pte_cd_sort _pte_cd_gap _pte_cd_delta_probe _pte_cd_esample
    qui gen long `_pte_cd_sort' = _n
    qui sort `panelvar' `timevar'
    qui by `panelvar' (`timevar'): gen double `_pte_cd_delta_probe' = ///
        `timevar' - `timevar'[_n-1] if _n > 1 & !mi(`timevar', `timevar'[_n-1])
    qui summarize `_pte_cd_delta_probe' if `_pte_cd_delta_probe' > 0, meanonly
    local _cd_tsdelta = r(min)
    if missing(`_cd_tsdelta') | `_cd_tsdelta' <= 0 {
        local _cd_tsdelta = 1
    }
    local _cd_tsdelta_tol = max(1e-10, abs(`_cd_tsdelta') * 1e-10)

    qui by `panelvar' (`timevar'): gen byte `_pte_cd_gap' = ///
        (abs((`timevar' - `timevar'[_n-1]) - `_cd_tsdelta') > `_cd_tsdelta_tol') if _n > 1
    qui by `panelvar' (`timevar'): replace `_pte_cd_gap' = 1 if _n == 1
    qui by `panelvar' (`timevar'): replace `_pte_cd_gap' = 1 if _n > 1 & ///
        (`_pte_cd_sample'[_n-1] == 0 | missing(`_pte_cd_sample'[_n-1]))

    qui gen byte `_pte_cd_esample' = (`_pte_cd_sample' & `midvar' == 0)
    qui replace `_pte_cd_esample' = 0 if `_pte_cd_gap' == 1
    qui replace `_pte_cd_esample' = 0 if ///
        mi(`phi_var') | mi(`phi_var'[_n-1]) | ///
        mi(`free') | mi(`free'[_n-1]) | ///
        mi(`state') | mi(`state'[_n-1]) | ///
        mi(`treatment') | mi(`treatment'[_n-1]) | ///
        mi(_pte_t)
    qui sort `_pte_cd_sort'
    qui count if `_pte_cd_esample'
    local _N_post = r(N)

    ereturn post `b', esample(`_pte_cd_esample') obs(`_N_post')

    // Scalars
    ereturn scalar N = `N_gmm'
    ereturn scalar converged = `converged'
    ereturn scalar fval = `fval'
    ereturn scalar criterion = `fval'
    ereturn scalar iterations = `iterations'
    ereturn scalar r2_stage1 = `r2_stage1'
    ereturn scalar n_stage1 = `n_stage1'
    ereturn scalar rts = `rts'
    ereturn scalar beta_l = `beta_l'
    ereturn scalar beta_k = `beta_k'
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar cols_X = `cols_X'
    ereturn scalar cols_Z = `cols_Z'
    ereturn scalar cols_OLP = `cols_OLP'
    ereturn scalar cond_ZZ = `cond_ZZ'

    // Macros
    ereturn local cmd "pte"
    ereturn local subcmd "cd_estimate"
    ereturn local pfunc "cd"
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
        di as text "Cobb-Douglas Estimation Results"
        di as text "{hline 60}"
        di as text ""
        di as text _col(3) "Sample Information:"
        di as text _col(5) "First-stage observations:" _col(40) as result %10.0fc `n_stage1'
        di as text _col(5) "GMM observations:" _col(40) as result %10.0fc `N_gmm'
        di as text _col(5) "First-stage R-squared:" _col(40) as result %10.4f `r2_stage1'
        di as text ""
        di as text _col(3) "GMM Optimization:"
        di as text _col(5) "Objective function value:" _col(40) as result %12.8e `fval'
        di as text _col(5) "Iterations:" _col(40) as result %8.0f `iterations'
        di as text _col(5) "Converged:" _col(40) as result cond(`converged', "Yes", "No")
        di as text _col(5) "Z'Z condition number:" _col(40) as result %12.4e `cond_ZZ'
        di as text ""
        di as text _col(3) "Parameter Estimates:"
        di as text _col(5) "beta_l (labor elasticity):" _col(40) as result %10.6f `beta_l'
        di as text _col(5) "beta_k (capital elasticity):" _col(40) as result %10.6f `beta_k'
        di as text _col(5) "Returns to scale:" _col(40) as result %10.6f `rts'
        di as text ""
        di as text "{hline 60}"
        di as text ""
    }

end
