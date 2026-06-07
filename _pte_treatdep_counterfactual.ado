*! _pte_treatdep_counterfactual.ado
*! Simulates omega_0 paths for treatment-dependent production functions

version 14.0
capture program drop _pte_treatdep_counterfactual
program define _pte_treatdep_counterfactual, eclass
    version 14.0
    syntax , attperiods(integer) [nodiagnose]
    
    // ================================================================
    // Step 1: Validate e(rho_0) matrix exists (Task 1)
    // ================================================================
    capture confirm matrix e(rho_0)
    if _rc != 0 {
        di as error "Error: e(rho_0) matrix not found."
        di as error "  Run _pte_treatdep_evolution first."
        exit 198
    }
    
    // ================================================================
    // Step 2: Extract omegapoly parameter (Task 2)
    // ================================================================
    local omegapoly = e(omegapoly)
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "Error: omegapoly must be between 1 and 4"
        exit 198
    }
    
    // ================================================================
    // Step 3: Extract rho coefficients from e(rho_0) ONLY (Task 3-4)
    // CRITICAL: Only h_bar_0 parameters, NO gamma/delta
    // ================================================================
    tempname Rho_0
    matrix `Rho_0' = e(rho_0)
    
    // Verify dimension: should be 1 x (omegapoly+1)
    local expected_cols = `omegapoly' + 1
    if colsof(`Rho_0') != `expected_cols' {
        di as error "Error: e(rho_0) has " colsof(`Rho_0') " columns, expected " `expected_cols'
        exit 198
    }
    
    // Extract coefficients
    scalar rho0 = `Rho_0'[1, 1]
    scalar rho1 = `Rho_0'[1, 2]
    if `omegapoly' >= 2 scalar rho2 = `Rho_0'[1, 3]
    if `omegapoly' >= 3 scalar rho3 = `Rho_0'[1, 4]
    if `omegapoly' >= 4 scalar rho4 = `Rho_0'[1, 5]
    
    // ================================================================
    // Step 4: Validate required variables (Task 5)
    // ================================================================
    confirm variable eps0_sim
    confirm variable eps0_sim_trim
    confirm variable nt
    confirm variable omega
    
    qui count if !missing(eps0_sim)
    if r(N) == 0 {
        di as error "Error: eps0_sim variable is empty"
        exit 198
    }
    
    // Validate panel structure
    qui _xt, trequired
    
    // ================================================================
    // Step 5: Clean and initialize variables (Task 6-9)
    // ================================================================
    cap drop omega_0
    cap drop omega_0_trim
    cap drop omega_02
    cap drop omega_02_trim
    cap drop omega_03
    cap drop omega_03_trim
    cap drop omega_04
    cap drop omega_04_trim
    
    qui gen double omega_0 = .
    qui gen double omega_0_trim = .
    
    if `omegapoly' >= 2 {
        qui gen double omega_02 = .
        qui gen double omega_02_trim = .
    }
    if `omegapoly' >= 3 {
        qui gen double omega_03 = .
        qui gen double omega_03_trim = .
    }
    if `omegapoly' >= 4 {
        qui gen double omega_04 = .
        qui gen double omega_04_trim = .
    }
    
    // ================================================================
    // Step 6: Compute nt=0 using observed L.omega (Task 11-12)
    // h_bar_0(omega_{t-1}) + eps0_sim
    // At nt=0, use OBSERVED lagged omega as starting point
    // ================================================================
    
    // Build h_bar_0 formula for nt=0 (using L.omega)
    qui replace omega_0 = rho0 + rho1*L.omega if nt == 0
    if `omegapoly' >= 2 {
        qui replace omega_0 = omega_0 + rho2*(L.omega)^2 if nt == 0
    }
    if `omegapoly' >= 3 {
        qui replace omega_0 = omega_0 + rho3*(L.omega)^3 if nt == 0
    }
    if `omegapoly' >= 4 {
        qui replace omega_0 = omega_0 + rho4*(L.omega)^4 if nt == 0
    }
    qui replace omega_0 = omega_0 + L.eps0_sim if nt == 0
    
    // Trim version (same h_bar_0 at nt=0, different eps)
    qui replace omega_0_trim = rho0 + rho1*L.omega if nt == 0
    if `omegapoly' >= 2 {
        qui replace omega_0_trim = omega_0_trim + rho2*(L.omega)^2 if nt == 0
    }
    if `omegapoly' >= 3 {
        qui replace omega_0_trim = omega_0_trim + rho3*(L.omega)^3 if nt == 0
    }
    if `omegapoly' >= 4 {
        qui replace omega_0_trim = omega_0_trim + rho4*(L.omega)^4 if nt == 0
    }
    qui replace omega_0_trim = omega_0_trim + L.eps0_sim_trim if nt == 0
    
    // Task 13: Inline verification of nt=0 computation
    if "`diagnose'" == "" {
        qui count if !missing(omega_0) & nt == 0
        if r(N) == 0 {
            di as error "Error: No omega_0 values computed at nt=0"
            exit 198
        }
    }
    
    // ================================================================
    // Step 7: Recursive computation for nt=1..attperiods (Task 14-20)
    // Order: update high-order terms at nt=s-1 FIRST, then compute omega_0 at nt=s
    // ================================================================
    forv s = 1/`attperiods' {
        
        // Update high-order terms at nt=s-1 (BEFORE computing omega_0 at nt=s)
        if `omegapoly' >= 2 {
            qui replace omega_02 = omega_0^2 if nt == `s' - 1
            qui replace omega_02_trim = omega_0_trim^2 if nt == `s' - 1
        }
        if `omegapoly' >= 3 {
            qui replace omega_03 = omega_0^3 if nt == `s' - 1
            qui replace omega_03_trim = omega_0_trim^3 if nt == `s' - 1
        }
        if `omegapoly' >= 4 {
            qui replace omega_04 = omega_0^4 if nt == `s' - 1
            qui replace omega_04_trim = omega_0_trim^4 if nt == `s' - 1
        }
        
        // Compute omega_0 at nt=s using SIMULATED L.omega_0
        qui replace omega_0 = rho0 + rho1*L.omega_0 if nt == `s'
        if `omegapoly' >= 2 {
            qui replace omega_0 = omega_0 + rho2*L.omega_02 if nt == `s'
        }
        if `omegapoly' >= 3 {
            qui replace omega_0 = omega_0 + rho3*L.omega_03 if nt == `s'
        }
        if `omegapoly' >= 4 {
            qui replace omega_0 = omega_0 + rho4*L.omega_04 if nt == `s'
        }
        qui replace omega_0 = omega_0 + L.eps0_sim if nt == `s'
        
        // Trim version
        qui replace omega_0_trim = rho0 + rho1*L.omega_0_trim if nt == `s'
        if `omegapoly' >= 2 {
            qui replace omega_0_trim = omega_0_trim + rho2*L.omega_02_trim if nt == `s'
        }
        if `omegapoly' >= 3 {
            qui replace omega_0_trim = omega_0_trim + rho3*L.omega_03_trim if nt == `s'
        }
        if `omegapoly' >= 4 {
            qui replace omega_0_trim = omega_0_trim + rho4*L.omega_04_trim if nt == `s'
        }
        qui replace omega_0_trim = omega_0_trim + L.eps0_sim_trim if nt == `s'
        
        // Task 20: Progress display
        if "`diagnose'" == "" {
            qui count if !missing(omega_0) & nt == `s'
            di as text "  nt=`s': " r(N) " obs computed"
        }
    }
    
    // ================================================================
    // Step 8: Validation (Task 21-23)
    // ================================================================
    
    // Verify nt=-1 has missing omega_0
    qui count if !missing(omega_0) & nt == -1
    if r(N) != 0 {
        di as error "Warning: omega_0 should be missing for nt=-1, found " r(N) " non-missing"
    }
    
    // Task 22: Verify recursive completeness for treatment group
    // Note: treat variable may not exist in all contexts, use quiet check
    capture confirm variable treat
    if _rc == 0 {
        qui count if missing(omega_0) & nt >= 0 & nt <= `attperiods' & treat == 1
        if r(N) != 0 {
            di as error "Warning: Found " r(N) " missing omega_0 in treatment group (nt>=0)"
        }
    }
    
    // Task 23: Verify high-order term precision
    if `omegapoly' >= 2 {
        tempvar check_02
        qui gen double `check_02' = abs(omega_02 - omega_0^2) if nt >= 0 & !missing(omega_02)
        qui summarize `check_02'
        if r(N) > 0 & r(max) > 1e-10 {
            di as error "Warning: omega_02 precision issue (max diff = " r(max) ")"
        }
    }
    if `omegapoly' >= 3 {
        tempvar check_03
        qui gen double `check_03' = abs(omega_03 - omega_0^3) if nt >= 0 & !missing(omega_03)
        qui summarize `check_03'
        if r(N) > 0 & r(max) > 1e-10 {
            di as error "Warning: omega_03 precision issue (max diff = " r(max) ")"
        }
    }
    
    // Store summary statistics
    qui summarize omega_0 if nt >= 0
    local omega0_mean = r(mean)
    local omega0_sd = r(sd)
    local omega0_n = r(N)
    
    qui summarize omega_0_trim if nt >= 0
    local omega0_trim_mean = r(mean)
    local omega0_trim_sd = r(sd)
    
    // ================================================================
    // Step 9: Set return values
    // ================================================================
    ereturn scalar omega0_sim_mean = `omega0_mean'
    ereturn scalar omega0_sim_sd = `omega0_sd'
    ereturn scalar omega0_sim_n = `omega0_n'
    ereturn scalar omega0_trim_mean = `omega0_trim_mean'
    ereturn scalar omega0_trim_sd = `omega0_trim_sd'
    ereturn scalar attperiods = `attperiods'
    
    // ================================================================
    // Step 10: Display results (unless nodiagnose)
    // ================================================================
    if "`diagnose'" == "" {
        di as text ""
        di as text "Counterfactual simulation (h_bar_0 only):"
        di as text "  omegapoly = " as result `omegapoly'
        di as text "  attperiods = " as result `attperiods'
        di as text "  N simulated = " as result `omega0_n'
        di as text ""
        di as text "  omega_0 (untrimmed): mean = " as result %9.4f `omega0_mean' ///
            as text ", sd = " as result %9.4f `omega0_sd'
        di as text "  omega_0 (trimmed):   mean = " as result %9.4f `omega0_trim_mean' ///
            as text ", sd = " as result %9.4f `omega0_trim_sd'
        di as text ""
        di as text "  Note: Uses ONLY rho0~rho`omegapoly' from e(rho_0)"
        di as text "        NO treatment interaction (gamma/delta) used"
    }
    
    // Clean up scalars
    scalar drop rho0 rho1
    if `omegapoly' >= 2 scalar drop rho2
    if `omegapoly' >= 3 scalar drop rho3
    if `omegapoly' >= 4 scalar drop rho4
    
end
