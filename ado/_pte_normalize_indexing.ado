*! _pte_normalize_indexing.ado
*! Indexing Number Normalization
*! Caves, Christensen & Diewert (1982)
*! For D=1 observations, compute "treated-productivity-with-fixed-technology":
*! omega_tilde = q_it - f(k, l, m, D=0; beta)
*! using untreated production function parameters beta^0.
*! For D=0 observations, omega_tilde = omega (unchanged).

version 14.0
capture program drop _pte_normalize_indexing
program define _pte_normalize_indexing
    version 14.0
    
    // Not eclass — returns results via scalar/matrix to caller
    syntax , [ATTnorm Quietly]
    
    // ================================================================
    // Step 1: Validate treatdependent mode (Task 2)
    // ================================================================
    
    if "`e(treatdependent)'" != "1" {
        di as error "normalize(indexing) requires treatdependent option"
        di as error "Run pte with: treatdependent normalize(indexing)"
        exit 198
    }
    
    // ================================================================
    // Step 2: Validate e(b_untreated) exists (Task 3)
    // ================================================================
    
    tempname b0
    capture matrix `b0' = e(b_untreated)
    if _rc {
        di as error "e(b_untreated) matrix not found"
        di as error "Ensure pte was run with treatdependent option"
        exit 198
    }
    if rowsof(`b0') == 0 | colsof(`b0') == 0 {
        di as error "e(b_untreated) matrix is empty"
        exit 198
    }
    
    // ================================================================
    // Step 3: Validate production function type (Task 4)
    // ================================================================
    
    local prodfunc "`e(prodfunc)'"
    if "`prodfunc'" == "" local prodfunc "`e(pfunc)'"
    if "`prodfunc'" == "tl" local prodfunc "translog"
    
    if !inlist("`prodfunc'", "cd", "translog") {
        di as error "unsupported production function type: `prodfunc'"
        di as error "Indexing Number normalization supports: cd, translog"
        exit 198
    }
    
    // ================================================================
    // Step 4: Get variable names dynamically (Task 5)
    // ================================================================
    // Bug 18 fix: use canonical e() names e(free/state/proxy/treatment)
    // instead of non-existent e(freevar/statevar/proxyvar/treatvar)
    
    local depvar "`e(depvar)'"
    local freevar "`e(free)'"
    local statevar "`e(state)'"
    local proxyvar "`e(proxy)'"
    
    // Guard: ensure variable names are non-empty
    if "`freevar'" == "" {
        di as error "e(free) is empty; cannot identify free variable"
        di as error "Ensure pte was run with free() option"
        exit 198
    }
    if "`statevar'" == "" {
        di as error "e(state) is empty; cannot identify state variable"
        di as error "Ensure pte was run with state() option"
        exit 198
    }
    
    // Validate required variables exist in data
    foreach var in `depvar' `freevar' `statevar' {
        capture confirm variable `var'
        if _rc {
            di as error "required variable `var' not found in data"
            exit 111
        }
    }
    
    // Get treatment variable: canonical name is e(treatment)
    local treatvar "`e(treatment)'"
    if "`treatvar'" == "" local treatvar "D"
    capture confirm variable `treatvar'
    if _rc {
        // Try treat_post as fallback
        capture confirm variable treat_post
        if !_rc {
            local treatvar "treat_post"
        }
        else {
            di as error "treatment variable `treatvar' not found"
            exit 111
        }
    }
    
    // ================================================================
    // Step 5: Extract beta^0 parameters (Task 6-9)
    // ================================================================
    
    local beta_l_0 = .
    local beta_k_0 = .
    local beta_ll_0 = 0
    local beta_kk_0 = 0
    local beta_lk_0 = 0
    local beta_t_0 = 0
    local has_time_trend = 0
    local n_params = 0
    
    // Extract first-order parameters
    // Try column names from b_untreated
    local colnames : colnames `b0'
    
    // Find freevar (labor) column
    // Guard: freevar is guaranteed non-empty by Step 4 check above
    local l_col = colnumb(`b0', "`freevar'")
    if `l_col' == . {
        // Try common names as fallback
        local l_col = colnumb(`b0', "lnl")
    }
    if `l_col' != . {
        local beta_l_0 = `b0'[1, `l_col']
    }
    
    // Find statevar (capital) column
    // Guard: statevar is guaranteed non-empty by Step 4 check above
    local k_col = colnumb(`b0', "`statevar'")
    if `k_col' == . {
        // Try common names as fallback
        local k_col = colnumb(`b0', "lnk")
    }
    if `k_col' != . {
        local beta_k_0 = `b0'[1, `k_col']
    }
    
    // Guard: ensure l_col and k_col are distinct (prevent silent collapse)
    if `l_col' == `k_col' & !missing(`l_col') {
        di as error "WARNING: freevar and statevar mapped to same column (`l_col') in e(b_untreated)"
        di as error "  freevar=`freevar', statevar=`statevar'"
        di as error "  This indicates an e() contract or column naming issue"
        exit 198
    }
    
    // Validate first-order params
    if missing(`beta_l_0') | missing(`beta_k_0') {
        di as error "cannot extract first-order parameters from e(b_untreated)"
        di as error "  beta_l_0 = `beta_l_0', beta_k_0 = `beta_k_0'"
        exit 198
    }
    local n_params = 2
    
    // Extract Translog second-order parameters (Task 8)
    if "`prodfunc'" == "translog" {
        // var_1_1 = lnl^2 coefficient
        capture local beta_ll_0 = `b0'[1, colnumb(`b0', "var_1_1")]
        if _rc | missing(`beta_ll_0') local beta_ll_0 = 0
        
        // var_3_3 = lnk^2 coefficient
        capture local beta_kk_0 = `b0'[1, colnumb(`b0', "var_3_3")]
        if _rc | missing(`beta_kk_0') local beta_kk_0 = 0
        
        // var_1_3 = lnl*lnk coefficient
        capture local beta_lk_0 = `b0'[1, colnumb(`b0', "var_1_3")]
        if _rc | missing(`beta_lk_0') local beta_lk_0 = 0
        
        local n_params = 5
        
        // Proxy variable (gross output) second-order terms
        if "`proxyvar'" != "" {
            capture local beta_m_0 = `b0'[1, colnumb(`b0', "`proxyvar'")]
            if _rc | missing(`beta_m_0') local beta_m_0 = 0
            
            capture local beta_lm_0 = `b0'[1, colnumb(`b0', "var_1_5")]
            if _rc | missing(`beta_lm_0') local beta_lm_0 = 0
            
            capture local beta_km_0 = `b0'[1, colnumb(`b0', "var_3_5")]
            if _rc | missing(`beta_km_0') local beta_km_0 = 0
            
            capture local beta_mm_0 = `b0'[1, colnumb(`b0', "var_5_5")]
            if _rc | missing(`beta_mm_0') local beta_mm_0 = 0
            
            local n_params = 9
        }
    }
    
    // Time trend (Task 9)
    capture local beta_t_0 = `b0'[1, colnumb(`b0', "t")]
    if _rc | missing(`beta_t_0') {
        local beta_t_0 = 0
        local has_time_trend = 0
    }
    else {
        local has_time_trend = 1
        local ++n_params
    }
    
    // Extreme value warning (Task 12)
    if abs(`beta_l_0') > 10 | abs(`beta_k_0') > 10 {
        di as text "Warning: unusually large parameter values detected"
        di as text "  beta_l_0 = " %9.4f `beta_l_0'
        di as text "  beta_k_0 = " %9.4f `beta_k_0'
    }
    
    // ================================================================
    // Step 6: Compute omega_indexing (Task 13-18)
    // ================================================================
    
    // Handle variable conflict (Task 16)
    capture confirm variable _pte_omega_indexing
    if !_rc {
        if "`quietly'" == "" {
            di as text "Note: _pte_omega_indexing already exists, replacing"
        }
        drop _pte_omega_indexing
    }
    
    // Compute normalized productivity using beta^0 for ALL observations
    // Paper Appendix C.1: omega_tilde = q - f(k,l,D=0; beta)
    if "`prodfunc'" == "cd" {
        // Cobb-Douglas: omega_tilde = lny - beta_l^0 * lnl - beta_k^0 * lnk
        qui gen double _pte_omega_indexing = `depvar' ///
            - `beta_l_0' * `freevar' ///
            - `beta_k_0' * `statevar'
        
        // Subtract time trend if present
        if `has_time_trend' {
            capture confirm variable t
            if !_rc {
                qui replace _pte_omega_indexing = _pte_omega_indexing - `beta_t_0' * t
            }
        }
    }
    else if "`prodfunc'" == "translog" {
        // Translog: omega_tilde = lny - beta_l^0*lnl - beta_k^0*lnk
        //   - beta_ll^0*lnl^2 - beta_kk^0*lnk^2 - beta_lk^0*lnl*lnk
        qui gen double _pte_omega_indexing = `depvar' ///
            - `beta_l_0' * `freevar' ///
            - `beta_k_0' * `statevar' ///
            - `beta_ll_0' * `freevar'^2 ///
            - `beta_kk_0' * `statevar'^2 ///
            - `beta_lk_0' * `freevar' * `statevar'
        
        // Gross-output additional terms
        if "`proxyvar'" != "" {
            capture confirm variable `proxyvar'
            if !_rc {
                qui replace _pte_omega_indexing = _pte_omega_indexing ///
                    - `beta_m_0' * `proxyvar' ///
                    - `beta_lm_0' * `freevar' * `proxyvar' ///
                    - `beta_km_0' * `statevar' * `proxyvar' ///
                    - `beta_mm_0' * `proxyvar'^2
            }
        }
        
        // Subtract time trend if present
        if `has_time_trend' {
            capture confirm variable t
            if !_rc {
                qui replace _pte_omega_indexing = _pte_omega_indexing - `beta_t_0' * t
            }
        }
    }
    
    // Missing value check (Task 17)
    qui count if missing(_pte_omega_indexing) & !missing(`depvar') & !missing(`freevar') & !missing(`statevar')
    if r(N) > 0 {
        di as error "WARNING: `r(N)' unexpected missing values in _pte_omega_indexing"
    }
    
    // Variable label (Task 19)
    label variable _pte_omega_indexing "Normalized productivity (Indexing Number method)"
    notes _pte_omega_indexing: Created by pte with normalize(indexing)
    notes _pte_omega_indexing: Reference: Chen, Liao & Schurter (2026) Appendix C.1
    notes _pte_omega_indexing: Uses untreated production function parameters (beta^0)
    
    // Basic statistics
    qui summ _pte_omega_indexing
    local omega_n = r(N)
    local omega_mean = r(mean)
    local omega_sd = r(sd)
    
    // ================================================================
    // Step 7: Consistency verification (Task 21-25)
    // ================================================================
    
    // D=0 consistency: omega_indexing should equal original omega for D=0
    local max_diff0 = .
    local d0_n = 0
    local d0_pass = 1
    local d0_status = "N/A"
    
    capture confirm variable _pte_omega
    if !_rc {
        tempvar diff0
        qui gen double `diff0' = abs(_pte_omega_indexing - _pte_omega) if `treatvar' == 0
        qui summ `diff0'
        local max_diff0 = r(max)
        local d0_n = r(N)
        
        if missing(`max_diff0') {
            local d0_pass = 1
            local d0_status = "N/A (no D=0 observations)"
        }
        else if `max_diff0' < 1e-10 {
            local d0_pass = 1
            local d0_status = "PASS"
        }
        else {
            local d0_pass = 0
            local d0_status = "FAIL (max diff = `max_diff0')"
            di as error "WARNING: D=0 consistency check failed, max diff = " %12.2e `max_diff0'
        }
    }
    
    // D=1 difference check: should differ from original omega
    local mean_diff1 = .
    local d1_n = 0
    local d1_pass = 1
    local d1_status = "N/A"
    
    capture confirm variable _pte_omega
    if !_rc {
        tempvar diff1
        qui gen double `diff1' = abs(_pte_omega_indexing - _pte_omega) if `treatvar' == 1
        qui summ `diff1'
        local mean_diff1 = r(mean)
        local d1_n = r(N)
        
        if missing(`mean_diff1') {
            local d1_pass = 1
            local d1_status = "N/A (no D=1 observations)"
        }
        else if `mean_diff1' > 1e-6 {
            local d1_pass = 1
            local d1_status = "PASS (expected difference)"
        }
        else {
            local d1_pass = 0
            local d1_status = "UNEXPECTED (no difference, may indicate beta^0 = beta^1)"
        }
    }
    
    // D=0 correlation check
    local corr_d0 = .
    capture confirm variable _pte_omega
    if !_rc {
        capture qui corr _pte_omega_indexing _pte_omega if `treatvar' == 0
        if !_rc local corr_d0 = r(rho)
    }
    
    local verify_pass = `d0_pass' & `d1_pass'
    
    // ================================================================
    // Step 8: Display output (Task 24, 29)
    // ================================================================
    
    if "`quietly'" == "" {
        di as text ""
        di as text "{hline 64}"
        di as text "Productivity Normalization: Indexing Number Method"
        di as text "{hline 64}"
        di as text "Method:              Indexing Number (Caves et al., 1982)"
        di as text "Reference:           Paper Appendix C.1"
        di as text ""
        di as text "Production function: " as result "`prodfunc'"
        di as text "Parameters used:     beta^0 (untreated)"
        di as text "Parameters count:    " as result "`n_params'"
        di as text ""
        di as text "  beta_l_0 = " as result %9.6f `beta_l_0'
        di as text "  beta_k_0 = " as result %9.6f `beta_k_0'
        if "`prodfunc'" == "translog" {
            di as text "  beta_ll_0 = " as result %9.6f `beta_ll_0'
            di as text "  beta_kk_0 = " as result %9.6f `beta_kk_0'
            di as text "  beta_lk_0 = " as result %9.6f `beta_lk_0'
        }
        if `has_time_trend' {
            di as text "  beta_t_0 = " as result %9.6f `beta_t_0'
        }
        di as text ""
        di as text "Normalized variable: " as result "_pte_omega_indexing"
        di as text "  Observations:      " as result `omega_n'
        di as text "  Mean:              " as result %9.4f `omega_mean'
        di as text "  Std. Dev.:         " as result %9.4f `omega_sd'
        di as text ""
        di as text "Verification:"
        di as text "  D=0 obs:          " as result `d0_n'
        di as text "  D=0 max diff:     " as result "`d0_status'"
        di as text "  D=1 obs:          " as result `d1_n'
        di as text "  D=1 mean diff:    " as result "`d1_status'"
        if !missing(`corr_d0') {
            di as text "  D=0 correlation:  " as result %9.6f `corr_d0'
        }
        di as text ""
        di as text "Interpretation:"
        di as text "  omega_indexing answers: 'What productivity would produce"
        di as text "  the same output using untreated technology?'"
        di as text "{hline 64}"
    }
    
    // ================================================================
    // Step 8b: Optional ATT_norm computation (Task 28)
    // ================================================================
    
    local att_norm_computed = 0
    local att_norm_horizon = .
    
    if "`attnorm'" != "" {
        // ATT_norm strategy:
        //   1. Save original omega
        //   2. Temporarily replace with normalized omega
        //   3. Call _pte_att to recompute counterfactual paths and ATT
        //      - Uses existing rho0-rho3 and eps0 distribution (no re-estimation)
        //      - Only changes simulation starting point to omega_indexing
        //   4. Extract ATT_norm results
        //   5. Restore original omega

        capture confirm variable omega, exact
        if !_rc {
            tempvar omega_orig
            qui gen double `omega_orig' = omega

            local att_treatment "`e(treatment)'"
            if "`att_treatment'" == "" {
                local att_treatment "`treatvar'"
            }

            local att_opts "treatment(`att_treatment')"
            capture local att_omegapoly = e(omegapoly)
            if _rc == 0 {
                local att_opts "`att_opts' omegapoly(`att_omegapoly')"
            }
            capture local att_attperiods = e(attperiods_max)
            if _rc == 0 {
                local att_opts "`att_opts' attperiods(`att_attperiods')"
            }
            capture local att_nsim = e(nsim)
            if _rc == 0 {
                local att_opts "`att_opts' nsim(`att_nsim')"
            }
            // ATT_norm should reuse the live ATT simulation law. On the
            // point-estimate path e(seed) may be only wrapper metadata while
            // e(point_seed) stores the actual inner ATT simulation seed.
            local att_seed = .
            capture local att_seed = e(point_seed)
            if _rc != 0 | missing(`att_seed') {
                capture local att_seed = e(seed)
            }
            if _rc == 0 & !missing(`att_seed') {
                local att_opts "`att_opts' seed(`att_seed')"
            }
            if "`e(notrimeps)'" != "" {
                local att_opts "`att_opts' notrimeps"
            }
            local att_opts "`att_opts' nodiagnose"

            capture confirm variable _pte_omega
            local has_archived_omega = (_rc == 0)
            if `has_archived_omega' {
                tempvar omega_archived_orig
                qui gen double `omega_archived_orig' = _pte_omega
                qui replace _pte_omega = _pte_omega_indexing
            }

            // Replace the live omega consumed by _pte_att.
            qui replace omega = _pte_omega_indexing

            // Call ATT computation (uses existing evolution params and eps0)
            capture noisily _pte_att, `att_opts'
            local att_rc = _rc
            
            if `att_rc' == 0 {
                // Extract normalized ATT results over the full requested
                // public horizon. Appendix C.1 says the normalized ATT path
                // reuses the same ATT recursion, so truncating the published
                // support below e(attperiods_max) would change the object.
                capture local att_norm_horizon = e(attperiods_max)
                if _rc != 0 | missing(`att_norm_horizon') {
                    local att_norm_horizon = `att_attperiods'
                }
                if missing(`att_norm_horizon') {
                    local att_norm_horizon = 3
                }

                local att_norm_complete = 1
                forvalues s = 0/`att_norm_horizon' {
                    capture confirm scalar _pte_att_`s'
                    if _rc != 0 {
                        local att_norm_complete = 0
                    }
                    else {
                        local att_norm_`s' = scalar(_pte_att_`s')
                    }
                }

                if `att_norm_complete' {
                    local att_norm_computed = 1
                }
                else if "`quietly'" == "" {
                    di as text "Note: ATT_norm bridge missing one or more `_pte_att_*' scalars; skipping"
                }

                if "`quietly'" == "" & `att_norm_computed' {
                    di as text ""
                    di as text "ATT (normalized):"
                    forvalues s = 0/`att_norm_horizon' {
                        di as text "  ATT_norm order `s': " as result %9.6f `att_norm_`s''
                    }
                }
            }
            else {
                if "`quietly'" == "" {
                    di as text "Note: ATT_norm computation failed (rc = `att_rc'), skipping"
                }
            }

            // Restore original omega
            qui replace omega = `omega_orig'
            if `has_archived_omega' {
                qui replace _pte_omega = `omega_archived_orig'
            }
        }
        else {
            if "`quietly'" == "" {
                di as text "Note: omega not found, cannot compute ATT_norm"
            }
        }
    }
    
    // ================================================================
    // Step 9: Return results via scalar/matrix (Task 26)
    // ================================================================
    
    // Pass results back to caller via scalar/matrix (not ereturn)
    scalar _pte_norm_d0_corr = `corr_d0'
    scalar _pte_norm_d0_maxdiff = `max_diff0'
    scalar _pte_norm_d1_meandiff = `mean_diff1'
    scalar _pte_norm_verify_pass = `verify_pass'
    scalar _pte_norm_n_params = `n_params'
    scalar _pte_norm_omega_n = `omega_n'
    scalar _pte_norm_omega_mean = `omega_mean'
    scalar _pte_norm_omega_sd = `omega_sd'
    
    // ATT_norm results (Task 28)
    scalar _pte_norm_att_norm_computed = `att_norm_computed'
    if `att_norm_computed' {
        scalar _pte_norm_att_norm_horizon = `att_norm_horizon'
        forvalues s = 0/`att_norm_horizon' {
            scalar _pte_norm_att_norm_`s' = `att_norm_`s''
        }
    }
    
    // Copy b0 matrix for caller
    matrix _pte_norm_b0_used = `b0'
    
end
