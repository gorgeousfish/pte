*! _pte_eps_bidirectional.ado
*! Bidirectional shock distribution estimation (non-absorbing treatment)

version 14.0
program define _pte_eps_bidirectional, eclass sortpreserve
    version 14.0
    
    // ===================================================================
    // Syntax parsing
    // ===================================================================
    syntax, ///
        OMEGA(varname)              /// productivity variable
        TREATMENT(varname)          /// treatment variable
        RHO_0(name)                 /// h-bar_0 parameter matrix
        RHO_1(name)                 /// h-bar_1 parameter matrix
        [                           ///
        OMEGApoly(integer 3)        /// evolution polynomial order
        ATTperiods(integer 3)       /// max ATT periods
        NOTRIMeps                   /// disable trimming
        NOLog                       /// suppress diagnostic output
        ]
    
    // ===================================================================
    // Input validation
    // ===================================================================
    
    // Verify variables exist
    confirm variable `omega'
    confirm variable `treatment'
    
    // Verify parameter matrices exist
    capture confirm matrix `rho_0'
    if _rc != 0 {
        di as error "pte: evolution parameters rho_0 not found"
        di as error "Run separate evolution estimation first"
        exit 301
    }
    
    capture confirm matrix `rho_1'
    if _rc != 0 {
        di as error "pte: evolution parameters rho_1 not found"
        di as error "Run separate evolution estimation first"
        exit 301
    }
    
    // Verify omegapoly range
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "omegapoly must be 1, 2, 3, or 4"
        exit 198
    }
    
    // Verify rho matrix dimensions match omegapoly
    if colsof(`rho_0') != `omegapoly' + 1 {
        di as error "pte: rho_0 dimension mismatch" ///
            " (expected " (`omegapoly' + 1) ", got " colsof(`rho_0') ")"
        exit 503
    }
    if colsof(`rho_1') != `omegapoly' + 1 {
        di as error "pte: rho_1 dimension mismatch" ///
            " (expected " (`omegapoly' + 1) ", got " colsof(`rho_1') ")"
        exit 503
    }
    
    // Verify panel structure
    capture _xt, trequired
    if _rc != 0 {
        di as error "data must be xtset as panel"
        exit 459
    }
    
    // ===================================================================
    // Part A: eps0 distribution estimation (for ATT+ simulation)
    // Paper: Appendix C.3 Eq.(C.3), D=D_{-1}=0 => eps0 = omega - h-bar_0
    // ===================================================================
    
    if "`nolog'" == "" {
        di as text _n "{hline 70}"
        di as text "Part A: eps0 Distribution Estimation (for ATT+ simulation)"
        di as text "{hline 70}"
    }
    
    // A.1 Sample selection: D==0 & L.D==0
    tempvar eps0_sample
    qui gen byte `eps0_sample' = (`treatment' == 0 & L.`treatment' == 0)
    
    // A.2 Sample size check
    qui count if `eps0_sample' == 1
    local N_eps0_raw = r(N)
    
    if `N_eps0_raw' == 0 {
        di as error "pte: no observations for eps0 sample (D==0 & L.D==0)"
        exit 3001
    }
    
    if `N_eps0_raw' < 30 {
        di as text "Warning: eps0 sample has only `N_eps0_raw' observations (< 30)"
    }
    
    // A.3 Generate lagged polynomial variables
    // Paper: Eq.(16) - polynomial evolution specification
    tempvar L_omega L_omega2 L_omega3 L_omega4
    qui gen double `L_omega' = L.`omega'
    qui gen double `L_omega2' = `L_omega'^2
    if `omegapoly' >= 3 {
        qui gen double `L_omega3' = `L_omega'^3
    }
    if `omegapoly' >= 4 {
        qui gen double `L_omega4' = `L_omega'^4
    }
    
    // A.4 Compute omega_hat_0 = h-bar_0(omega_{t-1})
    // Paper: Eq.(16) - omega^d = rho_0^d + rho_1^d*omega + rho_2^d*omega^2 + ...
    tempvar omega_hat_0 eps0
    qui gen double `omega_hat_0' = `rho_0'[1, 1]
    if `omegapoly' >= 1 {
        qui replace `omega_hat_0' = `omega_hat_0' + `rho_0'[1, 2] * `L_omega'
    }
    if `omegapoly' >= 2 {
        qui replace `omega_hat_0' = `omega_hat_0' + `rho_0'[1, 3] * `L_omega2'
    }
    if `omegapoly' >= 3 {
        qui replace `omega_hat_0' = `omega_hat_0' + `rho_0'[1, 4] * `L_omega3'
    }
    if `omegapoly' >= 4 {
        qui replace `omega_hat_0' = `omega_hat_0' + `rho_0'[1, 5] * `L_omega4'
    }
    // Only keep predictions for eps0 sample
    qui replace `omega_hat_0' = . if `eps0_sample' != 1
    
    // A.5 Compute residuals: eps0 = omega - omega_hat_0
    // Paper: Eq.(C.3) - eps0_it = omega_it - h-bar_0(omega_{it-1})
    qui gen double `eps0' = `omega' - `omega_hat_0' if `eps0_sample' == 1
    
    // A.5b Check for all-missing residuals
    qui count if `eps0_sample' == 1 & !missing(`eps0')
    if r(N) == 0 {
        di as error "pte: all eps0 values are missing after residual computation"
        di as error "Check: omega and L.omega may have no overlap with eps0 sample"
        exit 3003
    }
    
    // A.6 Raw statistics
    qui summ `eps0' if `eps0_sample' == 1
    local sigma_eps0_raw = r(sd)
    local mean_eps0 = r(mean)
    if `N_eps0_raw' == 1 & missing(`sigma_eps0_raw') {
        local sigma_eps0_raw = 0
    }
    
    if abs(`mean_eps0') > 0.1 {
        di as text "Warning: eps0 mean = " %8.6f `mean_eps0' " (not close to zero)"
    }
    
    // A.7 Trimming processing
    // Paper: Section 6.3.3 - "discard values smaller than 1st percentile
    //        or greater than 99th percentile"
    if "`notrimeps'" == "" {
        // Compute quantiles
        qui _pctile `eps0' if `eps0_sample' == 1, p(1 99)
        local eps0_p1 = r(r1)
        local eps0_p99 = r(r2)
        
        // Quantile validity check
        if `eps0_p1' >= `eps0_p99' {
            di as error "pte: eps0 quantile anomaly:" ///
                " p1 (`eps0_p1') >= p99 (`eps0_p99')"
            exit 3009
        }
        
        // Use the package's deterministic trim law instead of a runtime
        // dependency on winsor2. Semantically this matches the paper/DO
        // contract: drop values outside the 1st/99th percentiles.
        qui replace `eps0' = . if `eps0_sample' == 1 & ///
            (`eps0' < `eps0_p1' | `eps0' > `eps0_p99')
        
        // Post-trimming statistics
        qui summ `eps0' if `eps0_sample' == 1
        local sigma_eps0_trim = r(sd)
        local N_eps0_trim = r(N)
        if `N_eps0_trim' == 1 & missing(`sigma_eps0_trim') {
            local sigma_eps0_trim = 0
        }
        
        // Post-trimming sample size check
        if `N_eps0_trim' < 30 {
            di as error "pte: insufficient eps0 observations after" ///
                " trimming (N=`N_eps0_trim' < 30)"
            exit 3005
        }
    }
    else {
        local sigma_eps0_trim = `sigma_eps0_raw'
        local N_eps0_trim = `N_eps0_raw'
        local eps0_p1 = .
        local eps0_p99 = .
    }
    
    // A.8 Variance validity check
    // A degenerate innovation law with sigma = 0 is valid; only missing or
    // negative scales break the shock-distribution contract.
    if missing(`sigma_eps0_trim') {
        di as error "pte: eps0 variance unavailable after trimming"
        exit 3007
    }
    if `sigma_eps0_trim' < 0 {
        di as error "pte: negative variance in eps0 after trimming"
        exit 3007
    }
    
    if "`nolog'" == "" {
        di as text "  Sample: D==0 & L.D==0," ///
            " N_raw = `N_eps0_raw', N_trim = `N_eps0_trim'"
        di as text "  Sigma_raw = " %8.6f `sigma_eps0_raw' ///
            ", Sigma_trim = " %8.6f `sigma_eps0_trim'
    }
    
    // ===================================================================
    // Part B: eps1 distribution estimation (non-absorbing specific)
    // Paper: Appendix C.3 Eq.(C.3), D=D_{-1}=1 => eps1 = omega - h-bar_1
    // Note: Replication code has NO eps1 estimation logic.
    //       sigma_eps1=0.1 in pooled.do L11 is MC DGP parameter, not estimation.
    //       eps1 distribution estimation is pte's NEW feature for non-absorbing.
    // ===================================================================
    
    if "`nolog'" == "" {
        di as text _n "{hline 70}"
        di as text "Part B: eps1 Distribution Estimation (for ATT- simulation)"
        di as text "        [Non-absorbing treatment specific]"
        di as text "{hline 70}"
    }
    
    // B.1 Sample selection: D==1 & L.D==1
    tempvar eps1_sample
    qui gen byte `eps1_sample' = (`treatment' == 1 & L.`treatment' == 1)
    
    // B.2 Sample size check with absorbing detection
    qui count if `eps1_sample' == 1
    local N_eps1_raw = r(N)
    
    local degraded = 0
    local sigma_eps1_raw = .
    local sigma_eps1_trim = .
    local N_eps1_trim = 0
    local eps1_p1 = .
    local eps1_p99 = .
    
    if `N_eps1_raw' == 0 {
        // Detect if this is purely absorbing data
        qui count if `treatment' == 1 & L.`treatment' == 0
        local n_entry = r(N)
        qui count if `treatment' == 0 & L.`treatment' == 1
        local n_exit = r(N)
        
        if `n_exit' == 0 & `n_entry' > 0 {
            // Purely absorbing data: auto-degrade to single-direction mode
            di as text "Note: Absorbing treatment detected" ///
                " (entries=`n_entry', exits=0)"
            di as text "      Degrading to absorbing mode." ///
                " ATT- will be skipped."
            local degraded = 1
        }
        else {
            di as error "pte: no observations for eps1 sample (D==1 & L.D==1)"
            di as error "Recovery: Check if data has sustained treated observations"
            exit 3002
        }
    }
    
    // Remaining Part B steps only execute in non-degraded mode
    if `degraded' == 0 {
    
    if `N_eps1_raw' < 30 {
        di as text "Warning: eps1 sample has only `N_eps1_raw' observations (< 30)"
    }
    
    // B.3 Compute omega_hat_1 = h-bar_1(omega_{t-1})
    // Paper: Eq.(16) for d=1
    tempvar omega_hat_1 eps1
    qui gen double `omega_hat_1' = `rho_1'[1, 1]
    if `omegapoly' >= 1 {
        qui replace `omega_hat_1' = `omega_hat_1' + `rho_1'[1, 2] * `L_omega'
    }
    if `omegapoly' >= 2 {
        qui replace `omega_hat_1' = `omega_hat_1' + `rho_1'[1, 3] * `L_omega2'
    }
    if `omegapoly' >= 3 {
        qui replace `omega_hat_1' = `omega_hat_1' + `rho_1'[1, 4] * `L_omega3'
    }
    if `omegapoly' >= 4 {
        qui replace `omega_hat_1' = `omega_hat_1' + `rho_1'[1, 5] * `L_omega4'
    }
    // Only keep predictions for eps1 sample
    qui replace `omega_hat_1' = . if `eps1_sample' != 1
    
    // B.4 Compute residuals: eps1 = omega - omega_hat_1
    // Paper: Eq.(C.3) - eps1_it = omega_it - h-bar_1(omega_{it-1})
    qui gen double `eps1' = `omega' - `omega_hat_1' if `eps1_sample' == 1
    
    // B.4b Check for all-missing residuals
    qui count if `eps1_sample' == 1 & !missing(`eps1')
    if r(N) == 0 {
        di as error "pte: all eps1 values are missing after residual computation"
        di as error "Check: omega and L.omega may have no overlap with eps1 sample"
        exit 3004
    }
    
    // B.5 Raw statistics
    qui summ `eps1' if `eps1_sample' == 1
    local sigma_eps1_raw = r(sd)
    local mean_eps1 = r(mean)
    if `N_eps1_raw' == 1 & missing(`sigma_eps1_raw') {
        local sigma_eps1_raw = 0
    }
    
    if abs(`mean_eps1') > 0.1 {
        di as text "Warning: eps1 mean = " %8.6f `mean_eps1' " (not close to zero)"
    }
    
    // B.6 Trimming processing (symmetric with eps0)
    if "`notrimeps'" == "" {
        // Compute quantiles
        qui _pctile `eps1' if `eps1_sample' == 1, p(1 99)
        local eps1_p1 = r(r1)
        local eps1_p99 = r(r2)
        
        // Quantile validity check
        if `eps1_p1' >= `eps1_p99' {
            di as error "pte: eps1 quantile anomaly:" ///
                " p1 (`eps1_p1') >= p99 (`eps1_p99')"
            exit 3010
        }
        
        // Use the same deterministic trim law as eps0 so nonabsorbing shock
        // estimation does not depend on an external winsor2 installation.
        qui replace `eps1' = . if `eps1_sample' == 1 & ///
            (`eps1' < `eps1_p1' | `eps1' > `eps1_p99')
        
        // Post-trimming statistics
        qui summ `eps1' if `eps1_sample' == 1
        local sigma_eps1_trim = r(sd)
        local N_eps1_trim = r(N)
        if `N_eps1_trim' == 1 & missing(`sigma_eps1_trim') {
            local sigma_eps1_trim = 0
        }
        
        // Post-trimming sample size check
        if `N_eps1_trim' < 30 {
            di as error "pte: insufficient eps1 observations after" ///
                " trimming (N=`N_eps1_trim' < 30)"
            exit 3006
        }
    }
    else {
        local sigma_eps1_trim = `sigma_eps1_raw'
        local N_eps1_trim = `N_eps1_raw'
        local eps1_p1 = .
        local eps1_p99 = .
    }
    
    // B.7 Variance validity check
    // A degenerate innovation law with sigma = 0 is valid; only missing or
    // negative scales break the shock-distribution contract.
    if missing(`sigma_eps1_trim') {
        di as error "pte: eps1 variance unavailable after trimming"
        exit 3008
    }
    if `sigma_eps1_trim' < 0 {
        di as error "pte: negative variance in eps1 after trimming"
        exit 3008
    }
    
    if "`nolog'" == "" {
        di as text "  Sample: D==1 & L.D==1," ///
            " N_raw = `N_eps1_raw', N_trim = `N_eps1_trim'"
        di as text "  Sigma_raw = " %8.6f `sigma_eps1_raw' ///
            ", Sigma_trim = " %8.6f `sigma_eps1_trim'
    }
    
    } // end if `degraded' == 0
    
    // ===================================================================
    // Part C: Assumption verification
    // Paper: Appendix C.2 Assumption C.2, Example 4
    // ===================================================================
    
    if "`nolog'" == "" {
        di as text _n "{hline 70}"
        di as text "Part C: Assumption C.2 / C.2' Verification"
        di as text "{hline 70}"
    }
    
    // C.1 Assumption C.2 verification (ATT+ control group)
    // Need firms continuously untreated for ell periods ahead
    tempname N_eps0_control
    matrix `N_eps0_control' = J(1, `attperiods' + 1, .)
    
    forvalues ell = 0/`attperiods' {
        // Build sustained untreated condition
        local cond "`treatment' == 0"
        forvalues j = 1/`ell' {
            local cond "`cond' & F`j'.`treatment' == 0"
        }
        
        qui count if `cond'
        matrix `N_eps0_control'[1, `ell' + 1] = r(N)
        
        if r(N) < 30 {
            di as text "  Warning: Assumption C.2 -" ///
                " insufficient control for ell=`ell' (N=" r(N) " < 30)"
        }
    }
    
    // C.2 Assumption C.2' verification (ATT- control group)
    // pte's symmetric extension: need firms continuously treated
    tempname N_eps1_control
    matrix `N_eps1_control' = J(1, `attperiods' + 1, .)
    
    forvalues ell = 0/`attperiods' {
        // Build sustained treated condition
        local cond "`treatment' == 1"
        forvalues j = 1/`ell' {
            local cond "`cond' & F`j'.`treatment' == 1"
        }
        
        qui count if `cond'
        matrix `N_eps1_control'[1, `ell' + 1] = r(N)
        
        if r(N) < 30 {
            di as text "  Warning: Assumption C.2' -" ///
                " insufficient control for ell=`ell' (N=" r(N) " < 30)"
            di as text "           Note: C.2' is pte's symmetric extension"
        }
    }
    
    if "`nolog'" == "" {
        di as text "  C.2  (eps0 control): " _continue
        forvalues ell = 0/`attperiods' {
            di as text "ell=`ell':" %6.0f `N_eps0_control'[1, `ell'+1] " " _continue
        }
        di ""
        di as text "  C.2' (eps1 control): " _continue
        forvalues ell = 0/`attperiods' {
            di as text "ell=`ell':" %6.0f `N_eps1_control'[1, `ell'+1] " " _continue
        }
        di ""
    }
    
    // ===================================================================
    // Part D: ereturn setup
    // ===================================================================
    
    // Preserve the evolution bridge expected by direct ATT+ / ATT- consumers.
    ereturn matrix rho_0 = `rho_0'
    ereturn matrix rho_1 = `rho_1'

    // eps0 returns
    ereturn scalar sigma_eps0_raw = `sigma_eps0_raw'
    ereturn scalar sigma_eps0_trim = `sigma_eps0_trim'
    ereturn scalar sigma_eps0 = `sigma_eps0_trim'
    ereturn scalar N_eps0_raw = `N_eps0_raw'
    ereturn scalar N_eps0_trim = `N_eps0_trim'
    ereturn scalar eps0_p1 = `eps0_p1'
    ereturn scalar eps0_p99 = `eps0_p99'
    
    // eps1 returns
    ereturn scalar sigma_eps1_raw = `sigma_eps1_raw'
    ereturn scalar sigma_eps1_trim = `sigma_eps1_trim'
    if !missing(`sigma_eps1_trim') {
        ereturn scalar sigma_eps1 = `sigma_eps1_trim'
    }
    ereturn scalar N_eps1_raw = `N_eps1_raw'
    ereturn scalar N_eps1_trim = `N_eps1_trim'
    ereturn scalar eps1_p1 = `eps1_p1'
    ereturn scalar eps1_p99 = `eps1_p99'
    
    // Common returns
    ereturn scalar trimeps = ("`notrimeps'" == "")
    ereturn scalar nonabsorbing = 1
    ereturn scalar degraded = `degraded'
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar attperiods = `attperiods'
    ereturn local eps0_dist "normal"
    ereturn local eps1_dist "normal"
    
    // Assumption verification matrices
    ereturn matrix N_eps0_control = `N_eps0_control'
    ereturn matrix N_eps1_control = `N_eps1_control'
    
    // Command info
    ereturn local cmd "pte_eps_bidirectional"
    
    // ===================================================================
    // Diagnostic display
    // ===================================================================
    
    if "`nolog'" == "" {
        di as text _n "{hline 78}"
        di as text "{bf:Bidirectional Shock Distribution Estimation" ///
            " (Non-absorbing Treatment)}"
        di as text "{hline 78}"
        
        // eps0 diagnostics
        di as text _n "{bf:eps0 Distribution (for ATT+ simulation):}"
        di as text "  Sample condition:           D == 0 & L.D == 0"
        di as text "  Original observations:      " %8.0f `N_eps0_raw'
        di as text "  Trimmed observations:       " %8.0f `N_eps0_trim'
        if `N_eps0_raw' > 0 {
            local trim_pct0 = (`N_eps0_raw' - `N_eps0_trim') / `N_eps0_raw' * 100
            di as text "  Trimming percentage:        " %5.2f `trim_pct0' "%"
        }
        di as text "  Std. dev. (raw):            " %8.6f `sigma_eps0_raw'
        di as text "  Std. dev. (trimmed):        " %8.6f `sigma_eps0_trim' ///
            " {it:[used by ATT+ simulation]}"
        di as text "  Distribution assumption:    Normal(0, sigma^2)"
        if "`notrimeps'" == "" {
            di as text "  Trimming status:            Enabled (1%-99%)"
        }
        else {
            di as text "  Trimming status:            Disabled"
        }
        
        // eps1 diagnostics
        if `degraded' {
            di as text _n "{bf:eps1 Distribution:}" ///
                " N/A (degraded to absorbing mode, ATT- skipped)"
        }
        else {
            di as text _n "{bf:eps1 Distribution (for ATT- simulation):}" ///
                "  {it:[Non-absorbing specific]}"
            di as text "  Sample condition:           D == 1 & L.D == 1"
            di as text "  Original observations:      " %8.0f `N_eps1_raw'
            di as text "  Trimmed observations:       " %8.0f `N_eps1_trim'
            if `N_eps1_raw' > 0 {
                local trim_pct1 = (`N_eps1_raw' - `N_eps1_trim') / `N_eps1_raw' * 100
                di as text "  Trimming percentage:        " %5.2f `trim_pct1' "%"
            }
            di as text "  Std. dev. (raw):            " %8.6f `sigma_eps1_raw'
            di as text "  Std. dev. (trimmed):        " %8.6f `sigma_eps1_trim' ///
                " {it:[used by ATT- simulation]}"
            di as text "  Distribution assumption:    Normal(0, sigma^2)"
            if "`notrimeps'" == "" {
                di as text "  Trimming status:            Enabled (1%-99%)"
            }
            else {
                di as text "  Trimming status:            Disabled"
            }
        }
        
        // Assumption verification summary
        di as text _n "{bf:Note:}"
        di as text "  Assumption C.2' (ATT- control) is pte's symmetric extension,"
        di as text "  not directly from Proposition C.4. Use with caution."
        
        di as text _n "{hline 78}"
    }
    
end
