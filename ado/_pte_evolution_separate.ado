*! _pte_evolution_separate.ado
*! Separate Evolution Estimation for non-absorbing treatment
*! Estimates two independent evolution functions h_bar_0 and h_bar_1
*! by running separate OLS regressions on D=L.D=0 and D=L.D=1 samples.
*! Returns (eclass):
*! e(rho_0)     - 1x(P+1) matrix, untreated evolution parameters
*! e(rho_1)     - 1x(P+1) matrix, treated evolution parameters
*! e(N_h0)      - sample size for h_bar_0
*! e(N_h1)      - sample size for h_bar_1
*! e(n_missing) - observations with missing values
*! e(omegapoly) - polynomial order used

version 14.0
capture program drop _pte_evolution_separate
program define _pte_evolution_separate, eclass sortpreserve
    version 14.0
    
    // ================================================================
    // Syntax parsing
    // ================================================================
    syntax anything(name=omega_token) [if] [in], ///
        TREATment(name)                     /// treatment variable (required)
        [ OMEGApoly(integer 3)              /// polynomial order (1-4, default 3)
        NOWarn                              /// suppress warnings
        VERB ]
    
    local omega_words : word count `"`omega_token'"'
    if `omega_words' != 1 {
        di as error "[pte] Specify exactly one realized-productivity variable"
        exit 198
    }

    local omega `"`omega_token'"'
    local D `treatment'
    local verbose `verb'

    // Clear stale estimation state before input validation so an exact-name
    // failure cannot leak h_bar_0 / h_bar_1 from a prior successful run.
    ereturn clear
    
    // ================================================================
    // Step 1: Input validation
    // ================================================================
    
    // 1.1 Validate omegapoly range
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "[pte] omegapoly must be 1, 2, 3, or 4"
        exit 198
    }
    
    // 1.2 Validate panel structure
    capture _xt, trequired
    if _rc != 0 {
        di as error "[pte] Data must be xtset as panel"
        exit 459
    }
    local idvar = r(ivar)
    local timevar = r(tvar)
    
    // 1.3 Validate omega variable using the caller's exact token. Abbreviation
    // fallback would silently rebind the realized productivity state.
    capture confirm variable `omega', exact
    if _rc != 0 {
        di as error "[pte] Variable `omega' not found"
        di as error "[pte] Run productivity recovery first"
        exit 111
    }
    
    capture confirm numeric variable `omega'
    if _rc != 0 {
        di as error "[pte] Variable `omega' not found or not numeric"
        di as error "[pte] Run productivity recovery first"
        exit 111
    }
    
    // 1.4 Validate treatment variable using the caller's exact token so the
    // evolution law cannot silently switch to a shadow state variable.
    capture confirm variable `D', exact
    if _rc != 0 {
        di as error "[pte] Treatment variable `D' not found"
        exit 111
    }

    capture confirm numeric variable `D'
    if _rc != 0 {
        di as error "[pte] Treatment variable `D' not found or not numeric"
        exit 111
    }
    
    // 1.5 Mark sample
    marksample touse

    // 1.6 Treatment must remain binary on the active sample. The separate
    // h_bar_0 / h_bar_1 regressions are identified only for states 0 and 1.
    capture assert inlist(`D', 0, 1) if `touse' & !missing(`D')
    if _rc != 0 {
        di as error "[pte] Treatment variable `D' must be binary (0/1)"
        exit 450
    }
    
    // ================================================================
    // Step 2: Generate polynomial terms (tempvar for clean namespace)
    // ================================================================
    
    if "`verbose'" != "" {
        di as text _n "[pte] Generating polynomial terms (order=`omegapoly')..."
    }
    
    tempvar omega_p2 omega_p3 omega_p4
    
    if `omegapoly' >= 2 {
        qui gen double `omega_p2' = `omega'^2
    }
    
    if `omegapoly' >= 3 {
        qui gen double `omega_p3' = `omega'^3
    }
    
    if `omegapoly' == 4 {
        qui gen double `omega_p4' = `omega'^4
    }
    
    // ================================================================
    // Step 3: Sample selection and validation
    // ================================================================
    
    tempvar pair_base sample_h0 sample_h1
    qui gen byte `pair_base' = (`touse' == 1 & L.`touse' == 1)
    qui gen byte `sample_h0' = (`pair_base' & `D' == 0 & L.`D' == 0 & ///
        !missing(`omega') & !missing(L.`omega') & !missing(`D') & !missing(L.`D'))
    qui gen byte `sample_h1' = (`pair_base' & `D' == 1 & L.`D' == 1 & ///
        !missing(`omega') & !missing(L.`omega') & !missing(`D') & !missing(L.`D'))

    // 3.1 Count current rows whose pair is unusable because the lagged row is
    // outside the active sample or required lagged values are missing.
    qui count if `touse' & (!`pair_base' | missing(`omega') | missing(L.`omega') | ///
                  missing(`D') | missing(L.`D'))
    local n_missing = r(N)
    
    if `n_missing' > 0 & "`verbose'" != "" {
        di as text "[pte] Note: `n_missing' observations with" ///
            " missing values excluded"
    }
    
    // 3.2 Select h_bar_0 sample (untreated: D=0 & L.D=0)
    qui count if `sample_h0'
    local N_h0 = r(N)
    
    if "`verbose'" != "" {
        di as text "[pte] Sample for h_bar_0 (D=L.D=0): N = `N_h0'"
    }
    
    // 3.3 Validate h_bar_0 sample size
    if `N_h0' == 0 {
        di as error "[pte] No observations for h_bar_0 estimation (D=L.D=0)"
        exit 2000
    }
    
    if `N_h0' < 30 & "`nowarn'" == "" {
        di as text "[pte] Warning: Very small sample for h_bar_0" ///
            " (N=`N_h0' < 30); proceeding with OLS"
    }
    else if `N_h0' < 100 & "`nowarn'" == "" {
        di as text "[pte] Warning: Small sample for h_bar_0" ///
            " (N=`N_h0' < 100)"
    }
    
    // 3.4 Select h_bar_1 sample (treated: D=1 & L.D=1)
    qui count if `sample_h1'
    local N_h1 = r(N)
    
    if "`verbose'" != "" {
        di as text "[pte] Sample for h_bar_1 (D=L.D=1): N = `N_h1'"
    }
    
    // 3.5 Validate h_bar_1 sample size
    if `N_h1' == 0 {
        di as error "[pte] No observations for h_bar_1 estimation (D=L.D=1)"
        exit 2000
    }
    
    if `N_h1' < 30 & "`nowarn'" == "" {
        di as text "[pte] Warning: Very small sample for h_bar_1" ///
            " (N=`N_h1' < 30); proceeding with OLS"
    }
    else if `N_h1' < 100 & "`nowarn'" == "" {
        di as text "[pte] Warning: Small sample for h_bar_1" ///
            " (N=`N_h1' < 100)"
    }
    
    // ================================================================
    // Step 4: Build regression variable list
    // ================================================================
    
    if `omegapoly' == 1 {
        local regvars "L.`omega'"
    }
    else if `omegapoly' == 2 {
        local regvars "L.`omega' L.`omega_p2'"
    }
    else if `omegapoly' == 3 {
        local regvars "L.`omega' L.`omega_p2' L.`omega_p3'"
    }
    else if `omegapoly' == 4 {
        local regvars "L.`omega' L.`omega_p2' L.`omega_p3' L.`omega_p4'"
    }
    
    // ================================================================
    // Step 5: h_bar_0 evolution regression (D=0 & L.D=0)
    // ================================================================
    
    if "`verbose'" != "" {
        di as text _n "[pte] Estimating h_bar_0 (untreated evolution)..."
    }
    
    capture qui regress `omega' `regvars' if `sample_h0'
    
    if _rc != 0 {
        di as error "[pte] h_bar_0 regression failed (error code " _rc ")"
        exit _rc
    }
    
    // Extract coefficients into matrix
    tempname Rho_0
    matrix `Rho_0' = J(1, `omegapoly'+1, .)
    
    matrix `Rho_0'[1,1] = _b[_cons]
    
    if `omegapoly' >= 1 {
        matrix `Rho_0'[1,2] = _b[L.`omega']
    }
    if `omegapoly' >= 2 {
        matrix `Rho_0'[1,3] = _b[L.`omega_p2']
    }
    if `omegapoly' >= 3 {
        matrix `Rho_0'[1,4] = _b[L.`omega_p3']
    }
    if `omegapoly' == 4 {
        matrix `Rho_0'[1,5] = _b[L.`omega_p4']
    }
    
    // Validate coefficient extraction
    forv j = 1/`=`omegapoly'+1' {
        if missing(`Rho_0'[1,`j']) {
            di as error "[pte] Failed to extract coefficient `j' for h_bar_0"
            exit 303
        }
    }
    
    // ================================================================
    // Step 6: h_bar_1 evolution regression (D=1 & L.D=1)
    // ================================================================
    
    if "`verbose'" != "" {
        di as text _n "[pte] Estimating h_bar_1 (treated evolution)..."
    }
    
    capture qui regress `omega' `regvars' if `sample_h1'
    
    if _rc != 0 {
        di as error "[pte] h_bar_1 regression failed (error code " _rc ")"
        exit _rc
    }
    
    // Extract coefficients into matrix
    tempname Rho_1
    matrix `Rho_1' = J(1, `omegapoly'+1, .)
    
    matrix `Rho_1'[1,1] = _b[_cons]
    
    if `omegapoly' >= 1 {
        matrix `Rho_1'[1,2] = _b[L.`omega']
    }
    if `omegapoly' >= 2 {
        matrix `Rho_1'[1,3] = _b[L.`omega_p2']
    }
    if `omegapoly' >= 3 {
        matrix `Rho_1'[1,4] = _b[L.`omega_p3']
    }
    if `omegapoly' == 4 {
        matrix `Rho_1'[1,5] = _b[L.`omega_p4']
    }
    
    // Validate coefficient extraction
    forv j = 1/`=`omegapoly'+1' {
        if missing(`Rho_1'[1,`j']) {
            di as error "[pte] Failed to extract coefficient `j' for h_bar_1"
            exit 303
        }
    }
    
    // ================================================================
    // Step 7: Matrix naming and formatting
    // ================================================================
    
    matrix rownames `Rho_0' = "h_0"
    matrix rownames `Rho_1' = "h_1"
    
    if `omegapoly' == 1 {
        matrix colnames `Rho_0' = "rho0" "rho1"
        matrix colnames `Rho_1' = "rho0" "rho1"
    }
    else if `omegapoly' == 2 {
        matrix colnames `Rho_0' = "rho0" "rho1" "rho2"
        matrix colnames `Rho_1' = "rho0" "rho1" "rho2"
    }
    else if `omegapoly' == 3 {
        matrix colnames `Rho_0' = "rho0" "rho1" "rho2" "rho3"
        matrix colnames `Rho_1' = "rho0" "rho1" "rho2" "rho3"
    }
    else if `omegapoly' == 4 {
        matrix colnames `Rho_0' = "rho0" "rho1" "rho2" "rho3" "rho4"
        matrix colnames `Rho_1' = "rho0" "rho1" "rho2" "rho3" "rho4"
    }
    
    // ================================================================
    // Step 8: ereturn setup
    // ================================================================
    
    ereturn clear
    
    // Matrix return values
    ereturn matrix rho_0 = `Rho_0'
    ereturn matrix rho_1 = `Rho_1'
    
    // Scalar return values
    ereturn scalar N_h0 = `N_h0'
    ereturn scalar N_h1 = `N_h1'
    ereturn scalar n_missing = `n_missing'
    ereturn scalar omegapoly = `omegapoly'
    
    // Macro return values
    ereturn local cmd "_pte_evolution_separate"
    ereturn local depvar "`omega'"
    ereturn local treatment "`D'"
    
    // ================================================================
    // Step 9: Output report (if verbose)
    // ================================================================
    
    if "`verbose'" != "" {
        di as text _n "{hline 70}"
        di as text "Separate Evolution Estimation Results"
        di as text "{hline 70}"
        
        di as text _n "h_bar_0 (Untreated Evolution):"
        di as text "  Sample: D=L.D=0, N = " as result "`N_h0'"
        matrix list e(rho_0), noheader
        
        di as text _n "h_bar_1 (Treated Evolution):"
        di as text "  Sample: D=L.D=1, N = " as result "`N_h1'"
        matrix list e(rho_1), noheader
        
        di as text _n "{hline 70}"
        di as text "omegapoly = " as result "`omegapoly'"
        if `n_missing' > 0 {
            di as text "Missing observations = " as result "`n_missing'"
        }
        di as text "{hline 70}"
    }
    
end
