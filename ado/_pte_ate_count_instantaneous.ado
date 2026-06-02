*! _pte_ate_count_instantaneous.ado
*! Instantaneous counterfactual ATE estimation (Proposition D.2)
*! Computes ATE_{s,0}^{count} = E[h_1^+(omega) - h_bar_0(omega) | i in G]

version 14.0
capture program drop _pte_ate_count_instantaneous
program define _pte_ate_count_instantaneous, eclass
    version 14.0
    
    // ================================================================
    // Task 1-4: Syntax parsing and precondition checks
    // ================================================================
    
    syntax , ///
        TARGETgroup(name)        /// 0/1 variable identifying target group G
        REFERENCEtime(integer)   /// t0: first treatment period
        EXPANSIONtime(integer)   /// t0+s: planned expansion period
        [                        ///
        Level(integer 95)        /// confidence level
        KEEPfirm                 /// store firm-level effects in e()
        QUIET                    /// suppress display
        ]
    
    // --- Task 1: Check h_1^+ availability ---
    capture confirm matrix e(h_plus)
    if _rc {
        di as error "{bf:pte error 3009}: Instantaneous counterfactual ATE requires h_1^+ to be estimated"
        di as error "  Please run: pte ..., evolution(divergent) estimatetransition"
        di as error "  or specify cfmethod(matching) for alternative approach"
        exit 3009
    }
    tempname H_plus
    matrix `H_plus' = e(h_plus)
    
    // --- Task 2: Check rho_0 availability ---
    capture confirm matrix e(rho_0)
    if _rc {
        di as error "{bf:pte error 3010}: Missing evolution parameters rho_0"
        di as error "  Please ensure production function estimation completed successfully"
        exit 3010
    }
    tempname Rho_0
    matrix `Rho_0' = e(rho_0)
    
    // --- Task 3: Validate coefficient matrix dimensions ---
    local omegapoly = e(omegapoly)
    if `omegapoly' == . {
        // Infer from matrix dimension
        local omegapoly = colsof(`H_plus') - 1
    }
    
    if colsof(`H_plus') != `omegapoly' + 1 {
        di as error "{bf:pte error 3014}: h_plus matrix dimension mismatch"
        di as error "  Expected `=`omegapoly'+1' columns, got `=colsof(`H_plus')'"
        exit 3014
    }
    if colsof(`Rho_0') != `omegapoly' + 1 {
        di as error "{bf:pte error 3014}: rho_0 matrix dimension mismatch"
        di as error "  Expected `=`omegapoly'+1' columns, got `=colsof(`Rho_0')'"
        exit 3014
    }
    
    // --- Task 4: Validate targetgroup variable ---
    capture confirm variable `targetgroup', exact
    if _rc {
        di as error "{bf:pte error 3006}: targetgroup variable '`targetgroup'' not found"
        exit 3006
    }
    capture assert inlist(`targetgroup', 0, 1, .)
    if _rc {
        di as error "{bf:pte error 3006}: targetgroup must be 0/1 variable"
        exit 3006
    }
    
    // ================================================================
    // Task 5-8: Sample selection
    // ================================================================
    
    // --- Task 5: Validate time parameters ---
    local t0 = `referencetime'
    local s = `expansiontime' - `referencetime'
    local target_year = `t0' + `s' - 1
    
    qui sum year
    local year_min = r(min)
    local year_max = r(max)
    
    if `target_year' < `year_min' | `target_year' > `year_max' {
        di as error "{bf:pte error 3013}: Target period `target_year' out of data range [`year_min', `year_max']"
        di as error "  t0 = `t0', s = `s'"
        di as error "  Please adjust referencetime() or expansiontime()"
        exit 3013
    }
    
    // --- Task 6: Filter target group sample ---
    preserve
    keep if `targetgroup' == 1 & year == `target_year'
    local N_target = _N
    
    if `N_target' == 0 {
        di as error "{bf:pte error 3012}: No valid observations in target group"
        di as error "  Year = `target_year', targetgroup = 1"
        restore
        exit 3012
    }
    
    // --- Task 7: Verify target group is untreated ---
    local treatvar "`e(treatvar)'"
    if "`treatvar'" == "" local treatvar "D"
    capture confirm variable `treatvar'
    if !_rc {
        qui count if `treatvar' == 1
        if r(N) > 0 {
            di as error "{bf:pte error 3011}: Target group contains `r(N)' treated firms at t0+s-1"
            di as error "  Target group G must be subset of untreated group S^ut"
            di as error "  Please verify targetgroup() variable definition"
            restore
            exit 3011
        }
    }
    
    // --- Task 8: Handle missing omega and empty sample ---
    qui count if missing(omega)
    if r(N) > 0 {
        local n_missing = r(N)
        if "`quiet'" == "" {
            di as text "  Warning: `n_missing' observations with missing omega excluded"
        }
        drop if missing(omega)
    }
    
    local N_target = _N
    if `N_target' == 0 {
        di as error "{bf:pte error 3012}: No valid observations in target group after excluding missing omega"
        restore
        exit 3012
    }
    
    // ================================================================
    // Task 9-12: Prediction computation
    // ================================================================
    
    // --- Task 9: Generate higher-order omega terms ---
    if `omegapoly' >= 2 {
        cap confirm variable omega2
        if _rc {
            gen double omega2 = omega^2
        }
    }
    if `omegapoly' >= 3 {
        cap confirm variable omega3
        if _rc {
            gen double omega3 = omega^3
        }
    }
    if `omegapoly' >= 4 {
        cap confirm variable omega4
        if _rc {
            gen double omega4 = omega^4
        }
    }
    
    // --- Task 10: Compute h_1^+(omega) prediction ---
    gen double _h_plus_pred = `H_plus'[1,1]
    forvalues j = 1/`omegapoly' {
        if `j' == 1 {
            replace _h_plus_pred = _h_plus_pred + `H_plus'[1,2] * omega
        }
        else {
            replace _h_plus_pred = _h_plus_pred + `H_plus'[1,`=`j'+1'] * omega`j'
        }
    }
    
    // --- Task 11: Compute h_bar_0(omega) prediction ---
    // CRITICAL: Only use rho coefficients, NOT gamma or delta
    gen double _h0_pred = `Rho_0'[1,1]
    forvalues j = 1/`omegapoly' {
        if `j' == 1 {
            replace _h0_pred = _h0_pred + `Rho_0'[1,2] * omega
        }
        else {
            replace _h0_pred = _h0_pred + `Rho_0'[1,`=`j'+1'] * omega`j'
        }
    }
    
    // --- Task 12: Compute firm-level effects and summary ---
    gen double _ate_count_0_firm = _h_plus_pred - _h0_pred
    
    qui sum _ate_count_0_firm
    scalar _ate_s_0_count = r(mean)
    scalar _ate_s_0_count_sd = r(sd)
    local N_target = r(N)
    
    // ================================================================
    // Task 13: Inference (SE and CI)
    // ================================================================
    
    local alpha = 1 - `level'/100
    local z = invnormal(1 - `alpha'/2)
    
    if `N_target' > 1 {
        scalar _se_analytic = _ate_s_0_count_sd / sqrt(`N_target')
        scalar _ci_lower = _ate_s_0_count - `z' * _se_analytic
        scalar _ci_upper = _ate_s_0_count + `z' * _se_analytic
    }
    else {
        if "`quiet'" == "" {
            di as text "  Warning: Single firm in target group, SE unavailable"
        }
        scalar _se_analytic = .
        scalar _ci_lower = .
        scalar _ci_upper = .
    }
    
    // Save firm-level effects if requested
    if "`keepfirm'" != "" {
        capture confirm variable firm
        if !_rc {
            mkmat firm _ate_count_0_firm, matrix(_ate_firm_temp)
        }
        else {
            mkmat _ate_count_0_firm, matrix(_ate_firm_temp)
        }
    }
    
    restore
    
    // ================================================================
    // Task 14: Display results
    // ================================================================
    
    if "`quiet'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "Instantaneous Counterfactual Treatment Effect (Proposition D.2)"
        di as text "{hline 70}"
        di as text ""
        di as text "  Target period:   year = " as result %4.0f `target_year' as text " (t0 + s - 1)"
        di as text "  Reference time:  t0   = " as result %4.0f `t0'
        di as text "  Expansion delay: s    = " as result %4.0f `s'
        di as text "  Target group N:        " as result %9.0f `N_target'
        di as text ""
        di as text "{hline 70}"
        di as text "  ATE_{s,0}^count      = " as result %12.6f _ate_s_0_count
        if _se_analytic < . {
            di as text "  Std. Error           = " as result %12.6f _se_analytic
            di as text "  `level'% Conf. Interval = [" as result %9.6f _ci_lower as text ", " as result %9.6f _ci_upper as text "]"
        }
        else {
            di as text "  Std. Error           = " as result "N/A (N=1)"
        }
        di as text "{hline 70}"
        di as text ""
        di as text "  Method: Divergent evolution (Proposition D.2)"
        di as text "  Formula: ATE = E[h_1^+(omega) - h_bar_0(omega) | i in G]"
        di as text "{hline 70}"
    }
    
    // ================================================================
    // Task 15: Store e() returns (append, do NOT clear prior results)
    // ================================================================
    
    // Scalars
    ereturn scalar ate_count_0 = _ate_s_0_count
    ereturn scalar ate_count_0_se = _se_analytic
    ereturn scalar ate_count_0_sd = _ate_s_0_count_sd
    ereturn scalar ate_count_0_ci_lower = _ci_lower
    ereturn scalar ate_count_0_ci_upper = _ci_upper
    ereturn scalar n_target = `N_target'
    ereturn scalar t0 = `t0'
    ereturn scalar s = `s'
    ereturn scalar level_cf = `level'
    
    // Firm-level effects matrix (optional)
    if "`keepfirm'" != "" {
        cap confirm matrix _ate_firm_temp
        if _rc == 0 {
            ereturn matrix ate_count_0_firm = _ate_firm_temp
        }
    }
    
    // Macros
    ereturn local cfmethod "divergent"
    ereturn local subcmd_cf "counterfactual_instantaneous"
    
    // Clean up scalars
    cap scalar drop _ate_s_0_count
    cap scalar drop _ate_s_0_count_sd
    cap scalar drop _se_analytic
    cap scalar drop _ci_lower
    cap scalar drop _ci_upper
    
end
