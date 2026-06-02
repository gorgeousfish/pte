*! _pte_stage1_diag.ado
*! Diagnostics for the live Stage-1 regression. This helper assumes e(cmd)
*! still points to regress and checks whether the supplied phi matches the
*! paper/DO construction predict(xb) minus the controls that actually entered
*! Stage 1. Correlation with controls is descriptive only; the identity check
*! is the contractual test.

version 14.0
capture program drop _pte_stage1_diag
program define _pte_stage1_diag, rclass
    version 14.0
    
    syntax [if] [in], PHI(varname) PFUNC(string) ///
        [DIAGnose] [STRICT] [CONTROLvars(varlist)] ///
        [R2min(real 0.8)] [VIFmax(real 10)] [CORRmax(real 0.05)]

    marksample touse

    local verbose = ("`diagnose'" != "")
    local exit_on_error = ("`strict'" != "")

    if !inlist("`pfunc'", "cd", "translog") {
        di as error "pfunc() must be 'cd' or 'translog'"
        exit 198
    }

    if `r2min' <= 0 | `r2min' > 1 {
        di as error "r2min() must be in (0, 1]"
        exit 198
    }

    if `vifmax' < 1 {
        di as error "vifmax() must be >= 1"
        exit 198
    }

    if `corrmax' <= 0 | `corrmax' > 1 {
        di as error "corrmax() must be in (0, 1]"
        exit 198
    }

    if "`e(cmd)'" != "regress" {
        di as error "Error: No regression results found"
        di as error "  _pte_stage1_diag must be called after first-stage regression"
        di as error "  Expected: e(cmd) = regress"
        di as error "  Found: e(cmd) = `e(cmd)'"
        exit 301
    }
    
    capture confirm variable `phi'
    if _rc {
        di as error "Error: phi variable '`phi'' not found"
        exit 111
    }

    quietly count if `touse' & !mi(`phi')
    local phi_N = r(N)
    if `phi_N' == 0 {
        di as error "Error: No valid observations in phi variable"
        exit 2000
    }

    if mi(e(r2)) | e(r2) < 0 | e(r2) > 1 {
        di as error "Error: e(r2) is invalid or missing"
        di as error "  e(r2) = " e(r2)
        exit 498
    }

    // Infer controls from the live coefficient vector when possible. The
    // subtraction contract is about what actually entered Stage 1, not what
    // a canned grouped-time template would have used in another sample.
    if "`controlvars'" != "" {
        local control_vars "`controlvars'"
    }
    else {
        local _coef_controls ""
        local _coefnames : colfullnames e(b)
        local _stage1_polyvars ///
            "lnl lnm lnk l1 m1 k1 l2 m2 k2 l3 m3 k3 l1m1 l1k1 m1k1 l1m2 l1k2 m1k2 m1l2 k1l2 k1m2 k1l1m1"
        local _looks_like_stage1 = 0
        foreach ctrl of local _coefnames {
            if "`ctrl'" == "_cons" {
                continue
            }
            local _is_stage1_poly : list ctrl in _stage1_polyvars
            if `_is_stage1_poly' {
                local _looks_like_stage1 = 1
                continue, break
            }
        }
        foreach ctrl of local _coefnames {
            if "`ctrl'" == "_cons" {
                continue
            }
            if `_looks_like_stage1' {
                local _is_stage1_poly : list ctrl in _stage1_polyvars
            }
            else {
                local _is_stage1_poly = 0
                if !regexm("`ctrl'", "^t$|^t[0-9]+$|^_pte_t$|^_pte_t[0-9]+$") {
                    continue
                }
            }
            if !`_is_stage1_poly' {
                capture confirm variable `ctrl', exact
                if !_rc {
                    local _coef_controls "`_coef_controls' `ctrl'"
                }
            }
        }
        if "`_coef_controls'" != "" {
            local control_vars "`_coef_controls'"
        }
        else {
            local control_vars ""
        }
    }
    local control_vars : list retokenize control_vars

    foreach ctrl of local control_vars {
        capture confirm variable `ctrl'
        if _rc {
            di as error "Error: Control variable '`ctrl'' not found"
            di as error "  pfunc = `pfunc' requires variable: `ctrl'"
            exit 111
        }
    }
    
    local n_controls : word count `control_vars'

    if `verbose' {
        di as text ""
        di as text "{hline 70}"
        di as text "First-Stage Regression Diagnostics Configuration"
        di as text "{hline 70}"
        di as text "  phi variable:    `phi'"
        di as text "  pfunc:           `pfunc'"
        di as text "  diagnose mode:   `verbose'"
        di as text "  strict mode:     `exit_on_error'"
        di as text "  R2 threshold:    `r2min'"
        di as text "  VIF threshold:   `vifmax'"
        di as text "  Corr threshold:  `corrmax'"
        di as text "  Control vars:    `control_vars'"
        di as text "  Valid phi obs:   `phi_N'"
        di as text "{hline 70}"
        di as text ""
    }
    
    local r2 = e(r2)
    local r2_adj = e(r2_a)

    local r2_status = "ok"
    if `r2' < 0.5 {
        local r2_status = "critical"
    }
    else if `r2' < `r2min' {
        local r2_status = "warning"
    }
    
    if "`r2_status'" == "critical" {
        di as error ""
        di as error "{hline 70}"
        di as error "CRITICAL: First-stage R-squared = " %5.3f `r2' " < 0.5"
        di as error "{hline 70}"
        di as error "The polynomial approximation has very poor fit."
        di as error "Possible causes:"
        di as error "  1. Insufficient polynomial terms (increase poly order)"
        di as error "  2. Severe data quality issues"
        di as error "  3. Model misspecification"
        di as error "{hline 70}"
        
        if `exit_on_error' {
            exit 498
        }
    }
    else if "`r2_status'" == "warning" & `verbose' {
        di as text ""
        di as text "Warning: First-stage R-squared = " %5.3f `r2' " < `r2min'"
        di as text "  Consider adding more polynomial terms or checking data quality"
        di as text "  Adjusted R-squared = " %5.3f `r2_adj'
    }
    else if `verbose' {
        di as text ""
        di as text "R-squared check: PASSED"
        di as text "  R-squared = " %5.3f `r2' " (threshold: `r2min')"
        di as text "  Adjusted R-squared = " %5.3f `r2_adj'
    }
    
    local max_vif = .
    local max_vif_var = ""
    local mean_vif = .
    local vif_status = "ok"
    
    capture quietly estat vif
    if _rc == 0 {
        local max_vif = 0
        local sum_vif = 0
        local count_vif = 0

        forvalues i = 1/100 {
            capture local this_vif = r(vif_`i')
            if _rc != 0 {
                continue, break
            }
            if `this_vif' < . {
                local sum_vif = `sum_vif' + `this_vif'
                local count_vif = `count_vif' + 1
                
                if `this_vif' > `max_vif' {
                    local max_vif = `this_vif'
                    local max_vif_var = "`r(name_`i')'"
                }
            }
        }

        if `count_vif' > 0 {
            local mean_vif = `sum_vif' / `count_vif'
        }

        if `max_vif' >= 10 {
            local vif_status = "warning"
        }
        else if `max_vif' >= 5 {
            local vif_status = "acceptable"
        }
    }
    else {
        local max_vif = .
        local max_vif_var = "(singular)"
        local mean_vif = .
        local vif_status = "critical"
        
        if `verbose' {
            di as error ""
            di as error "Warning: VIF calculation failed (singular matrix?)"
            di as error "  This may indicate perfect collinearity among regressors"
        }
    }

    if "`vif_status'" == "warning" {
        di as error ""
        di as error "Warning: High multicollinearity detected"
        di as error "  Max VIF = " %8.2f `max_vif' " (variable: `max_vif_var')"
        di as error "  Mean VIF = " %8.2f `mean_vif'
        di as error "  Threshold: VIF > `vifmax' indicates problematic collinearity"
        di as error "  Consider:"
        di as error "    - Removing redundant polynomial terms"
        di as error "    - Centering variables before creating polynomials"
        di as error "    - Using orthogonal polynomials"
    }
    else if `verbose' & `max_vif' != . {
        di as text ""
        di as text "VIF check: PASSED"
        di as text "  Max VIF = " %5.2f `max_vif' " (variable: `max_vif_var')"
        di as text "  Mean VIF = " %5.2f `mean_vif'
    }
    
    // First compute corr(phi, control) as descriptive output. phi can still
    // co-move with controls through the retained polynomial terms even when
    // control subtraction is exact, so the rebuilt-phi identity is the test.
    local max_corr = 0
    local max_corr_var = ""
    local corr_status = "ok"
    local control_identity_maxdiff = .
    local control_identity_meandiff = .
    local control_identity_n = 0
    
    foreach ctrl of local control_vars {
        quietly correlate `phi' `ctrl' if `touse'
        local rho_`ctrl' = r(rho)

        if abs(`rho_`ctrl'') > abs(`max_corr') {
            local max_corr = `rho_`ctrl''
            local max_corr_var = "`ctrl'"
        }
    }

    local phi_type : type `phi'

    tempvar _phi_raw_rebuilt _phi_expected_cast _phi_diff
    quietly predict double `_phi_raw_rebuilt' if `touse', xb
    quietly gen `phi_type' `_phi_expected_cast' = `_phi_raw_rebuilt' if `touse'

    foreach ctrl of local control_vars {
        capture scalar _pte_beta_ctrl = _b[`ctrl']
        if _rc | missing(_pte_beta_ctrl) {
            scalar _pte_beta_ctrl = 0
        }
        quietly replace `_phi_expected_cast' = `_phi_expected_cast' - _pte_beta_ctrl * `ctrl' if `touse'
        scalar drop _pte_beta_ctrl
    }

    quietly gen double `_phi_diff' = `phi' - `_phi_expected_cast' if `touse' & !mi(`phi', `_phi_expected_cast')
    quietly count if !mi(`_phi_diff')
    local control_identity_n = r(N)

    if `control_identity_n' == 0 {
        di as error "Error: No valid observations for control-subtraction identity check"
        exit 2000
    }

    quietly summarize `_phi_diff', detail
    local control_identity_maxdiff = max(abs(r(min)), abs(r(max)))
    local control_identity_meandiff = abs(r(mean))

    if `control_identity_maxdiff' >= 1e-6 | `control_identity_meandiff' >= 1e-8 {
        local corr_status = "critical"
    }
    else if `control_identity_maxdiff' >= 1e-8 | `control_identity_meandiff' >= 1e-10 {
        local corr_status = "warning"
    }

    if "`corr_status'" == "critical" | "`corr_status'" == "warning" {
        di as error ""
        di as error "Warning: control-subtraction identity check failed"
        di as error "  Max |phi - rebuilt phi| = " %12.10f `control_identity_maxdiff'
        di as error "  Mean |phi - rebuilt phi| = " %12.10f `control_identity_meandiff'
        di as error "  Rebuilt phi = predict(xb) - sum(beta_control * control)"
        di as error "  Check the control-subtraction code or stale phi input"
    }
    else if `verbose' {
        di as text ""
        di as text "Control-subtraction identity check: PASSED"
        di as text "  Max |phi - rebuilt phi| = " %12.10f `control_identity_maxdiff'
        di as text "  Mean |phi - rebuilt phi| = " %12.10f `control_identity_meandiff'
    }

    if `verbose' & abs(`max_corr') >= `corrmax' {
        di as text ""
        di as text "Note: phi and controls still co-move in levels"
        di as text "  Max |corr(phi, control)| = " %6.4f abs(`max_corr') ///
            " (variable: `max_corr_var')"
        di as text "  This is descriptive only and does not, by itself, imply a subtraction error."
    }
    
    quietly summarize `phi' if `touse', detail
    
    local phi_mean = r(mean)
    local phi_sd = r(sd)
    local phi_var = r(Var)
    local phi_min = r(min)
    local phi_max = r(max)
    local phi_p1 = r(p1)
    local phi_p5 = r(p5)
    local phi_p10 = r(p10)
    local phi_p25 = r(p25)
    local phi_p50 = r(p50)
    local phi_p75 = r(p75)
    local phi_p90 = r(p90)
    local phi_p95 = r(p95)
    local phi_p99 = r(p99)
    local phi_skewness = r(skewness)
    local phi_kurtosis = r(kurtosis)
    local phi_iqr = `phi_p75' - `phi_p25'
    
    // These summaries are descriptive screens only; later omega and eps0
    // stages own trimming and support decisions.
    local lower_5sigma = `phi_mean' - 5 * `phi_sd'
    local upper_5sigma = `phi_mean' + 5 * `phi_sd'
    quietly count if !mi(`phi') & (`phi' < `lower_5sigma' | `phi' > `upper_5sigma')
    local n_outliers_5sigma = r(N)
    local pct_outliers_5sigma = `n_outliers_5sigma' / `phi_N' * 100
    
    local lower_iqr = `phi_p25' - 3 * `phi_iqr'
    local upper_iqr = `phi_p75' + 3 * `phi_iqr'
    quietly count if !mi(`phi') & (`phi' < `lower_iqr' | `phi' > `upper_iqr')
    local n_outliers_iqr = r(N)
    local pct_outliers_iqr = `n_outliers_iqr' / `phi_N' * 100
    
    if `verbose' {
        di as text ""
        di as text "{hline 60}"
        di as text "phi (First-Stage Fitted Value) Descriptive Statistics"
        di as text "{hline 60}"
        di as text "  Observations:    " as result %10.0fc `phi_N'
        di as text "{hline 60}"
        di as text "  Central Tendency:"
        di as text "    Mean:          " as result %12.4f `phi_mean'
        di as text "    Median (P50):  " as result %12.4f `phi_p50'
        di as text "{hline 60}"
        di as text "  Dispersion:"
        di as text "    Std. Dev.:     " as result %12.4f `phi_sd'
        di as text "    IQR:           " as result %12.4f `phi_iqr'
        di as text "    Range:         " as result %12.4f (`phi_max' - `phi_min')
        di as text "{hline 60}"
        di as text "  Percentiles:"
        di as text "    P1:            " as result %12.4f `phi_p1'
        di as text "    P5:            " as result %12.4f `phi_p5'
        di as text "    P25:           " as result %12.4f `phi_p25'
        di as text "    P75:           " as result %12.4f `phi_p75'
        di as text "    P95:           " as result %12.4f `phi_p95'
        di as text "    P99:           " as result %12.4f `phi_p99'
        di as text "{hline 60}"
        di as text "  Extremes:"
        di as text "    Min:           " as result %12.4f `phi_min'
        di as text "    Max:           " as result %12.4f `phi_max'
        di as text "{hline 60}"
        di as text "  Shape:"
        di as text "    Skewness:      " as result %12.4f `phi_skewness'
        di as text "    Kurtosis:      " as result %12.4f `phi_kurtosis'
        di as text "{hline 60}"
        di as text "  Outliers:"
        di as text "    5-sigma rule:  " as result %10.0f `n_outliers_5sigma' ///
            as text " (" as result %5.2f `pct_outliers_5sigma' as text "%)"
        di as text "    IQR rule:      " as result %10.0f `n_outliers_iqr' ///
            as text " (" as result %5.2f `pct_outliers_iqr' as text "%)"
        di as text "{hline 60}"
    }
    
    if `pct_outliers_5sigma' > 1 {
        di as error ""
        di as error "Warning: High proportion of outliers in phi"
        di as error "  " %5.2f `pct_outliers_5sigma' "% of observations exceed 5-sigma from mean"
        di as error "  Consider:"
        di as error "    - Winsorizing extreme values"
        di as error "    - Checking data quality for these observations"
        di as error "    - Investigating industry or time-specific patterns"
    }
    
    // Promote the worst diagnostic so callers can fail closed on the most
    // serious contract break without parsing multiple status flags.
    local overall_status = "ok"
    
    if "`r2_status'" == "critical" | "`vif_status'" == "critical" | "`corr_status'" == "critical" {
        local overall_status = "critical"
    }
    else if "`r2_status'" == "warning" | "`vif_status'" == "warning" | "`corr_status'" == "warning" {
        local overall_status = "warning"
    }
    
    if `verbose' {
        di as text ""
        di as text "{hline 70}"
        di as text "Diagnostic Summary"
        di as text "{hline 70}"
        
        if "`r2_status'" == "ok" {
            di as text "  R-squared:           " as result "PASSED" as text " (R2 = " %5.3f `r2' ")"
        }
        else if "`r2_status'" == "warning" {
            di as text "  R-squared:           " as error "WARNING" as text " (R2 = " %5.3f `r2' ")"
        }
        else {
            di as text "  R-squared:           " as error "CRITICAL" as text " (R2 = " %5.3f `r2' ")"
        }
        
        if "`vif_status'" == "ok" | "`vif_status'" == "acceptable" {
            di as text "  Multicollinearity:   " as result "PASSED" as text " (max VIF = " %5.2f `max_vif' ")"
        }
        else if "`vif_status'" == "warning" {
            di as text "  Multicollinearity:   " as error "WARNING" as text " (max VIF = " %5.2f `max_vif' ")"
        }
        else {
            di as text "  Multicollinearity:   " as error "CRITICAL" as text " (VIF calculation failed)"
        }
        
        if "`corr_status'" == "ok" {
            di as text "  Control subtraction: " as result "PASSED" as text " (max diff = " %9.2e `control_identity_maxdiff' ")"
        }
        else if "`corr_status'" == "warning" {
            di as text "  Control subtraction: " as error "WARNING" as text " (max diff = " %9.2e `control_identity_maxdiff' ")"
        }
        else {
            di as text "  Control subtraction: " as error "CRITICAL" as text " (max diff = " %9.2e `control_identity_maxdiff' ")"
        }
        
        di as text "{hline 70}"
        
        if "`overall_status'" == "ok" {
            di as result "Overall Status: ALL DIAGNOSTICS PASSED"
        }
        else if "`overall_status'" == "warning" {
            di as error "Overall Status: WARNINGS DETECTED - Review recommended"
        }
        else {
            di as error "Overall Status: CRITICAL ISSUES - Action required"
        }
        
        di as text "{hline 70}"
    }
    
    return local phi "`phi'"
    return local pfunc "`pfunc'"
    return local control_vars "`control_vars'"
    return scalar r2min = `r2min'
    return scalar vifmax = `vifmax'
    return scalar corrmax = `corrmax'
    return scalar verbose = `verbose'
    return scalar strict = `exit_on_error'
    
    return scalar r2 = `r2'
    return scalar r2_adj = `r2_adj'
    return local r2_status "`r2_status'"
    return scalar n_obs = e(N)
    return scalar n_vars = e(df_m)
    
    return scalar max_vif = `max_vif'
    return local max_vif_var "`max_vif_var'"
    return scalar mean_vif = `mean_vif'
    return local vif_status "`vif_status'"
    
    return scalar max_corr = `max_corr'
    return local max_corr_var "`max_corr_var'"
    return local corr_status "`corr_status'"
    return scalar control_identity_maxdiff = `control_identity_maxdiff'
    return scalar control_identity_meandiff = `control_identity_meandiff'
    return scalar control_identity_n = `control_identity_n'
    
    foreach ctrl of local control_vars {
        return scalar corr_`ctrl' = `rho_`ctrl''
    }

    return scalar phi_N = `phi_N'
    return scalar phi_mean = `phi_mean'
    return scalar phi_sd = `phi_sd'
    return scalar phi_var = `phi_var'
    return scalar phi_min = `phi_min'
    return scalar phi_max = `phi_max'
    return scalar phi_p1 = `phi_p1'
    return scalar phi_p5 = `phi_p5'
    return scalar phi_p10 = `phi_p10'
    return scalar phi_p25 = `phi_p25'
    return scalar phi_p50 = `phi_p50'
    return scalar phi_p75 = `phi_p75'
    return scalar phi_p90 = `phi_p90'
    return scalar phi_p95 = `phi_p95'
    return scalar phi_p99 = `phi_p99'
    return scalar phi_iqr = `phi_iqr'
    return scalar phi_skewness = `phi_skewness'
    return scalar phi_kurtosis = `phi_kurtosis'
    
    return scalar n_outliers_5sigma = `n_outliers_5sigma'
    return scalar pct_outliers_5sigma = `pct_outliers_5sigma'
    return scalar n_outliers_iqr = `n_outliers_iqr'
    return scalar pct_outliers_iqr = `pct_outliers_iqr'
    
    return local diag_status "`overall_status'"
    return scalar n_controls = `n_controls'
    
end
