*! _pte_stage1.ado
*! Stage 1 builds phi on the full estimable sample and strips only external
*! controls from predict(xb). Transition-period exclusion belongs to the
*! later GMM step, so dropping mid==1 here would change the paper's Stage-1
*! object and misalign phi with the reference DO workflow.

version 14.0
capture program drop _pte_stage1
program define _pte_stage1, rclass
    version 14.0

    // Preserve the raw option string so helper-level exact-name guards can
    // reject Stata's unique-abbreviation fallback before Stage 1 changes phi.
    local _pte_cmdline `"`0'"'
    local _pte_control_literal ""
    local _pte_tvars_literal ""
    if regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])control[(]([^)]*)[)]") {
        local _pte_control_literal `"`=regexs(2)'"'
        local _pte_control_literal = lower(itrim(strtrim(`"`_pte_control_literal'"')))
    }
    if regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])tvars[(]([^)]*)[)]") {
        local _pte_tvars_literal `"`=regexs(2)'"'
        local _pte_tvars_literal = lower(itrim(strtrim(`"`_pte_tvars_literal'"')))
    }
    
    syntax, depvar(name) pfunc(string) ///
            [control(varlist) TVARS(varlist) industry(varname) BYINDustry NODIAGnose STRICT ///
             TOUSE(varname)]

    if !inlist("`pfunc'", "cd", "translog") {
        di as error "[pte] pfunc must be 'cd' or 'translog', got '`pfunc''"
        exit 198
    }

    // depvar() must bind to the exact outcome variable used in Stage 1.
    // Allowing Stata abbreviation resolution here can silently switch the
    // production-function target from y_it to an unrelated shadow column.
    capture confirm variable `depvar', exact
    if _rc {
        di as error "[pte] variable `depvar' not found"
        exit 111
    }

    // Stage 1 subtracts the exact control list from phi_raw. Allowing
    // control() abbreviations would silently change the identifying object
    // in Eq. (6)-(7) from the paper and the DO subtract-controls workflow.
    if `"`_pte_control_literal'"' != "" & "`control'" != "" {
        local _pte_control_resolved = lower(itrim(strtrim(`"`control'"')))
        if `"`_pte_control_literal'"' != `"`_pte_control_resolved'"' {
            di as error "[pte] control() variables must be specified with exact existing variable names"
            exit 111
        }
    }

    // tvars() defines the exact time-trend controls subtracted from phi_raw.
    // Abbreviation fallback would silently redirect that subtraction to a
    // shadow control and change the first-stage identifying object.
    if `"`_pte_tvars_literal'"' != "" & "`tvars'" != "" {
        local _pte_tvars_resolved = lower(itrim(strtrim(`"`tvars'"')))
        if `"`_pte_tvars_literal'"' != `"`_pte_tvars_resolved'"' {
            di as error "[pte] tvars() variables must be specified with exact existing variable names"
            exit 111
        }
    }
    
    // Validate core polynomial variables exist (from)
    foreach var in l1 m1 k1 {
        capture confirm variable `var'
        if _rc {
            di as error "[pte] polynomial variable `var' not found; run _pte_polyvar first"
            exit 111
        }
    }

    // Build the default Stage-1 sample before any pooled-industry branch reads
    // touse. Omitting touse() must fall back to the full estimable sample.
    if "`touse'" == "" {
        tempvar touse
        mark `touse'
        markout `touse' `depvar' l1 m1 k1
        foreach var of local control {
            markout `touse' `var'
        }
        foreach var of local tvars {
            markout `touse' `var'
        }
        if "`industry'" != "" {
            capture confirm string variable `industry'
            if _rc {
                markout `touse' `industry'
            }
            else {
                quietly replace `touse' = 0 if missing(`industry')
            }
        }
    }
    else {
        capture confirm numeric variable `touse'
        if _rc {
            di as error "[pte] touse variable `touse' must be numeric"
            exit 109
        }
    }

    tempvar _pte_stage1_sample
    quietly gen byte `_pte_stage1_sample' = (`touse' != 0 & !missing(`touse'))
    
    // Stage 1 follows the paper/DO split between by-industry and pooled
    // regressions because pooled runs need grouped time controls that depend
    // on the realized industry partition in the current sample.
    local is_byindustry = ("`byindustry'" != "")

    local n_ind = 0
    if !`is_byindustry' {
        if "`industry'" != "" {
            quietly levelsof `industry' if `_pte_stage1_sample', local(ind_levels)
            local n_ind : word count `ind_levels'
        }
    }
    
    // Use explicit polynomial names instead of wildcards so generated lag
    // helpers such as l1k_lag never leak into the Stage-1 sieve.
    local regvars_base ""
    local default_time_controls ""
    if "`pfunc'" == "cd" {
        if `is_byindustry' {
            local regvars_base "l1 l1m1 l1k1 l1m2 l1k2 m1 m1k1 m1k2 m1l2 k1 k1l2 k1m2 k1l1m1 k2 l2 m2 k3 l3 m3"
            local default_time_controls "t"
            local n_poly_expected = 19
            local n_control_expected = 1
        }
        else {
            if `n_ind' > 0 {
                local t_vars ""
                forvalues j = 1/`n_ind' {
                    local t_vars "`t_vars' t`j'"
                }
                local regvars_base "l1 l1m1 l1k1 l1m2 l1k2 m1 m1k1 m1k2 m1l2 k1 k1l2 k1m2 k1l1m1 k2 l2 m2 k3 l3 m3"
                local default_time_controls "`t_vars'"
                local n_poly_expected = 19
                local n_control_expected = `n_ind'
            }
            else {
                local regvars_base "l1 l1m1 l1k1 l1m2 l1k2 m1 m1k1 m1k2 m1l2 k1 k1l2 k1m2 k1l1m1 k2 l2 m2 k3 l3 m3"
                local default_time_controls "t"
                local n_poly_expected = 19
                local n_control_expected = 1
            }
        }
    }
    else if "`pfunc'" == "translog" {
        if `is_byindustry' {
            local regvars_base "l1 l1m1 l1k1 l1m2 l1k2 m1 m1k1 m1k2 m1l2 k1 k1l2 k1m2 k1l1m1 l2 m2 k2 l3 m3 k3"
            local default_time_controls "t"
            local n_poly_expected = 19
            local n_control_expected = 1
        }
        else {
            if `n_ind' > 0 {
                local t_vars ""
                forvalues j = 1/`n_ind' {
                    local t_vars "`t_vars' t`j'"
                }
                local regvars_base "l1 l1m1 l1k1 l1m2 l1k2 m1 m1k1 m1k2 m1l2 k1 k1l2 k1m2 k1l1m1 l2 m2 k2"
                local default_time_controls "`t_vars'"
                local n_poly_expected = 16
                local n_control_expected = `n_ind'
            }
            else {
                local regvars_base "l1 l1m1 l1k1 l1m2 l1k2 m1 m1k1 m1k2 m1l2 k1 k1l2 k1m2 k1l1m1 l2 m2 k2"
                local default_time_controls "t"
                local n_poly_expected = 16
                local n_control_expected = 1
            }
        }
    }

    if "`tvars'" == "" & !`is_byindustry' & "`industry'" != "" & `n_ind' > 0 {
        // Do not trust pre-existing t1-tJ variables here. The pooled DO path
        // defines these controls from the common grouped time trend t and the
        // current industry partition; stale workspace leftovers would silently
        // rewrite phi and downstream GMM beta. Rebuild a private control set
        // from exact t whenever stage1 owns the pooled control contract.
        capture confirm variable t, exact
        if _rc {
            di as error "[pte] pooled stage1 without explicit tvars() requires exact grouped time variable t"
            di as error "[pte]        Existing t1-tJ variables are not trusted implicitly"
            di as error "[pte]        Provide tvars() explicitly or generate t = group(time) first"
            exit 111
        }
        capture confirm numeric variable t
        if _rc {
            di as error "[pte] grouped time variable t must be numeric"
            exit 109
        }

        tempvar _pte_industry_group
        quietly egen long `_pte_industry_group' = group(`industry') if `_pte_stage1_sample'
        local _pte_autotvars ""
        local _pte_j = 0
        foreach _pte_lev of local ind_levels {
            local ++_pte_j
            capture drop _pte_t`_pte_j'
            quietly gen double _pte_t`_pte_j' = ///
                t * (`_pte_industry_group' == `_pte_j') if `_pte_stage1_sample'
            local _pte_autotvars "`_pte_autotvars' _pte_t`_pte_j'"
        }
        local default_time_controls "`_pte_autotvars'"
    }

    if "`tvars'" != "" {
        local time_control_vars "`tvars'"
    }
    else {
        local time_control_vars "`default_time_controls'"
    }

    local overlap_poly_tvars : list time_control_vars & regvars_base
    if "`overlap_poly_tvars'" != "" {
        di as error "[pte] tvars() cannot include production-function polynomial terms"
        di as error "[pte]      Overlap: `overlap_poly_tvars'"
        di as error "[pte]      tvars() is reserved for time-trend controls only"
        exit 198
    }

    local control_vars "`time_control_vars'"
    local regvars "`regvars_base' `time_control_vars'"
    
    if "`control'" != "" {
        local overlap_poly_controls : list control & regvars_base
        if "`overlap_poly_controls'" != "" {
            di as error "[pte] control() cannot include production-function polynomial terms"
            di as error "[pte]        Overlap: `overlap_poly_controls'"
            di as error "[pte]        control() is reserved for external controls such as time trends"
            exit 198
        }
        local control_vars "`control_vars' `control'"
        local control_vars : list uniq control_vars
        local regvars "`regvars' `control'"
        local regvars : list uniq regvars
    }

    // Every control in this list will later be subtracted from phi_raw, so
    // a stale or nonnumeric control would silently corrupt the state passed
    // to omega recovery and GMM.
    foreach var of local control_vars {
        capture confirm variable `var'
        if _rc {
            di as error "[pte] control variable `var' not found"
            exit 111
        }
        capture confirm numeric variable `var'
        if _rc {
            di as error "[pte] control variable `var' is not numeric"
            exit 109
        }
    }
    
    // Keep the full Stage-1 sample here. The paper and DO code drop
    // transition periods only when forming the GMM moments, not when
    // constructing phi from the sieve regression.
    quietly reg `depvar' `regvars' if `_pte_stage1_sample'

    local r2 = e(r2)
    local n_stage1 = e(N)

    if `n_stage1' == 0 {
        di as error "[pte] no observations for first-stage regression"
        exit 2000
    }

    if `r2' == 0 {
        di as error "[pte] first-stage R-squared is zero; check data or model specification"
        exit 498
    }

    capture drop phi_raw
    capture drop phi

    // predict-created tempvars are safer than writing phi_raw directly
    // because later replacement steps expect a persistent named variable.
    tempvar phi_temp
    quietly predict double `phi_temp' if e(sample), xb

    quietly generate double phi_raw = `phi_temp'

    quietly count if missing(phi_raw) & e(sample)
    if r(N) > 0 {
        di as error "[pte] phi_raw has `r(N)' missing values in regression sample"
        exit 2000
    }

    // phi is the fitted Stage-1 object net of external controls only. The
    // labor, capital, and materials terms stay inside phi because later
    // stages recover beta and omega from that exact decomposition.
    quietly generate double phi = phi_raw

    local n_control : word count `control_vars'
    matrix beta_controls = J(1, `n_control', .)
    local missing_coef_vars ""
    
    local j = 0
    foreach var of local control_vars {
        local ++j
        
        capture scalar _pte_beta_`var' = _b[`var']
        if _rc | missing(_pte_beta_`var') {
            di as text "[pte] Note: coefficient for `var' is missing; set to 0"
            scalar _pte_beta_`var' = 0
            local missing_coef_vars "`missing_coef_vars' `var'"
        }

        quietly replace phi = phi - _pte_beta_`var' * `var'
        matrix beta_controls[1, `j'] = _pte_beta_`var'

        scalar drop _pte_beta_`var'
    }

    label variable phi "First-stage fitted value (controls subtracted)"
    label variable phi_raw "First-stage raw fitted value"

    // Run diagnostics while the Stage-1 regression is still active so the
    // helper can rebuild phi from the live e(b) and e(sample) objects.
    local _diag_opts "phi(phi) pfunc(`pfunc') controlvars(`control_vars')"
    if "`nodiagnose'" == "" {
        local _diag_opts "`_diag_opts' diagnose"
    }
    if "`strict'" != "" {
        local _diag_opts "`_diag_opts' strict"
    }
    
    _pte_stage1_diag, `_diag_opts'

    // Copy r() immediately because the summary block below issues new rclass
    // commands and would otherwise erase the helper's contract outputs.
    local _diag_status   "`r(diag_status)'"
    local _diag_r2       = r(r2)
    local _diag_r2_adj   = r(r2_adj)
    local _diag_r2_status "`r(r2_status)'"
    local _diag_max_vif  = r(max_vif)
    local _diag_max_vif_var "`r(max_vif_var)'"
    local _diag_mean_vif = r(mean_vif)
    local _diag_vif_status "`r(vif_status)'"
    local _diag_max_corr = r(max_corr)
    local _diag_max_corr_var "`r(max_corr_var)'"
    local _diag_corr_status "`r(corr_status)'"
    local _diag_phi_N    = r(phi_N)
    local _diag_phi_mean = r(phi_mean)
    local _diag_phi_sd   = r(phi_sd)
    local _diag_phi_min  = r(phi_min)
    local _diag_phi_max  = r(phi_max)
    local _diag_n_outliers_5sigma = r(n_outliers_5sigma)
    local _diag_pct_outliers_5sigma = r(pct_outliers_5sigma)
    
    return scalar r2_stage1 = `r2'
    return scalar n_stage1 = `n_stage1'
    return scalar n_poly_vars = `n_poly_expected'
    return scalar n_control_vars = `n_control'

    return local diag_status = "`_diag_status'"
    return scalar diag_r2 = `_diag_r2'
    return scalar diag_r2_adj = `_diag_r2_adj'
    return local diag_r2_status = "`_diag_r2_status'"
    return scalar diag_max_vif = `_diag_max_vif'
    return local diag_max_vif_var = "`_diag_max_vif_var'"
    return scalar diag_mean_vif = `_diag_mean_vif'
    return local diag_vif_status = "`_diag_vif_status'"
    return scalar diag_max_corr = `_diag_max_corr'
    return local diag_max_corr_var = "`_diag_max_corr_var'"
    return local diag_corr_status = "`_diag_corr_status'"
    return scalar rho_phi_control = abs(`_diag_max_corr')
    return scalar diag_n_outliers_5sigma = `_diag_n_outliers_5sigma'
    return scalar diag_pct_outliers_5sigma = `_diag_pct_outliers_5sigma'
    
    // beta_controls preserves the exact subtraction weights that were used to
    // turn phi_raw into phi, which downstream diagnostics can compare.
    matrix colnames beta_controls = `control_vars'
    return matrix beta_controls = beta_controls

    return scalar phi_mean = `_diag_phi_mean'
    return scalar phi_sd = `_diag_phi_sd'
    return scalar phi_min = `_diag_phi_min'
    return scalar phi_max = `_diag_phi_max'

    return local missing_coef_vars = trim("`missing_coef_vars'")

    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "First-Stage Regression"
        di as text "{hline 60}"
        di as text "  Production function:          " as result "`pfunc'"
        if `is_byindustry' {
            di as text "  Estimation mode:              " as result "by-industry"
        }
        else {
            di as text "  Estimation mode:              " as result "pooled"
        }
        di as text "  Sample size:                  " as result %10.0fc `n_stage1'
        di as text "  R-squared:                    " as result %10.4f `r2'
        di as text "  Number of polynomial vars:    " as result %10.0f `n_poly_expected'
        di as text "  Number of control vars:       " as result %10.0f `n_control'
        di as text "  Max |corr(phi, control)|:     " as result %10.4f abs(`_diag_max_corr')
        di as text "  phi mean:                     " as result %10.4f `_diag_phi_mean'
        di as text "  phi std dev:                  " as result %10.4f `_diag_phi_sd'
        di as text "  Diagnostic status:            " as result "`_diag_status'"
        di as text "{hline 60}"
        di as text ""
    }
    
end
