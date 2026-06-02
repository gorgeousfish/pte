*! _pte_bias_report.ado
*! v1.0
*! Based on Paper Section 5: Discussion of the Potential Productivity Process

version 14.0
capture program drop _pte_bias_report
program define _pte_bias_report, eclass
    version 14.0
    
    syntax , [DIAGfile(string) QUIetly]
    
    // =========================================================================
    // Task 1: Validate prerequisites
    // =========================================================================
    
    capture confirm matrix e(att)
    if _rc {
        di as error "Error 301: pte has not been run."
        di as error "Please run {bf:pte} first, then {bf:pte_compare}."
        exit 301
    }
    
    // =========================================================================
    // Task 2: Extract pte ATT mean
    // =========================================================================
    
    tempname att_pte
    matrix `att_pte' = e(att)
    local ncols = colsof(`att_pte')
    
    // Compute mean ATT (exclude last column if it is pooled/avg)
    local att_sum = 0
    local att_count = `ncols'
    if `ncols' > 1 {
        local att_count = `ncols' - 1
    }
    forvalues i = 1/`att_count' {
        local att_sum = `att_sum' + `att_pte'[1, `i']
    }
    local att_pte_mean = `att_sum' / `att_count'
    
    // =========================================================================
    // Task 3: Retrieve traditional method ATT estimates
    // =========================================================================
    
    local att_expost = .
    local att_endo = .
    local att_clk_twfe = .
    
    capture confirm scalar e(att_expost_3)
    if !_rc local att_expost = e(att_expost_3)
    
    // Primary: match _pte_compare_endog.ado's actual output name
    capture confirm scalar e(att_endog_3)
    if !_rc {
        local att_endo = e(att_endog_3)
    }
    else {
        // Fallback: legacy name for backward compatibility
        capture confirm scalar e(att_endo_3)
        if !_rc local att_endo = e(att_endo_3)
    }
    
    capture confirm scalar e(att_clk_twfe_3)
    if !_rc local att_clk_twfe = e(att_clk_twfe_3)
    
    // =========================================================================
    // Task 4: Build Problem Diagnosis Matrix (Paper Section 5)
    // =========================================================================
    // 4x3 matrix: rows = methods, cols = Problem 1/2/3
    // Values: 1 = YES, 0.5 = PARTIAL, 0 = NO
    
    tempname problem_matrix
    matrix `problem_matrix' = J(4, 3, 0)
    
    // Ex-post: no interaction + transition included -> all YES
    matrix `problem_matrix'[1, 1] = 1
    matrix `problem_matrix'[1, 2] = 1
    matrix `problem_matrix'[1, 3] = 1
    
    // Endogenous: interaction + transition included -> all YES
    matrix `problem_matrix'[2, 1] = 1
    matrix `problem_matrix'[2, 2] = 1
    matrix `problem_matrix'[2, 3] = 1
    
    // CLK+TWFE: transition excluded + TWFE -> PARTIAL/NO/PARTIAL
    matrix `problem_matrix'[3, 1] = 0.5
    matrix `problem_matrix'[3, 2] = 0
    matrix `problem_matrix'[3, 3] = 0.5
    
    // pte: all NO (fully addresses all problems)
    matrix `problem_matrix'[4, 1] = 0
    matrix `problem_matrix'[4, 2] = 0
    matrix `problem_matrix'[4, 3] = 0
    
    matrix rownames `problem_matrix' = "Ex-post" "Endogenous" "CLK+TWFE" "pte"
    matrix colnames `problem_matrix' = "Problem1" "Problem2" "Problem3"
    
    // =========================================================================
    // Task 5: Quantitative bias calculation
    // =========================================================================
    
    tempname bias_quantitative bias_direction
    matrix `bias_quantitative' = J(4, 2, .)
    matrix `bias_direction' = J(4, 1, 0)
    
    // Ex-post bias
    if `att_expost' != . {
        local bias_abs = `att_expost' - `att_pte_mean'
        if abs(`att_pte_mean') > 1e-10 {
            local bias_rel = `bias_abs' / `att_pte_mean' * 100
        }
        else {
            local bias_rel = .
        }
        matrix `bias_quantitative'[1, 1] = `bias_abs'
        matrix `bias_quantitative'[1, 2] = `bias_rel'
        matrix `bias_direction'[1, 1] = sign(`bias_abs')
    }
    
    // Endogenous bias
    if `att_endo' != . {
        local bias_abs = `att_endo' - `att_pte_mean'
        if abs(`att_pte_mean') > 1e-10 {
            local bias_rel = `bias_abs' / `att_pte_mean' * 100
        }
        else {
            local bias_rel = .
        }
        matrix `bias_quantitative'[2, 1] = `bias_abs'
        matrix `bias_quantitative'[2, 2] = `bias_rel'
        matrix `bias_direction'[2, 1] = sign(`bias_abs')
    }
    
    // CLK+TWFE bias
    if `att_clk_twfe' != . {
        local bias_abs = `att_clk_twfe' - `att_pte_mean'
        if abs(`att_pte_mean') > 1e-10 {
            local bias_rel = `bias_abs' / `att_pte_mean' * 100
        }
        else {
            local bias_rel = .
        }
        matrix `bias_quantitative'[3, 1] = `bias_abs'
        matrix `bias_quantitative'[3, 2] = `bias_rel'
        matrix `bias_direction'[3, 1] = sign(`bias_abs')
    }
    
    // pte bias = 0 (baseline)
    matrix `bias_quantitative'[4, 1] = 0
    matrix `bias_quantitative'[4, 2] = 0
    matrix `bias_direction'[4, 1] = 0
    
    matrix rownames `bias_quantitative' = "Ex-post" "Endogenous" "CLK+TWFE" "pte"
    matrix colnames `bias_quantitative' = "AbsBias" "RelBias_pct"
    matrix rownames `bias_direction' = "Ex-post" "Endogenous" "CLK+TWFE" "pte"
    matrix colnames `bias_direction' = "Direction"
    
    // =========================================================================
    // Tasks 7-12: Report output
    // =========================================================================
    
    if "`quietly'" == "" {
        
        // Task 7: Report header
        di as text ""
        di as text "{hline 79}"
        di as text "BIAS SOURCE ANALYSIS REPORT"
        di as text "Based on Paper Section 5: Discussion of the Potential Productivity Process"
        di as text "{hline 79}"
        di as text ""
        
        // ATT estimates summary
        di as text "ATT Estimates:"
        di as text "  pte (baseline):  " %10.6f `att_pte_mean'
        if `att_expost' != . {
            di as text "  Ex-post:         " %10.6f `att_expost'
        }
        else {
            di as text "  Ex-post:         (not estimated)"
        }
        if `att_endo' != . {
            di as text "  Endogenous:      " %10.6f `att_endo'
        }
        else {
            di as text "  Endogenous:      (not estimated)"
        }
        if `att_clk_twfe' != . {
            di as text "  CLK+TWFE:        " %10.6f `att_clk_twfe'
        }
        else {
            di as text "  CLK+TWFE:        (not estimated)"
        }
        di as text ""
        
        // Task 8-10: Method detail for each method
        // Method I: Ex-post
        di as text "{hline 79}"
        di as text "METHOD I: Ex-post Regression + TWFE"
        di as text "{hline 79}"
        di as text "Assumptions:"
        di as text "  - Exogenous productivity process"
        di as text "  - h0 = h1 (no treatment-productivity interaction)"
        di as text "  - Transition period included in estimation"
        di as text ""
        di as text "Problem Diagnosis:"
        di as text "  Problem 1 (Unobserved Heterogeneity):      YES"
        di as text "    Firm observes (omega0, omega1), econometrician only omega"
        di as text "  Problem 2 (Misleading Causal Interpretation): YES"
        di as text "    Stays agnostic about treatment effect mechanism"
        di as text "  Problem 3 (Misleading ATE):                YES"
        di as text "    TWFE estimates ATE, not ATT on treated"
        if `att_expost' != . {
            di as text ""
            di as text "Quantitative Bias (vs pte):"
            di as text "  Absolute: " %10.6f `bias_quantitative'[1, 1]
            if !mi(`bias_quantitative'[1, 2]) {
                di as text "  Relative: " %8.2f `bias_quantitative'[1, 2] "%"
            }
        }
        di as text ""
        
        // Method II: Endogenous
        di as text "{hline 79}"
        di as text "METHOD II: Endogenous Productivity + TWFE"
        di as text "{hline 79}"
        di as text "Assumptions:"
        di as text "  - Endogenous productivity (treatment interaction)"
        di as text "  - Transition period included in estimation"
        di as text ""
        di as text "Problem Diagnosis:"
        di as text "  Problem 1 (Unobserved Heterogeneity):      YES"
        di as text "  Problem 2 (Misleading Causal Interpretation): YES"
        di as text "  Problem 3 (Misleading ATE):                YES"
        if `att_endo' != . {
            di as text ""
            di as text "Quantitative Bias (vs pte):"
            di as text "  Absolute: " %10.6f `bias_quantitative'[2, 1]
            if !mi(`bias_quantitative'[2, 2]) {
                di as text "  Relative: " %8.2f `bias_quantitative'[2, 2] "%"
            }
        }
        di as text ""
        
        // Method III: CLK+TWFE
        di as text "{hline 79}"
        di as text "METHOD III: CLK Correction + TWFE"
        di as text "{hline 79}"
        di as text "Assumptions:"
        di as text "  - CLK correction (transition period excluded)"
        di as text "  - TWFE for ATT estimation"
        di as text ""
        di as text "Problem Diagnosis:"
        di as text "  Problem 1 (Unobserved Heterogeneity):      PARTIAL"
        di as text "    Transition excluded, but TWFE limitations remain"
        di as text "  Problem 2 (Misleading Causal Interpretation): NO"
        di as text "    CLK correction addresses this"
        di as text "  Problem 3 (Misleading ATE):                PARTIAL"
        di as text "    TWFE still estimates ATE rather than simulation ATT"
        if `att_clk_twfe' != . {
            di as text ""
            di as text "Quantitative Bias (vs pte):"
            di as text "  Absolute: " %10.6f `bias_quantitative'[3, 1]
            if !mi(`bias_quantitative'[3, 2]) {
                di as text "  Relative: " %8.2f `bias_quantitative'[3, 2] "%"
            }
        }
        di as text ""
        
        // Method IV: pte (baseline)
        di as text "{hline 79}"
        di as text "METHOD IV: pte (Potential Productivity Framework)"
        di as text "{hline 79}"
        di as text "Assumptions:"
        di as text "  - Potential productivity framework"
        di as text "  - CLK correction (transition period excluded)"
        di as text "  - Simulation-based counterfactual ATT"
        di as text ""
        di as text "Problem Diagnosis:"
        di as text "  Problem 1 (Unobserved Heterogeneity):      NO"
        di as text "    Transition excluded, simulation avoids dependence on omega1"
        di as text "  Problem 2 (Misleading Causal Interpretation): NO"
        di as text "    Stays agnostic, uses potential productivity"
        di as text "  Problem 3 (Misleading ATE):                NO"
        di as text "    Simulation-based counterfactual computes true ATT"
        di as text ""
        di as text "  This is the BASELINE method (bias = 0 by definition)"
        di as text ""
        
        // Task 11: Summary tables
        di as text "{hline 79}"
        di as text "SUMMARY: PROBLEM DIAGNOSIS MATRIX"
        di as text "{hline 79}"
        di as text ""
        di as text "                    | Problem 1  | Problem 2  | Problem 3  |"
        di as text "  {hline 62}"
        
        // Row 1: Ex-post
        local p1 = cond(`problem_matrix'[1,1]==1, "YES", cond(`problem_matrix'[1,1]==0.5, "PARTIAL", "NO"))
        local p2 = cond(`problem_matrix'[1,2]==1, "YES", cond(`problem_matrix'[1,2]==0.5, "PARTIAL", "NO"))
        local p3 = cond(`problem_matrix'[1,3]==1, "YES", cond(`problem_matrix'[1,3]==0.5, "PARTIAL", "NO"))
        di as text "  Ex-post           |" %10s "`p1'" " |" %10s "`p2'" " |" %10s "`p3'" " |"
        
        // Row 2: Endogenous
        local p1 = cond(`problem_matrix'[2,1]==1, "YES", cond(`problem_matrix'[2,1]==0.5, "PARTIAL", "NO"))
        local p2 = cond(`problem_matrix'[2,2]==1, "YES", cond(`problem_matrix'[2,2]==0.5, "PARTIAL", "NO"))
        local p3 = cond(`problem_matrix'[2,3]==1, "YES", cond(`problem_matrix'[2,3]==0.5, "PARTIAL", "NO"))
        di as text "  Endogenous        |" %10s "`p1'" " |" %10s "`p2'" " |" %10s "`p3'" " |"
        
        // Row 3: CLK+TWFE
        local p1 = cond(`problem_matrix'[3,1]==1, "YES", cond(`problem_matrix'[3,1]==0.5, "PARTIAL", "NO"))
        local p2 = cond(`problem_matrix'[3,2]==1, "YES", cond(`problem_matrix'[3,2]==0.5, "PARTIAL", "NO"))
        local p3 = cond(`problem_matrix'[3,3]==1, "YES", cond(`problem_matrix'[3,3]==0.5, "PARTIAL", "NO"))
        di as text "  CLK+TWFE          |" %10s "`p1'" " |" %10s "`p2'" " |" %10s "`p3'" " |"
        
        // Row 4: pte
        local p1 = cond(`problem_matrix'[4,1]==1, "YES", cond(`problem_matrix'[4,1]==0.5, "PARTIAL", "NO"))
        local p2 = cond(`problem_matrix'[4,2]==1, "YES", cond(`problem_matrix'[4,2]==0.5, "PARTIAL", "NO"))
        local p3 = cond(`problem_matrix'[4,3]==1, "YES", cond(`problem_matrix'[4,3]==0.5, "PARTIAL", "NO"))
        di as text "  pte (baseline)    |" %10s "`p1'" " |" %10s "`p2'" " |" %10s "`p3'" " |"
        
        di as text "  {hline 62}"
        di as text ""
        
        // Quantitative bias summary table
        di as text "QUANTITATIVE BIAS SUMMARY (vs pte baseline):"
        di as text ""
        di as text "                    |   ATT Est  | Abs. Bias  | Rel. Bias  |"
        di as text "  {hline 62}"
        
        if `att_expost' != . {
            di as text "  Ex-post           |" %10.4f `att_expost' " |" ///
                %10.4f `bias_quantitative'[1,1] " |" ///
                %9.1f `bias_quantitative'[1,2] "% |"
        }
        else {
            di as text "  Ex-post           |       n/a  |       n/a  |       n/a  |"
        }
        
        if `att_endo' != . {
            di as text "  Endogenous        |" %10.4f `att_endo' " |" ///
                %10.4f `bias_quantitative'[2,1] " |" ///
                %9.1f `bias_quantitative'[2,2] "% |"
        }
        else {
            di as text "  Endogenous        |       n/a  |       n/a  |       n/a  |"
        }
        
        if `att_clk_twfe' != . {
            di as text "  CLK+TWFE          |" %10.4f `att_clk_twfe' " |" ///
                %10.4f `bias_quantitative'[3,1] " |" ///
                %9.1f `bias_quantitative'[3,2] "% |"
        }
        else {
            di as text "  CLK+TWFE          |       n/a  |       n/a  |       n/a  |"
        }
        
        di as text "  pte (baseline)    |" %10.4f `att_pte_mean' " |" ///
            %10.4f 0 " |" %9.1f 0 "% |"
        
        di as text "  {hline 62}"
        di as text ""
        
        // Task 12: Conclusion
        di as text "{hline 79}"
        di as text "CONCLUSION"
        di as text "{hline 79}"
        di as text ""
        di as text "The pte method (CLK correction + Simulation-based ATT) addresses all three"
        di as text "problems identified in Section 5 of the paper:"
        di as text ""
        di as text "1. Unobserved Heterogeneity: Resolved by excluding transition period"
        di as text "   observations and using potential productivity framework."
        di as text "2. Misleading Causal Interpretation: Resolved by staying agnostic about"
        di as text "   the treatment effect mechanism."
        di as text "3. Misleading ATE: Resolved by simulation-based counterfactual that"
        di as text "   computes the true ATT on the treated."
        di as text ""
        di as text "For details, see:"
        di as text "  - Paper Section 5 (Discussion)"
        di as text "  - Paper Figure 2 (Bias illustration)"
        di as text "  - Paper Figure 6 (Method comparison)"
        di as text "{hline 79}"
        
        // ATT near zero warning
        if abs(`att_pte_mean') < 1e-10 {
            di as text ""
            di as text "Warning: pte ATT mean is approximately 0 (|ATT| < 1e-10)"
            di as text "  Relative bias (RelBias) set to missing (.)"
            di as text "  Absolute bias values remain valid."
        }
    }
    
    // =========================================================================
    // Task 14: File output (diagfile option)
    // =========================================================================
    
    if "`diagfile'" != "" {
        capture file close _diagfile
        
        capture file open _diagfile using "`diagfile'", write replace
        if _rc {
            di as error "Error: cannot write to file: `diagfile'"
            exit 603
        }
        
        file write _diagfile "BIAS SOURCE ANALYSIS REPORT" _n
        file write _diagfile "Based on Paper Section 5" _n
        file write _diagfile "Generated: `c(current_date)' `c(current_time)'" _n
        file write _diagfile "" _n
        file write _diagfile "ATT Estimates:" _n
        
        local att_pte_str : di %10.6f `att_pte_mean'
        file write _diagfile "  pte (baseline): `att_pte_str'" _n
        
        if `att_expost' != . {
            local att_ep_str : di %10.6f `att_expost'
            file write _diagfile "  Ex-post:        `att_ep_str'" _n
        }
        if `att_endo' != . {
            local att_en_str : di %10.6f `att_endo'
            file write _diagfile "  Endogenous:     `att_en_str'" _n
        }
        if `att_clk_twfe' != . {
            local att_ct_str : di %10.6f `att_clk_twfe'
            file write _diagfile "  CLK+TWFE:       `att_ct_str'" _n
        }
        
        file write _diagfile "" _n
        file write _diagfile "Problem Diagnosis Matrix:" _n
        file write _diagfile "  Ex-post:    P1=YES  P2=YES  P3=YES" _n
        file write _diagfile "  Endogenous: P1=YES  P2=YES  P3=YES" _n
        file write _diagfile "  CLK+TWFE:   P1=PARTIAL  P2=NO  P3=PARTIAL" _n
        file write _diagfile "  pte:        P1=NO  P2=NO  P3=NO" _n
        
        file close _diagfile
        di as result "Diagnostic report saved to: `diagfile'"
    }
    
    // =========================================================================
    // Task 6: Store e() return values
    // =========================================================================
    
    // Extract scalar values before ereturn matrix moves tempnames
    local s_att_pte_mean = `att_pte_mean'
    
    if `att_expost' != . {
        local s_bias_expost = `bias_quantitative'[1, 1]
        local s_relbias_expost = `bias_quantitative'[1, 2]
    }
    if `att_endo' != . {
        local s_bias_endo = `bias_quantitative'[2, 1]
        local s_relbias_endo = `bias_quantitative'[2, 2]
    }
    if `att_clk_twfe' != . {
        local s_bias_clk_twfe = `bias_quantitative'[3, 1]
        local s_relbias_clk_twfe = `bias_quantitative'[3, 2]
    }

    // Rebuild a self-consistent eclass shell while preserving the existing
    // compare-result payload already stored in e().
    tempname b_report V_report
    tempvar bias_report_sample
    matrix `b_report' = (`s_att_pte_mean')
    matrix colnames `b_report' = att_pte_mean
    matrix coleq `b_report' = ""
    matrix `V_report' = (0)
    matrix rownames `V_report' = att_pte_mean
    matrix colnames `V_report' = att_pte_mean
    quietly gen byte `bias_report_sample' = 0
    ereturn repost b=`b_report' V=`V_report', resize esample(`bias_report_sample')
    
    // Matrix return values
    ereturn matrix problem_matrix = `problem_matrix'
    ereturn matrix bias_quantitative = `bias_quantitative'
    ereturn matrix bias_direction = `bias_direction'
    
    // Scalar return values
    ereturn scalar att_pte_mean = `s_att_pte_mean'
    
    if `att_expost' != . {
        ereturn scalar bias_expost = `s_bias_expost'
        ereturn scalar relbias_expost = `s_relbias_expost'
    }
    if `att_endo' != . {
        ereturn scalar bias_endo = `s_bias_endo'
        ereturn scalar relbias_endo = `s_relbias_endo'
    }
    if `att_clk_twfe' != . {
        ereturn scalar bias_clk_twfe = `s_bias_clk_twfe'
        ereturn scalar relbias_clk_twfe = `s_relbias_clk_twfe'
    }
    
    // Macro return values
    ereturn local diagnose "yes"
    ereturn local cmd "pte_compare"
    ereturn local assumptions_expost "Exogenous; h0=h1; No interaction; Transition included"
    ereturn local assumptions_endo "Endogenous; Interaction; Transition included"
    ereturn local assumptions_clk_twfe "CLK correction; Transition excluded; TWFE ATT"
    ereturn local assumptions_pte "Potential productivity; CLK; Simulation ATT"
    
end
