*! _pte_hetero_qtest.ado
*! Heterogeneity Q-Test (Cochran's Q) for cohort ATT estimates
*! Q = sum(w_g * (ATT_g - ATT_pool)^2), Q ~ chi2(G-1)
*! I2 = max(0, (Q - df) / Q) * 100

version 14.0
capture program drop _pte_hetero_qtest
program define _pte_hetero_qtest, rclass
    version 14.0
    
    // ================================================================
    // Syntax parsing
    // ================================================================
    
    syntax [, POOL]
    
    local do_pool = 0
    if "`pool'" != "" {
        local do_pool = 1
    }
    
    // ================================================================
    // Input validation: check e() matrices exist
    // ================================================================
    
    cap confirm matrix e(att_cohort)
    if _rc != 0 {
        di as error "{bf:pte error E-3016}: e(att_cohort) not found"
        di as error "  Run cohort ATT estimation first"
        exit 498
    }
    
    cap confirm matrix e(att_cohort_se)
    if _rc != 0 {
        di as error "{bf:pte error E-3016}: e(att_cohort_se) not found"
        di as error "  Run cohort ATT estimation first"
        exit 498
    }
    
    // Check minimum cohort count
    local G = rowsof(e(att_cohort))
    if `G' < 2 {
        di as error "{bf:pte error E-3011}: heterogeneity test requires at least 2 cohorts with valid SE"
        exit 3011
    }
    
    // ================================================================
    // Compute Q-test via Mata
    // ================================================================
    
    tempname Q_mat p_mat I2_mat df_mat G_mat df_val G_val Q_pool_val p_pool_val df_pool_val
    
    mata: _pte_hetero_qtest_compute(`do_pool')
    
    // ================================================================
    // Display results BEFORE return (return matrix moves data)
    // ================================================================
    
    local ncols = colsof(`Q_mat')
    
    di as text ""
    di as text "Cohort Heterogeneity Test (Cochran's Q-statistic)"
    di as text "{hline 70}"
    di as text %10s "Period" %12s "Q" %8s "G" %8s "df" %12s "p-value" %10s "I2(%)" %10s "Level"
    di as text "{hline 70}"
    
    forvalues l = 1/`ncols' {
        local period = `l' - 1
        local Q_l = `Q_mat'[1,`l']
        local p_l = `p_mat'[1,`l']
        local I2_l = `I2_mat'[1,`l']
        local df_l = `df_mat'[1,`l']
        local G_l = `G_mat'[1,`l']
        
        // Significance stars
        local stars = ""
        if `p_l' < 0.01 {
            local stars = "***"
        }
        else if `p_l' < 0.05 {
            local stars = "**"
        }
        else if `p_l' < 0.10 {
            local stars = "*"
        }
        
        // I2 level label
        local level_label = ""
        if `I2_l' < 25 {
            local level_label = "low"
        }
        else if `I2_l' < 50 {
            local level_label = "low-mod"
        }
        else if `I2_l' < 75 {
            local level_label = "moderate"
        }
        else {
            local level_label = "high"
        }
        
        if `Q_l' < . {
            di as text %10.0f `period' ///
               as result %12.4f `Q_l' ///
               as text %8.0f `G_l' ///
               as text %8.0f `df_l' ///
               as result %12.4f `p_l' ///
               as text " `stars'" ///
               as result %8.1f `I2_l' ///
               as text "  `level_label'"
        }
        else {
            di as text %10.0f `period' ///
               as text %12s "." ///
               as text %8.0f `G_l' ///
               as text %8s "." ///
               as text %12s "." ///
               as text %10s "." ///
               as text "  ."
        }
    }
    
    di as text "{hline 70}"
    di as text "  *** p<0.01, ** p<0.05, * p<0.10"
    if `df_val' < . & `G_val' < . {
        di as text "  df = `=`df_val'', G = `=`G_val'' valid cohorts"
    }
    else {
        di as text "  df/G vary by period; see r(df_period) and r(G_period)"
    }
    
    // Pooled Q display
    if `do_pool' == 1 & `Q_pool_val' < . {
        di as text ""
        di as text "  Pooled Q = " as result %9.4f `Q_pool_val' ///
           as text ", df = " as result %4.0f `df_pool_val' ///
           as text ", p = " as result %9.4f `p_pool_val'
    }
    
    // ================================================================
    // Store results in r()
    // ================================================================
    
    return scalar df = `df_val'
    return scalar G = `G_val'
    
    if `do_pool' == 1 {
        return scalar Q_pool = `Q_pool_val'
        return scalar p_pool = `p_pool_val'
        return scalar df_pool = `df_pool_val'
    }
    
    return matrix Q = `Q_mat'
    return matrix p = `p_mat'
    return matrix I2 = `I2_mat'
    return matrix df_period = `df_mat'
    return matrix G_period = `G_mat'
    
end
