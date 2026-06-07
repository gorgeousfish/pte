*! _pte_compare_all.ado
*! Combined Method Comparison (Method I + II + III)
*!
*! Theory: Paper Section 5, Table 3
*!
*! Runs all three methods and produces a combined comparison table:
*!   Method I  (expost):  m1, m2, m3 - Ex-post regression + TWFE
*!   Method II (endog):   m4, m5, m6 - Endogenous productivity + TWFE
*!   Method III(clktwfe): m7, m8, m9 - CLK + TWFE

version 14.0
capture program drop _pte_compare_all
program define _pte_compare_all, eclass
    version 14.0

    local _pte_compare_all_optscan " `0' "
    local _pte_compare_all_has_omegapoly = ///
        regexm(lower(`"`_pte_compare_all_optscan'"'), "(^|[ ,])omegapoly[(]")

    syntax , treatment(varname) ///
        [SPECs(numlist integer min=1 max=3 >0 <4) ///
         OMEGApoly(integer -1) ///
         ABsorb(string) VCE(string) INDustry(varname) ///
         LAGTreatment DIAGnose noREPort ///
         EXPort(string) REPLACE]

    if "`specs'" == "" local specs "1 2 3"
    local _pte_compare_all_nspecs : word count `specs'
    local _pte_compare_all_has_spec1 = 0
    local _pte_compare_all_has_spec2 = 0
    local _pte_compare_all_has_spec3 = 0
    foreach _pte_compare_all_spec of local specs {
        local _pte_compare_all_has_spec`_pte_compare_all_spec' = 1
    }
    if `_pte_compare_all_nspecs' != 3 | ///
        !`_pte_compare_all_has_spec1' | ///
        !`_pte_compare_all_has_spec2' | ///
        !`_pte_compare_all_has_spec3' {
        di as error "Error 198: _pte_compare_all requires specs(1 2 3)."
        di as error "The combined compare workflow implements the full Table 3 bundle only."
        exit 198
    }
    local specs "1 2 3"

    if `omegapoly' == -1 & !`_pte_compare_all_has_omegapoly' {
        capture local omegapoly = e(omegapoly)
        if _rc != 0 | missing(`omegapoly') {
            local omegapoly = 3
        }
    }
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "Error 198: omegapoly(`omegapoly') must be 1, 2, 3, or 4."
        exit 198
    }

    if "`industry'" != "" {
        di as error "Error 198: industry() is not supported by _pte_compare_all."
        di as error "The released comparison workflow does not implement a general by-industry public interface."
        di as error "Subset the data before calling, or use a dedicated industry comparison workflow."
        exit 198
    }
    
    // =========================================================================
    // Step 0: Validate prerequisites
    // =========================================================================
    
    if "`e(cmd)'" != "pte" {
        di as error "Error 301: pte has not been run."
        di as error "Please run {bf:pte} first."
        exit 301
    }
    
    capture which reghdfe
    if _rc {
        di as error "Error 601: reghdfe is required but not installed."
        di as error "Please install: {stata ssc install reghdfe}"
        exit 601
    }
    
    // Save pte results
    local pte_panelvar "`e(panelvar)'"
    local pte_timevar  "`e(timevar)'"
    tempvar compare_esample
    capture quietly generate byte `compare_esample' = e(sample)
    if _rc {
        di as error "Error 498: pte_compare could not recover the original pte estimation sample."
        exit 498
    }
    
    // Save pte ATT for bias calculation (T-010)
    // Must capture before sub-methods overwrite e()
    local pte_att_saved = .
    capture local pte_att_saved = e(ATT_avg)
    if missing(`pte_att_saved') {
        capture {
            tempname _att_mat
            matrix `_att_mat' = e(att)
            local _ncols = colsof(`_att_mat')
            local pte_att_saved = `_att_mat'[1, `_ncols']
        }
    }
    
    di as text ""
    di as text "{hline 70}"
    di as text "  Combined Method Comparison (Table 3 Style)"
    di as text "  Paper Section 5: Traditional Two-Step Methods"
    di as text "{hline 70}"
    di as text ""
    
    // Build common options for sub-methods. Only Method II consumes
    // omegapoly(), so keep a dedicated endog option bundle.
    local common_opts "treatment(`treatment') noreport"
    if "`specs'"    != "" local common_opts "`common_opts' specs(`specs')"
    if "`absorb'"   != "" local common_opts "`common_opts' absorb(`absorb')"
    if "`vce'"      != "" local common_opts "`common_opts' vce(`vce')"
    if "`industry'" != "" local common_opts "`common_opts' industry(`industry')"
    if "`lagtreatment'" != "" local common_opts "`common_opts' lagtreatment"
    if "`diagnose'" != "" local common_opts "`common_opts' diagnose"
    local endog_opts "`common_opts' omegapoly(`omegapoly')"
    local treatment_label "`treatment'"
    if "`lagtreatment'" != "" {
        local treatment_label "L.`treatment'"
    }
    local treatment_label_tex = subinstr(`"`treatment_label'"', "_", "\_", .)
    
    // =========================================================================
    // Step 1: Run Method I (Ex-post) - m1, m2, m3
    // =========================================================================
    
    di as text "  Running Method I: Ex-post regression + TWFE (m1-m3)..."
    
    // Save pte e() before expost overwrites it
    tempname pte_hold
    _estimates hold `pte_hold', copy
    
    capture noisily _pte_compare_expost, `common_opts'
    local expost_rc = _rc
    
    // Extract expost results
    tempname coef_expost se_expost r2_expost n_expost
    if `expost_rc' == 0 {
        matrix `coef_expost' = e(coef_expost)
        matrix `se_expost'   = e(se_expost)
        matrix `r2_expost'   = e(r2_expost)
        matrix `n_expost'    = e(n_expost)
        di as text "    Method I complete."
    }
    else {
        matrix `coef_expost' = J(1, 3, .)
        matrix `se_expost'   = J(1, 3, .)
        matrix `r2_expost'   = J(1, 3, .)
        matrix `n_expost'    = J(1, 3, .)
        di as error "    Method I failed (rc = `expost_rc'). Continuing..."
    }
    
    // Restore pte e() for next method
    _estimates unhold `pte_hold'
    
    // =========================================================================
    // Step 2: Run Method II (Endogenous) - m4, m5, m6
    // =========================================================================
    
    di as text "  Running Method II: Endogenous productivity + TWFE (m4-m6)..."
    
    _estimates hold `pte_hold', copy
    
    capture noisily _pte_compare_endog, `endog_opts'
    local endog_rc = _rc
    
    // Extract endog results
    tempname coef_endog se_endog r2_endog n_endog beta_endog
    if `endog_rc' == 0 {
        matrix `coef_endog' = e(coef_endog)
        matrix `se_endog'   = e(se_endog)
        matrix `r2_endog'   = e(r2_endog)
        matrix `n_endog'    = e(n_endog)
        capture matrix `beta_endog' = e(beta_endog)
        di as text "    Method II complete."
    }
    else {
        matrix `coef_endog' = J(1, 3, .)
        matrix `se_endog'   = J(1, 3, .)
        matrix `r2_endog'   = J(1, 3, .)
        matrix `n_endog'    = J(1, 3, .)
        di as error "    Method II failed (rc = `endog_rc'). Continuing..."
    }
    
    _estimates unhold `pte_hold'
    
    // =========================================================================
    // Step 3: Run Method III (CLK+TWFE) - m7, m8, m9
    // =========================================================================
    
    di as text "  Running Method III: CLK + TWFE (m7-m9)..."
    
    _estimates hold `pte_hold', copy
    
    capture noisily _pte_compare_clktwfe, `common_opts'
    local clktwfe_rc = _rc
    
    // Extract clktwfe results
    tempname coef_clktwfe se_clktwfe r2_clktwfe n_clktwfe
    if `clktwfe_rc' == 0 {
        matrix `coef_clktwfe' = e(coef_clktwfe)
        matrix `se_clktwfe'   = e(se_clktwfe)
        matrix `r2_clktwfe'   = e(r2_clktwfe)
        matrix `n_clktwfe'    = e(n_clktwfe)
        di as text "    Method III complete."
    }
    else {
        matrix `coef_clktwfe' = J(1, 3, .)
        matrix `se_clktwfe'   = J(1, 3, .)
        matrix `r2_clktwfe'   = J(1, 3, .)
        matrix `n_clktwfe'    = J(1, 3, .)
        di as error "    Method III failed (rc = `clktwfe_rc'). Continuing..."
    }
    
    _estimates unhold `pte_hold'

    // The combined Table 3 contract is valid only when every method-spec
    // slot in the full m1-m9 lattice is populated.
    local complete_count = 0
    local incomplete_methods ""
    foreach _pte_compare_method in expost endog clktwfe {
        local _pte_compare_complete = 1
        foreach _pte_compare_j of numlist `specs' {
            if missing(`coef_`_pte_compare_method''[1, `_pte_compare_j']) {
                local _pte_compare_complete = 0
                continue, break
            }
        }
        if `_pte_compare_complete' {
            local ++complete_count
        }
        else {
            local incomplete_methods "`incomplete_methods' `_pte_compare_method'"
        }
    }
    if `complete_count' == 0 {
        di as error "Error 498: pte_compare, method(all) produced no comparison estimates."
        di as error "All comparison submethods failed, so no combined Table 3 result is available."
        exit 498
    }
    if `complete_count' < 3 {
        local incomplete_methods = strtrim("`incomplete_methods'")
        di as error "Error 498: pte_compare, method(all) did not recover the full requested comparison bundle."
        di as error "method(all) requires every requested method/specification slot to be available before publishing the combined result."
        di as error "Incomplete methods: `incomplete_methods'"
        exit 498
    }
    
    // =========================================================================
    // Step 4: Combined Table 3 Style Output
    // =========================================================================
    
    if "`report'" != "noreport" {
        di as text ""
        di as text "{hline 78}"
        di as text "  Table 3: TWFE Estimates of Treatment Effects on Productivity"
        di as text "  (Paper Section 5, Reproduction Code L175-210)"
        di as text "{hline 78}"
        di as text ""
        di as text "  Production   Ex-post (I)          Endogenous (II)      CLK+TWFE (III)"
        di as text "  Function     Standard ACF          w/ Treatment Int.    CLK-corrected"
        di as text "  {hline 74}"
        di as text "  Spec         (m1)   (m2)   (m3)   (m4)   (m5)   (m6)   (m7)   (m8)   (m9)"
        di as text "  {hline 74}"
        
        // Treatment coefficient row
        di as text %12s "`treatment_label'" _continue
        forvalues m = 1/3 {
            di as text %7.3f `coef_expost'[1,`m'] _continue
        }
        forvalues m = 1/3 {
            di as text %7.3f `coef_endog'[1,`m'] _continue
        }
        forvalues m = 1/3 {
            di as text %7.3f `coef_clktwfe'[1,`m'] _continue
        }
        di as text ""
        
        // Standard errors row
        di as text "             " _continue
        forvalues m = 1/3 {
            local se_val = `se_expost'[1,`m']
            di as text "(" %5.3f `se_val' ")" _continue
        }
        forvalues m = 1/3 {
            local se_val = `se_endog'[1,`m']
            di as text "(" %5.3f `se_val' ")" _continue
        }
        forvalues m = 1/3 {
            local se_val = `se_clktwfe'[1,`m']
            di as text "(" %5.3f `se_val' ")" _continue
        }
        di as text ""
        
        // Significance stars row
        di as text "             " _continue
        foreach mat in expost endog clktwfe {
            forvalues m = 1/3 {
                local c = `coef_`mat''[1,`m']
                local s = `se_`mat''[1,`m']
                local star ""
                if `s' != . & `s' > 0 {
                    local p = 2 * (1 - normal(abs(`c' / `s')))
                    if `p' < 0.01      local star "***"
                    else if `p' < 0.05 local star " **"
                    else if `p' < 0.10 local star "  *"
                    else               local star "   "
                }
                else local star "   "
                di as text "  `star'  " _continue
            }
        }
        di as text ""
        
        // N row
        di as text "  N          " _continue
        forvalues m = 1/3 {
            di as text %7.0f `n_expost'[1,`m'] _continue
        }
        forvalues m = 1/3 {
            di as text %7.0f `n_endog'[1,`m'] _continue
        }
        forvalues m = 1/3 {
            di as text %7.0f `n_clktwfe'[1,`m'] _continue
        }
        di as text ""
        
        // Adj R2 row
        di as text "  Adj.R2     " _continue
        forvalues m = 1/3 {
            di as text %7.3f `r2_expost'[1,`m'] _continue
        }
        forvalues m = 1/3 {
            di as text %7.3f `r2_endog'[1,`m'] _continue
        }
        forvalues m = 1/3 {
            di as text %7.3f `r2_clktwfe'[1,`m'] _continue
        }
        di as text ""
        
        // Bias row (T-011: bias vs pte ATT)
        if !missing(`pte_att_saved') & abs(`pte_att_saved') > 1e-10 {
            di as text "  Bias(%)    " _continue
            foreach mat in expost endog clktwfe {
                forvalues m = 1/3 {
                    local c = `coef_`mat''[1,`m']
                    if !missing(`c') {
                        local bias_pct = (`c' - `pte_att_saved') / abs(`pte_att_saved') * 100
                        if `bias_pct' >= 0 {
                            di as text "  +" %4.0f `bias_pct' _continue
                        }
                        else {
                            di as text "  " %5.0f `bias_pct' _continue
                        }
                    }
                    else {
                        di as text "     ." _continue
                    }
                }
            }
            di as text ""
        }
        
        di as text "  {hline 74}"
        di as text "  Controls     None  AR(1) AR(3)  None  AR(1) AR(3)  None  AR(1) AR(3)"
        di as text "  Excl. mid    No    No    No     No    No    No     Yes   Yes   Yes"
        di as text "  {hline 74}"
        
        // pte ATT reference (T-011)
        if !missing(`pte_att_saved') {
            di as text "  pte ATT (reference): " %9.4f `pte_att_saved'
        }
        
        di as text "  Note: * p<0.10, ** p<0.05, *** p<0.01"
        di as text "  Method I:   Standard ACF (no treatment interaction, no mid exclusion)"
        di as text "  Method II:  Endogenous ACF (with treatment interaction, no mid exclusion)"
        di as text "  Method III: CLK-corrected ACF (uses current pte omega contract; rebuilds if missing/stale)"
        di as text "{hline 78}"
    }
    
    // =========================================================================
    // Step 4b: LaTeX Export (T-013)
    // =========================================================================
    
    if "`export'" != "" {
        // Check if file exists and replace option
        capture confirm file "`export'"
        if _rc == 0 & "`replace'" == "" {
            di as error "Error 602: File `export' already exists."
            di as error "Use {bf:replace} option to overwrite."
            exit 602
        }
        
        // Open file for writing
        capture file close _latex_out
        file open _latex_out using "`export'", write replace
        
        // Write LaTeX table header
        file write _latex_out "% Table 3: TWFE Estimates of Treatment Effects on Productivity" _n
        file write _latex_out "% Generated by pte_compare, method(all)" _n
        file write _latex_out "% Reference: Chen, Liao \& Schurter (2026) Section 5" _n
        file write _latex_out _n
        file write _latex_out "\begin{table}[htbp]" _n
        file write _latex_out "  \centering" _n
        file write _latex_out "  \caption{TWFE Estimates of Treatment Effects on Productivity}" _n
        file write _latex_out "  \label{tab:twfe_comparison}" _n
        file write _latex_out "  \begin{tabular}{l*{9}{c}}" _n
        file write _latex_out "    \toprule" _n
        
        // Column headers
        file write _latex_out "    & \multicolumn{3}{c}{Ex-post (I)} & \multicolumn{3}{c}{Endogenous (II)} & \multicolumn{3}{c}{CLK+TWFE (III)} \\" _n
        file write _latex_out "    \cmidrule(lr){2-4} \cmidrule(lr){5-7} \cmidrule(lr){8-10}" _n
        file write _latex_out "    & (m1) & (m2) & (m3) & (m4) & (m5) & (m6) & (m7) & (m8) & (m9) \\" _n
        file write _latex_out "    \midrule" _n
        
        // Treatment coefficient row with significance stars
        file write _latex_out "    `treatment_label_tex' " _continue
        foreach mat in expost endog clktwfe {
            forvalues m = 1/3 {
                local c = `coef_`mat''[1,`m']
                local s = `se_`mat''[1,`m']
                local star ""
                if `s' != . & `s' > 0 {
                    local p = 2 * (1 - normal(abs(`c' / `s')))
                    if `p' < 0.01      local star "^{***}"
                    else if `p' < 0.05 local star "^{**}"
                    else if `p' < 0.10 local star "^{*}"
                }
                if `c' != . {
                    file write _latex_out "& " %7.3f (`c') "`star' " _continue
                }
                else {
                    file write _latex_out "& . " _continue
                }
            }
        }
        file write _latex_out "\\" _n
        
        // Standard errors row
        file write _latex_out "    " _continue
        foreach mat in expost endog clktwfe {
            forvalues m = 1/3 {
                local s = `se_`mat''[1,`m']
                if `s' != . {
                    file write _latex_out "& (" %5.3f (`s') ") " _continue
                }
                else {
                    file write _latex_out "& (.) " _continue
                }
            }
        }
        file write _latex_out "\\" _n
        
        // N row
        file write _latex_out "    N " _continue
        foreach mat in expost endog clktwfe {
            forvalues m = 1/3 {
                local n_val = `n_`mat''[1,`m']
                if `n_val' != . {
                    file write _latex_out "& " %7.0f (`n_val') " " _continue
                }
                else {
                    file write _latex_out "& . " _continue
                }
            }
        }
        file write _latex_out "\\" _n
        
        // Adj R2 row
        file write _latex_out "    Adj.\$R^2\$ " _continue
        foreach mat in expost endog clktwfe {
            forvalues m = 1/3 {
                local r2_val = `r2_`mat''[1,`m']
                if `r2_val' != . {
                    file write _latex_out "& " %5.3f (`r2_val') " " _continue
                }
                else {
                    file write _latex_out "& . " _continue
                }
            }
        }
        file write _latex_out "\\" _n
        
        // Footer
        file write _latex_out "    \midrule" _n
        file write _latex_out "    Controls & None & AR(1) & AR(3) & None & AR(1) & AR(3) & None & AR(1) & AR(3) \\" _n
        file write _latex_out "    Excl.\ mid & No & No & No & No & No & No & Yes & Yes & Yes \\" _n
        file write _latex_out "    \bottomrule" _n
        file write _latex_out "  \end{tabular}" _n
        file write _latex_out "  \begin{tablenotes}" _n
        file write _latex_out "    \small" _n
        file write _latex_out "    \item Note: \$^{*}\$ \$p<0.10\$, \$^{**}\$ \$p<0.05\$, \$^{***}\$ \$p<0.01\$." _n
        file write _latex_out "    \item Method I: Standard ACF (no treatment interaction, no mid exclusion)." _n
        file write _latex_out "    \item Method II: Endogenous ACF (with treatment interaction, no mid exclusion)." _n
        file write _latex_out "    \item Method III: CLK-corrected ACF (uses current pte omega contract; rebuilds if missing or stale)." _n
        file write _latex_out "  \end{tablenotes}" _n
        file write _latex_out "\end{table}" _n
        
        file close _latex_out
        
        di as text ""
        di as text "  LaTeX table exported to: `export'"
    }
    
    // =========================================================================
    // Step 5: Store combined e() return values
    // =========================================================================
    
    // Build combined 1x9 coefficient matrix (m1-m9)
    tempname coef_all se_all r2_all n_all
    matrix `coef_all' = `coef_expost', `coef_endog', `coef_clktwfe'
    matrix `se_all'   = `se_expost',   `se_endog',   `se_clktwfe'
    matrix `r2_all'   = `r2_expost',   `r2_endog',   `r2_clktwfe'
    matrix `n_all'    = `n_expost',    `n_endog',    `n_clktwfe'
    
    matrix colnames `coef_all' = m1 m2 m3 m4 m5 m6 m7 m8 m9
    matrix colnames `se_all'   = m1 m2 m3 m4 m5 m6 m7 m8 m9
    matrix colnames `r2_all'   = m1 m2 m3 m4 m5 m6 m7 m8 m9
    matrix colnames `n_all'    = m1 m2 m3 m4 m5 m6 m7 m8 m9
    
    // -------------------------------------------------------------------------
    // t-statistic and p-value calculation (T-008)
    // t = coef / SE, p = 2 * (1 - normal(|t|))
    // -------------------------------------------------------------------------
    tempname t_all p_all
    matrix `t_all' = J(1, 9, .)
    matrix `p_all' = J(1, 9, .)
    matrix colnames `t_all' = m1 m2 m3 m4 m5 m6 m7 m8 m9
    matrix colnames `p_all' = m1 m2 m3 m4 m5 m6 m7 m8 m9
    
    forvalues m = 1/9 {
        local c_m = `coef_all'[1, `m']
        local s_m = `se_all'[1, `m']
        if !missing(`c_m') & !missing(`s_m') & `s_m' > 0 {
            matrix `t_all'[1, `m'] = `c_m' / `s_m'
            matrix `p_all'[1, `m'] = 2 * (1 - normal(abs(`c_m' / `s_m')))
        }
    }
    
    // -------------------------------------------------------------------------
    // CI calculation (T-009): default 95% confidence interval
    // CI = coef +/- z_crit * SE, where z_crit = invnormal(1 - alpha/2)
    // -------------------------------------------------------------------------
    tempname ci_lower ci_upper
    local z_crit = invnormal(1 - (1 - 95/100) / 2)
    matrix `ci_lower' = `coef_all' - `z_crit' * `se_all'
    matrix `ci_upper' = `coef_all' + `z_crit' * `se_all'
    matrix colnames `ci_lower' = m1 m2 m3 m4 m5 m6 m7 m8 m9
    matrix colnames `ci_upper' = m1 m2 m3 m4 m5 m6 m7 m8 m9
    
    // -------------------------------------------------------------------------
    // Bias calculation (T-010): bias vs pte ATT
    // Bias_k = (coef_k - pte_att) / |pte_att| * 100
    // -------------------------------------------------------------------------
    tempname bias_all
    matrix `bias_all' = J(1, 9, .)
    matrix colnames `bias_all' = m1 m2 m3 m4 m5 m6 m7 m8 m9
    
    // Use pte ATT saved before sub-methods ran
    local pte_att_val = `pte_att_saved'
    
    // Compute bias for each model
    if !missing(`pte_att_val') & abs(`pte_att_val') > 1e-10 {
        forvalues m = 1/9 {
            local c_m = `coef_all'[1, `m']
            if !missing(`c_m') {
                matrix `bias_all'[1, `m'] = (`c_m' - `pte_att_val') / abs(`pte_att_val') * 100
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // Spec indicator matrix (T-008): production function specification
    // 1=No lag controls, 2=AR(1) linear, 3=AR(3) cubic
    // Pattern repeats for each method group
    // -------------------------------------------------------------------------
    tempname spec_all
    matrix `spec_all' = (1, 2, 3, 1, 2, 3, 1, 2, 3)
    matrix colnames `spec_all' = m1 m2 m3 m4 m5 m6 m7 m8 m9

    // -------------------------------------------------------------------------
    // Graph interface compatibility matrices (9x1 column vectors)
    // _pte_graph_compare consumes compare_* matrices as stacked method-spec rows.
    // Keep legacy 1x9 *_all matrices for tabular workflows and add 9x1 aliases.
    // -------------------------------------------------------------------------
    tempname compare_coef compare_ci_lower compare_ci_upper compare_spec
    matrix `compare_coef'     = `coef_all''
    matrix `compare_ci_lower' = `ci_lower''
    matrix `compare_ci_upper' = `ci_upper''
    matrix `compare_spec'     = `spec_all''
    matrix rownames `compare_coef'     = m1 m2 m3 m4 m5 m6 m7 m8 m9
    matrix rownames `compare_ci_lower' = m1 m2 m3 m4 m5 m6 m7 m8 m9
    matrix rownames `compare_ci_upper' = m1 m2 m3 m4 m5 m6 m7 m8 m9
    matrix rownames `compare_spec'     = m1 m2 m3 m4 m5 m6 m7 m8 m9
    matrix colnames `compare_coef'     = coef
    matrix colnames `compare_ci_lower' = ci_lower
    matrix colnames `compare_ci_upper' = ci_upper
    matrix colnames `compare_spec'     = spec

    // Snapshot scalar aliases before posting matrices into e(), because
    // ereturn matrix may consume the temporary matrix handles.
    local att_m1 = `coef_expost'[1, 1]
    local att_m2 = `coef_expost'[1, 2]
    local att_m3 = `coef_expost'[1, 3]
    local att_m4 = `coef_endog'[1, 1]
    local att_m5 = `coef_endog'[1, 2]
    local att_m6 = `coef_endog'[1, 3]
    local att_m7 = `coef_clktwfe'[1, 1]
    local att_m8 = `coef_clktwfe'[1, 2]
    local att_m9 = `coef_clktwfe'[1, 3]
    
    // -------------------------------------------------------------------------
    // Post e() return values
    // -------------------------------------------------------------------------
    ereturn clear
    ereturn post, esample(`compare_esample')
    
    // Combined matrices
    ereturn matrix coef_all = `coef_all'
    ereturn matrix se_all   = `se_all'
    ereturn matrix r2_all   = `r2_all'
    ereturn matrix n_all    = `n_all'
    
    // CI matrices (T-009)
    ereturn matrix ci_lower = `ci_lower'
    ereturn matrix ci_upper = `ci_upper'
    
    // t-statistic and p-value matrices (T-008)
    ereturn matrix t_all = `t_all'
    ereturn matrix p_all = `p_all'
    
    // Bias matrix (T-010)
    ereturn matrix bias_all = `bias_all'
    
    // Spec indicator matrix (T-008)
    ereturn matrix spec_all = `spec_all'

    // Graph interface aliases for _pte_graph_compare
    ereturn matrix compare_coef     = `compare_coef'
    ereturn matrix compare_ci_lower = `compare_ci_lower'
    ereturn matrix compare_ci_upper = `compare_ci_upper'
    ereturn matrix compare_spec     = `compare_spec'
    
    // Per-method matrices
    ereturn matrix coef_expost  = `coef_expost'
    ereturn matrix se_expost    = `se_expost'
    ereturn matrix coef_endog   = `coef_endog'
    ereturn matrix se_endog     = `se_endog'
    ereturn matrix coef_clktwfe = `coef_clktwfe'
    ereturn matrix se_clktwfe   = `se_clktwfe'
    
    // Individual scalars for easy access
    ereturn scalar att_m1 = `att_m1'
    ereturn scalar att_m2 = `att_m2'
    ereturn scalar att_m3 = `att_m3'
    ereturn scalar att_m4 = `att_m4'
    ereturn scalar att_m5 = `att_m5'
    ereturn scalar att_m6 = `att_m6'
    ereturn scalar att_m7 = `att_m7'
    ereturn scalar att_m8 = `att_m8'
    ereturn scalar att_m9 = `att_m9'
    ereturn scalar omegapoly = `omegapoly'
    
    // pte ATT scalar (T-014)
    if !missing(`pte_att_val') {
        ereturn scalar pte_att = `pte_att_val'
    }
    
    // Method status
    ereturn scalar rc_expost  = `expost_rc'
    ereturn scalar rc_endog   = `endog_rc'
    ereturn scalar rc_clktwfe = `clktwfe_rc'
    
    // Strings
    ereturn local cmd "pte_compare"
    ereturn local method "all"
    ereturn local treatment "`treatment'"
    ereturn local absorb "`absorb'"
    ereturn local specs "`specs'"
    
end
