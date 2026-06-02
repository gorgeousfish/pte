*! _pte_diag_kstest_norm.ado
*! K-S Normality Test for eps0
*!
*! Tests whether eps0 (productivity shocks) follows a normal distribution.
*! Two complementary tests:
*!   1. K-S test: standardized eps0 vs N(0,1) [pte enhancement]
*!   2. sktest: D'Agostino-Pearson skewness-kurtosis test [replication consistent]

version 14.0
program define _pte_diag_kstest_norm, rclass
    version 14.0
    syntax , [eps0(varname) NOKStest NOSKtest NOTRIMeps]
    
    // =========================================================
    // 1. Variable validation
    // =========================================================
    
    // Determine eps0 variable
    if "`eps0'" == "" {
        capture confirm var _pte_eps0
        if _rc == 0 {
            local eps0 "_pte_eps0"
        }
        else {
            di as error "Error: Specify eps0() or ensure _pte_eps0 exists"
            exit 198
        }
    }
    
    // Verify eps0 is numeric
    capture confirm numeric var `eps0'
    if _rc != 0 {
        di as error "Error: `eps0' must be numeric"
        exit 198
    }

    quietly _pte_diag_eps0_support_if, epsvar(`eps0') ///
        context("normality diagnostics")
    local use_support = r(uses_support)
    
    tempvar eps0_work
    qui gen double `eps0_work' = `eps0'
    if `use_support' {
        qui replace `eps0_work' = . if _pte_eps0_ind != 1
    }

    // Default public path follows the trimmed-eps0 Gaussian approximation.
    if "`notrimeps'" == "" {
        quietly _pctile `eps0_work', p(1 99)
        local p1_cut = r(r1)
        local p99_cut = r(r2)
        quietly replace `eps0_work' = . if `eps0_work' < `p1_cut' | `eps0_work' > `p99_cut'
        local sample_label "trimmed 1%-99%"
    }
    else {
        local sample_label "raw (notrimeps)"
    }

    // Count non-missing observations on the effective diagnostic sample
    qui count if !mi(`eps0_work')
    local N_obs = r(N)
    
    if `N_obs' == 0 {
        di as error "Error: All eps0 values are missing"
        exit 2000
    }
    
    // Sample size warnings
    local skip_sktest = 0
    if `N_obs' < 8 {
        local skip_sktest = 1
    }
    
    // =========================================================
    // 2. Descriptive statistics
    // =========================================================
    
    qui summ `eps0_work'
    local mean_eps0 = r(mean)
    local sd_eps0 = r(sd)
    if `N_obs' == 1 & mi(`sd_eps0') {
        local sd_eps0 = 0
    }
    
    // Detailed statistics (skewness, kurtosis)
    qui summ `eps0_work', detail
    local skewness = r(skewness)
    local kurtosis = r(kurtosis)
    local N_final = r(N)
    local p1 = r(p1)
    local p99 = r(p99)
    local median_eps0 = r(p50)
    
    // =========================================================
    // 3. Output header
    // =========================================================
    
    di as text _n "K-S Normality Test: eps0 Distribution"
    di as text "{hline 60}"
    di as text "H0: eps0 follows a normal distribution"
    di as text "Paper reference: Section 6.3.3"
    di as text ""
    di as text "  Sample      = " as result "`sample_label'"
    di as text "  N           = " %10.0f `N_final'
    di as text "  Mean        = " %10.6f `mean_eps0'
    di as text "  Std. Dev.   = " %10.6f `sd_eps0'
    di as text "  Skewness    = " %10.6f `skewness'
    di as text "  Kurtosis    = " %10.6f `kurtosis'
    di as text ""
    
    if `N_obs' < 30 {
        di as text "  {bf:Warning}: Small sample size (N = `N_obs')"
        di as text "  Normality tests may have low power"
        di as text ""
    }

    if `sd_eps0' == 0 {
        di as text "Test 1: K-S Normality Test (pte enhancement)"
        di as text "  SKIPPED: degenerate eps0 law (sd = 0)"
        di as text ""
        if "`nosktest'" == "" {
            di as text "Test 2: D'Agostino-Pearson sktest (replication consistent)"
            di as text "  SKIPPED: degenerate eps0 law (sd = 0)"
            di as text ""
        }
        else {
            di as text "Test 2: sktest - SKIPPED (nosktest)"
            di as text ""
        }

        di as text "{hline 60}"
        di as text "Overall: SKIPPED - Degenerate eps0 law leaves normality statistics undefined"
        di as text "{hline 60}"

        return scalar ks_D_norm = .
        return scalar ks_p_norm = .
        return scalar sktest_chi2 = .
        return scalar sktest_p = .
        return scalar norm_pass = .
        return scalar N_eps0_norm = `N_final'
        return scalar eps0_mean = `mean_eps0'
        return scalar eps0_sd = 0
        return scalar eps0_skewness = `skewness'
        return scalar eps0_kurtosis = `kurtosis'
        exit
    }
    
    // =========================================================
    // 4. K-S normality test (pte enhancement)
    // =========================================================
    
    local ks_D_norm = .
    local ks_p_norm = .
    local ks_pass = .
    
    if "`nokstest'" == "" {
        // Standardize eps0
        tempvar eps0_std
        qui gen double `eps0_std' = (`eps0_work' - `mean_eps0') / `sd_eps0'
        
        // Single-sample K-S test vs N(0,1)
        qui ksmirnov `eps0_std' = normal(`eps0_std')
        local ks_D_norm = r(D)
        local ks_p_norm = r(p)
        local ks_pass = (`ks_p_norm' >= 0.05)
        
        di as text "Test 1: K-S Normality Test (pte enhancement)"
        di as text "  Standardized eps0 vs N(0,1)"
        di as text "  D     = " %10.6f `ks_D_norm'
        di as text "  p     = " %10.6f `ks_p_norm'
        if `ks_pass' {
            di as text "  Result: PASS (p >= 0.05)"
        }
        else {
            di as error "  Result: FAIL (p < 0.05)"
        }
        di as text ""
    }
    else {
        di as text "Test 1: K-S Normality Test - SKIPPED (nokstest)"
        di as text ""
    }
    
    // =========================================================
    // 5. sktest (replication consistent)
    // =========================================================
    
    local sktest_chi2 = .
    local sktest_p = .
    local sktest_pass = .
    local sktest_skew_z = .
    local sktest_kurt_z = .
    local sktest_skew_p = .
    local sktest_kurt_p = .
    
    if "`nosktest'" == "" {
        if `skip_sktest' == 0 {
            // sktest uses the effective diagnostic sample in original units.
            // Consistent with replication code: identification_check.do L96
            qui sktest `eps0_work'
            local sktest_chi2 = r(chi2)
            
            // Stata version compatibility:
            // Stata 14-17: r(P) for joint p-value
            // Stata 18+:  r(p_chi2) for joint p-value
            local sktest_p = r(P)
            if mi(`sktest_p') {
                local sktest_p = r(p_chi2)
            }
            
            // Capture component statistics if available
            // Stata 14-17: r(Zs), r(Zk), r(Ps), r(Pk)
            // Stata 18+:  r(p_skew), r(p_kurt)
            capture {
                local sktest_skew_z = r(Zs)
                local sktest_kurt_z = r(Zk)
                local sktest_skew_p = r(Ps)
                local sktest_kurt_p = r(Pk)
            }
            // Stata 18+ fallback
            if mi(`sktest_skew_p') {
                capture {
                    local sktest_skew_p = r(p_skew)
                    local sktest_kurt_p = r(p_kurt)
                }
            }
            
            local sktest_pass = (`sktest_p' >= 0.05)
            
            di as text "Test 2: D'Agostino-Pearson sktest (replication consistent)"
            di as text "  Uses " as result "`sample_label'" as text " eps0 (not standardized)"
            di as text "  chi2(2) = " %10.4f `sktest_chi2'
            di as text "  p       = " %10.6f `sktest_p'
            if !mi(`sktest_skew_p') {
                di as text "  Skewness z = " %8.4f `sktest_skew_z' ///
                    "  (p = " %6.4f `sktest_skew_p' ")"
            }
            if !mi(`sktest_kurt_p') {
                di as text "  Kurtosis z = " %8.4f `sktest_kurt_z' ///
                    "  (p = " %6.4f `sktest_kurt_p' ")"
            }
            if `sktest_pass' {
                di as text "  Result: PASS (p >= 0.05)"
            }
            else {
                di as error "  Result: FAIL (p < 0.05)"
            }
        }
        else {
            di as text "Test 2: sktest - SKIPPED (N < 8)"
            local sktest_pass = 1
        }
        di as text ""
    }
    else {
        di as text "Test 2: sktest - SKIPPED (nosktest)"
        di as text ""
    }
    
    // =========================================================
    // 6. Overall judgment
    // =========================================================
    
    // norm_pass: both tests must pass (or be skipped)
    local norm_pass = 1
    if !mi(`ks_pass') & `ks_pass' == 0 {
        local norm_pass = 0
    }
    if !mi(`sktest_pass') & `sktest_pass' == 0 {
        local norm_pass = 0
    }
    
    di as text "{hline 60}"
    if `norm_pass' {
        di as text "Overall: PASS - Cannot reject normality of eps0"
    }
    else {
        di as error "Overall: WARN - Departure from normality detected"
        di as text "  Note: Bootstrap inference remains valid regardless."
        di as text "  The normality assumption simplifies counterfactual"
        di as text "  simulation but is not required for identification."
    }
    di as text "{hline 60}"
    
    // =========================================================
    // 7. Return values
    // =========================================================
    
    // Descriptive statistics
    return scalar N_eps0_norm = `N_final'
    return scalar eps0_mean = `mean_eps0'
    return scalar eps0_sd = `sd_eps0'
    return scalar eps0_skewness = `skewness'
    return scalar eps0_kurtosis = `kurtosis'
    
    // K-S normality test (pte enhancement)
    return scalar ks_D_norm = `ks_D_norm'
    return scalar ks_p_norm = `ks_p_norm'
    
    // sktest (replication consistent)
    return scalar sktest_chi2 = `sktest_chi2'
    return scalar sktest_p = `sktest_p'
    
    // Component statistics (may be missing)
    return scalar sktest_skew_z = `sktest_skew_z'
    return scalar sktest_kurt_z = `sktest_kurt_z'
    return scalar sktest_skew_p = `sktest_skew_p'
    return scalar sktest_kurt_p = `sktest_kurt_p'
    
    // Overall judgment
    return scalar norm_pass = `norm_pass'
    return scalar ks_norm_pass = cond(mi(`ks_pass'), ., `ks_pass')
    return scalar sktest_norm_pass = cond(mi(`sktest_pass'), ., `sktest_pass')
    
end
