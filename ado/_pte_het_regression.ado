*! _pte_het_regression.ado
*! TT vs Initial Productivity Regression Analysis
*! Implements Table 4: Correlation between initial productivity and TTs

version 14.0
capture program drop _pte_het_regression
program define _pte_het_regression, eclass
    version 14.0
    
    syntax [, noNORMalize GRaph SAVing(string) USing(string) CLuster(varname)]
    
    // =========================================================================
    // Step 0: Retrieve global parameters
    // =========================================================================
    local panelid   "$pte_panelid"
    local timevar   "$pte_timevar"
    local industry  "$pte_industry"
    local attperiods = ${pte_attperiods}
    
    if "`panelid'" == "" | "`timevar'" == "" {
        display as error "_pte_het_regression: panel globals not set"
        display as error "  Required: pte_panelid, pte_timevar"
        exit 198
    }
    if missing(`attperiods') | `attperiods' < 0 {
        display as error "_pte_het_regression: pte_attperiods not set or invalid"
        exit 198
    }
    
    // =========================================================================
    // Step 1: Input validation
    // =========================================================================
    
    // Check required variables exist
    confirm variable TT_mean
    confirm variable omega
    confirm variable nt
    
    // Verify panel is set
    capture tsset
    if _rc != 0 {
        display as error "_pte_het_regression: data not tsset/xtset"
        display as error "  Run: xtset `panelid' `timevar'"
        exit 459
    }
    
    // Check nt=-1 observations exist (pre-treatment baseline)
    quietly count if nt == -1
    if r(N) == 0 {
        display as error "_pte_het_regression: no nt=-1 observations found"
        display as error "  nt=-1 marks pre-treatment baseline periods"
        exit 2000
    }
    
    // Check at least some nt>=0 observations exist
    quietly count if nt >= 0 & !missing(nt)
    if r(N) == 0 {
        display as error "_pte_het_regression: no nt>=0 observations for regression"
        exit 2000
    }
    
    // =========================================================================
    // Step 2: Data preparation - omega normalization by industry
    // =========================================================================
    
    // Determine omega variable for regression
    local omegavar "omega"
    
    if "`normalize'" != "nonormalize" & "`industry'" != "" {
        // Normalize omega by industry: subtract industry mean
        // Creates omega_norm = omega - mean(omega) within each industry
        capture drop omega_norm
        quietly {
            tempvar ind_mean
            sort `industry'
            by `industry': egen double `ind_mean' = mean(omega)
            gen double omega_norm = omega - `ind_mean'
            // Restore panel sort order
            sort `panelid' `timevar'
        }
        local omegavar "omega_norm"
        display as text "Note: Using industry-normalized omega (omega_norm)"
    }
    
    // =========================================================================
    // Step 3: Initialize result matrices
    // =========================================================================
    
    local ncols = `attperiods' + 1
    
    tempname b_beta b_se b_t b_p b_r2 b_N b_df
    matrix `b_beta' = J(1, `ncols', .)
    matrix `b_se'   = J(1, `ncols', .)
    matrix `b_t'    = J(1, `ncols', .)
    matrix `b_p'    = J(1, `ncols', .)
    matrix `b_r2'   = J(1, `ncols', .)
    matrix `b_N'    = J(1, `ncols', .)
    matrix `b_df'   = J(1, `ncols', .)
    
    // Column names: ell_0, ell_1, ..., ell_K
    local colnames ""
    forvalues ell = 0/`attperiods' {
        local colnames "`colnames' ell_`ell'"
    }
    
    // =========================================================================
    // Step 4: Display header
    // =========================================================================
    
    display as text ""
    display as text "{hline 79}"
    display as text _col(10) "TT vs Initial Productivity Regression (Table 4)"
    display as text "{hline 79}"
    display as text ""
    display as text "Dependent variable: TT_mean"
    display as text "Independent variable: L{lag}.`omegavar'"
    if "`cluster'" != "" {
        display as text "Cluster-robust SE: `cluster'"
    }
    else {
        display as text "Heteroskedasticity-robust SE (HC1)"
    }
    display as text ""
    display as text "{hline 79}"
    display as text %5s "ell" " {c |}" ///
        %4s "lag" ///
        %12s "beta" ///
        %10s "se" ///
        %10s "t" ///
        %10s "p" ///
        %8s "R2" ///
        %8s "N" ///
        "  FE"
    display as text "{hline 79}"
    
    // =========================================================================
    // Step 5: Regression loop
    // =========================================================================
    // Regression patterns:
    //   nt=0: reg omg_tt l1.omega i.year i.indid_adj, r          (NO firm FE)
    //   nt=1: reg omg_tt l2.omega i.year i.firm i.indid_adj, r   (WITH firm FE)
    //   nt=2: reg omg_tt l3.omega i.year i.firm i.indid_adj, r   (WITH firm FE)
    //   nt=3: reg omg_tt l4.omega i.year i.firm i.indid_adj, r   (WITH firm FE)
    // Key: lag = ell + 1; nt=0 has no firm FE, nt>=1 has firm FE
    
    local n_success = 0
    
    forvalues ell = 0/`attperiods' {
        local col = `ell' + 1
        local lag = `ell' + 1
        
        // Check if enough observations exist for this ell
        quietly count if nt == `ell' & !missing(TT_mean) & !missing(L`lag'.`omegavar')
        local n_avail = r(N)
        
        if `n_avail' < 5 {
            display as text %5.0f `ell' " {c |}" ///
                as text "  (skipped: only `n_avail' obs with non-missing data)"
            continue
        }
        
        // Build fixed effects specification
        // nt=0: i.timevar i.industry (NO firm FE)
        // nt>=1: i.timevar i.panelid i.industry (WITH firm FE)
        local fe_spec "i.`timevar'"
        local fe_label "year"
        
        if `ell' >= 1 {
            local fe_spec "`fe_spec' i.`panelid'"
            local fe_label "`fe_label'+firm"
        }
        
        if "`industry'" != "" {
            local fe_spec "`fe_spec' i.`industry'"
            local fe_label "`fe_label'+ind"
        }
        
        // Build SE specification
        if "`cluster'" != "" {
            local se_spec "vce(cluster `cluster')"
        }
        else {
            local se_spec "robust"
        }
        
        // Run regression
        // reg TT_mean L{lag}.omegavar FE if nt==ell, robust/cluster
        capture noisily regress TT_mean L`lag'.`omegavar' `fe_spec' ///
            if nt == `ell', `se_spec'
        
        if _rc != 0 {
            display as text %5.0f `ell' " {c |}" ///
                as error "  (regression failed, rc=" _rc ")"
            continue
        }
        
        // Extract results
        local beta_val = _b[L`lag'.`omegavar']
        local se_val   = _se[L`lag'.`omegavar']
        local t_val    = `beta_val' / `se_val'
        local p_val    = 2 * ttail(e(df_r), abs(`t_val'))
        local r2_val   = e(r2)
        local n_val    = e(N)
        local df_val   = e(df_r)
        
        // Store in matrices
        matrix `b_beta'[1, `col'] = `beta_val'
        matrix `b_se'[1, `col']   = `se_val'
        matrix `b_t'[1, `col']    = `t_val'
        matrix `b_p'[1, `col']    = `p_val'
        matrix `b_r2'[1, `col']   = `r2_val'
        matrix `b_N'[1, `col']    = `n_val'
        matrix `b_df'[1, `col']   = `df_val'
        
        // Store estimates for esttab
        estimates store _pte_reg_ell`ell'
        local n_success = `n_success' + 1
        
        // Significance stars
        local stars ""
        if `p_val' < 0.01      local stars "***"
        else if `p_val' < 0.05 local stars "**"
        else if `p_val' < 0.10 local stars "*"
        
        // Display formatted row
        display as text %5.0f `ell' " {c |}" ///
            as text %4.0f `lag' ///
            as result %12.4f `beta_val' as text "`stars'" ///
            as result %10.4f `se_val' ///
            as result %10.3f `t_val' ///
            as result %10.4f `p_val' ///
            as result %8.3f `r2_val' ///
            as result %8.0f `n_val' ///
            as text "  `fe_label'"
    }
    
    display as text "{hline 79}"
    display as text "* p < 0.10, ** p < 0.05, *** p < 0.01"
    display as text ""
    
    // =========================================================================
    // Step 6: Store results to e()
    // =========================================================================
    
    if `n_success' == 0 {
        display as error "_pte_het_regression: all regressions failed"
        exit 2000
    }
    
    // Set column names on all matrices
    matrix colnames `b_beta' = `colnames'
    matrix colnames `b_se'   = `colnames'
    matrix colnames `b_t'    = `colnames'
    matrix colnames `b_p'    = `colnames'
    matrix colnames `b_r2'   = `colnames'
    matrix colnames `b_N'    = `colnames'
    matrix colnames `b_df'   = `colnames'
    
    // Post to e()
    ereturn clear
    ereturn local cmd          "_pte_het_regression"
    ereturn local depvar       "TT_mean"
    ereturn local indepvar     "`omegavar'"
    if "`normalize'" != "nonormalize" & "`industry'" != "" {
        ereturn local normalized "yes"
    }
    else {
        ereturn local normalized "no"
    }
    ereturn local fe_nt0       "year+industry"
    ereturn local fe_nt1plus   "year+firm+industry"
    if "`cluster'" != "" {
        ereturn local vcetype  "cluster(`cluster')"
    }
    else {
        ereturn local vcetype  "robust"
    }
    ereturn scalar attperiods  = `attperiods'
    ereturn scalar n_success   = `n_success'
    
    ereturn matrix beta_omega  = `b_beta'
    ereturn matrix se_omega    = `b_se'
    ereturn matrix t_omega     = `b_t'
    ereturn matrix p_omega     = `b_p'
    ereturn matrix r2_omega    = `b_r2'
    ereturn matrix N_omega     = `b_N'
    ereturn matrix df_omega    = `b_df'
    
    // =========================================================================
    // Step 7: Optional esttab export
    // =========================================================================
    
    if "`using'" != "" {
        // Check if esttab is available
        capture which esttab
        if _rc != 0 {
            display as text "Note: esttab not installed, skipping table export"
            display as text "  Install with: ssc install estout"
        }
        else {
            // Build estimates list
            local est_list ""
            forvalues ell = 0/`attperiods' {
                capture estimates describe _pte_reg_ell`ell'
                if _rc == 0 {
                    local est_list "`est_list' _pte_reg_ell`ell'"
                }
            }
            
            if "`est_list'" != "" {
                // Console display: keep all omega lags
                display as text ""
                display as text "Regression table (esttab format):"
                esttab `est_list', keep(*`omegavar') nogaps ///
                    b(%9.3f) se(%9.3f) r2 ///
                    star(* 0.1 ** 0.05 *** 0.01)
                
                // File export
                esttab `est_list' using "`using'", replace ///
                    keep(*`omegavar') nogaps ///
                    b(%9.3f) se(%9.3f) r2 ///
                    star(* 0.1 ** 0.05 *** 0.01)
                
                display as text "Table exported to: `using'"
            }
        }
    }
    
    // =========================================================================
    // Step 8: Optional scatter plots
    // =========================================================================
    
    if "`graph'" != "" {
        display as text ""
        display as text "Generating TT vs omega scatter plots..."
        
        // Use TT_mean_trim if available (Winsorized), else TT_mean
        local depplot "TT_mean"
        capture confirm variable TT_mean_trim
        if _rc == 0 {
            local depplot "TT_mean_trim"
        }
        
        forvalues ell = 0/`attperiods' {
            local lag = `ell' + 1
            
            // Check sufficient data
            quietly count if nt == `ell' & !missing(`depplot') & !missing(L`lag'.`omegavar')
            if r(N) < 5 continue
            
            // Build graph
            local gtitle "TT vs Initial Productivity (ell=`ell', lag=`lag')"
            local gytitle "Treatment Effect (TT)"
            local gxtitle "L`lag'.`omegavar'"
            
            twoway (scatter `depplot' L`lag'.`omegavar' if nt == `ell', ///
                    msize(small) mcolor(gs8%50)) ///
                   (lfit `depplot' L`lag'.`omegavar' if nt == `ell', ///
                    lcolor(cranberry) lwidth(medthick)), ///
                   title("`gtitle'", size(medium)) ///
                   ytitle("`gytitle'") xtitle("`gxtitle'") ///
                   legend(off) name(_pte_reg_ell`ell', replace)
            
            // Save if requested
            if "`saving'" != "" {
                graph export "`saving'_ell`ell'.png", name(_pte_reg_ell`ell') replace
            }
        }
    }
    
    // =========================================================================
    // Step 9: Clean up stored estimates
    // =========================================================================
    
    // Drop stored estimates to avoid namespace pollution
    // Users can re-run with using() to get esttab output
    forvalues ell = 0/`attperiods' {
        capture estimates drop _pte_reg_ell`ell'
    }
    
    display as text "Regression analysis complete. Results stored in e()."
    display as text "  e(beta_omega) - coefficient on lagged omega"
    display as text "  e(se_omega)   - robust/cluster standard errors"
    display as text "  e(t_omega)    - t-statistics"
    display as text "  e(p_omega)    - p-values"
    display as text "  e(r2_omega)   - R-squared"
    display as text "  e(N_omega)    - number of observations"
    
end
