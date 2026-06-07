*! _pte_ivw_aggregate.ado
*! Inverse Variance Weighted ATT Aggregation
*! Formula: ATT_pool = sum(w_g * ATT_g) / sum(w_g), w_g = 1/SE_g^2

version 14.0
capture program drop _pte_ivw_aggregate
program define _pte_ivw_aggregate, eclass
    version 14.0
    
    // ================================================================
    // T3: Syntax parsing
    // ================================================================
    
    syntax [, Level(integer 95)]
    
    if `level' < 10 | `level' > 99 {
        di as error "Error: level() must be between 10 and 99"
        exit 198
    }
    
    // ================================================================
    // T4: Input matrix validation
    // ================================================================
    
    cap confirm matrix e(att_cohort)
    if _rc != 0 {
        di as error "Error: e(att_cohort) not found"
        di as error "  Run cohort ATT estimation first"
        exit 498
    }
    
    cap confirm matrix e(att_cohort_se)
    if _rc != 0 {
        di as error "Error: e(att_cohort_se) not found"
        di as error "  Run cohort ATT estimation first"
        exit 498
    }

    tempname ATT_cohort SE_cohort
    matrix `ATT_cohort' = e(att_cohort)
    matrix `SE_cohort' = e(att_cohort_se)

    // Preserve upstream cohort metadata before ereturn post rebuilds the
    // result object. Downstream cohort consumers still need the exact
    // event-time support and cohort payload after standalone IVW aggregation.
    tempname ATTPERIODS COHORT_LIST COHORT_SIZES
    local has_attperiods 0
    local has_cohort_list 0
    local has_cohort_sizes 0
    local has_n_cohorts 0
    local has_matchstrategy 0
    local has_matchexpr 0

    capture confirm matrix e(attperiods)
    if !_rc {
        matrix `ATTPERIODS' = e(attperiods)
        local has_attperiods 1
    }
    capture confirm matrix e(cohort_list)
    if !_rc {
        matrix `COHORT_LIST' = e(cohort_list)
        local has_cohort_list 1
    }
    capture confirm matrix e(cohort_sizes)
    if !_rc {
        matrix `COHORT_SIZES' = e(cohort_sizes)
        local has_cohort_sizes 1
    }
    capture confirm scalar e(n_cohorts)
    if !_rc {
        local has_n_cohorts 1
        local n_cohorts = e(n_cohorts)
    }
    capture local preserved_matchstrategy = e(matchstrategy)
    if !_rc {
        local has_matchstrategy 1
    }
    capture local preserved_matchexpr = e(matchexpr)
    if !_rc {
        local has_matchexpr 1
    }
    
    // ================================================================
    // T5-T12: Core IVW computation in Mata
    // ================================================================
    
    tempname ATT_pool SE_pool CI_lo CI_hi IVW_W N_valid b V

    mata: _pte_ivw_compute(`level')

    // ================================================================
    // T11: Rebuild a fresh eclass result object
    // ================================================================

    local L_plus_1 = colsof(`ATT_pool')
    local surface_colnames ""
    local b_colnames ""

    if `has_attperiods' {
        forvalues l = 1/`L_plus_1' {
            local period_val = `ATTPERIODS'[1, `l']
            if missing(`period_val') {
                di as error "_pte_ivw_aggregate: e(attperiods) must not contain missing event-time support."
                exit 198
            }
            if floor(`period_val') != `period_val' {
                di as error "_pte_ivw_aggregate: e(attperiods) must contain integer event-time support."
                exit 198
            }
            if `period_val' < 0 {
                di as error "_pte_ivw_aggregate: e(attperiods) must contain nonnegative event-time support."
                exit 198
            }
            if `l' > 1 {
                local prev_period = `ATTPERIODS'[1, `=`l' - 1']
                if `period_val' <= `prev_period' {
                    di as error "_pte_ivw_aggregate: e(attperiods) must be strictly increasing without duplicates."
                    exit 198
                }
            }
            local period_str = trim(string(`period_val', "%21.0g"))
            local surface_colnames "`surface_colnames' nt`period_str'"
            local b_colnames "`b_colnames' ATT_`period_str'"
        }
    }
    else {
        local upstream_cols : colnames `ATT_cohort'
        local parsed_support = 1
        local n_upstream_cols : word count `upstream_cols'
        if `n_upstream_cols' != `L_plus_1' {
            local parsed_support = 0
        }
        else {
            forvalues l = 1/`L_plus_1' {
                local upstream_tok : word `l' of `upstream_cols'
                local period_str ""
                if regexm(`"`upstream_tok'"', "^nt(-?[0-9.]+)$") {
                    local period_str = regexs(1)
                }
                else if regexm(`"`upstream_tok'"', "^ATT_(-?[0-9.]+)$") {
                    local period_str = regexs(1)
                }
                else if regexm(`"`upstream_tok'"', "^ATT(-?[0-9.]+)$") {
                    local period_str = regexs(1)
                }
                else {
                    local parsed_support = 0
                    continue, break
                }
                local surface_colnames "`surface_colnames' nt`period_str'"
                local b_colnames "`b_colnames' ATT_`period_str'"
            }
        }

        if !`parsed_support' {
            local surface_colnames ""
            local b_colnames ""
            forvalues l = 1/`L_plus_1' {
                local period_val = `l' - 1
                local surface_colnames "`surface_colnames' nt`period_val'"
                local b_colnames "`b_colnames' ATT_`period_val'"
            }
        }
    }

    local surface_colnames : list retokenize surface_colnames
    local b_colnames : list retokenize b_colnames

    matrix colnames `ATT_pool' = `surface_colnames'
    matrix colnames `SE_pool' = `surface_colnames'
    matrix colnames `CI_lo' = `surface_colnames'
    matrix colnames `CI_hi' = `surface_colnames'
    matrix colnames `N_valid' = `surface_colnames'
    matrix colnames `IVW_W' = `surface_colnames'
    local ivw_row_names : rownames `ATT_cohort'
    if `"`ivw_row_names'"' != "" {
        matrix rownames `IVW_W' = `ivw_row_names'
    }

    matrix `b' = `ATT_pool'
    matrix colnames `b' = `b_colnames'
    matrix coleq `b' = ""

    matrix `V' = J(`L_plus_1', `L_plus_1', 0)
    forvalues l = 1/`L_plus_1' {
        local se_val = `SE_pool'[1, `l']
        matrix `V'[`l', `l'] = `se_val'^2
    }
    matrix rownames `V' = `b_colnames'
    matrix colnames `V' = `b_colnames'

    ereturn post `b' `V', depname("ATT")

    ereturn matrix att_cohort = `ATT_cohort'
    ereturn matrix att_cohort_se = `SE_cohort'
    ereturn matrix att_pool = `ATT_pool'
    ereturn matrix att_pool_se = `SE_pool'
    ereturn matrix att_pool_ci_lo = `CI_lo'
    ereturn matrix att_pool_ci_hi = `CI_hi'
    ereturn matrix ivw_weights = `IVW_W'
    ereturn matrix n_valid_cohorts = `N_valid'
    ereturn scalar level = `level'
    if `has_attperiods' {
        ereturn matrix attperiods = `ATTPERIODS'
    }
    if `has_cohort_list' {
        ereturn matrix cohort_list = `COHORT_LIST'
    }
    if `has_cohort_sizes' {
        ereturn matrix cohort_sizes = `COHORT_SIZES'
    }
    if `has_n_cohorts' {
        ereturn scalar n_cohorts = `n_cohorts'
    }
    if `has_matchstrategy' {
        ereturn local matchstrategy `"`preserved_matchstrategy'"'
    }
    if `has_matchexpr' {
        ereturn local matchexpr `"`preserved_matchexpr'"'
    }
    ereturn local cmd "_pte_ivw_aggregate"
    ereturn local cmdline `"_pte_ivw_aggregate, level(`level')"'
    
    // ================================================================
    // T13: Display results
    // ================================================================
    
    di as text ""
    di as text "Pooled ATT (Inverse Variance Weighted):"
    di as text "{hline 60}"
    di as text "  Confidence level: `level'%"
    di as text ""
    tempname att_disp se_disp ci_lo_disp ci_hi_disp
    matrix `att_disp' = e(att_pool)
    matrix `se_disp' = e(att_pool_se)
    matrix `ci_lo_disp' = e(att_pool_ci_lo)
    matrix `ci_hi_disp' = e(att_pool_ci_hi)

    // Header row
    tempname period_disp
    if `has_attperiods' {
        matrix `period_disp' = e(attperiods)
    }
    di as text _col(10) _c
    forvalues l = 1/`L_plus_1' {
        if `has_attperiods' {
            local period_val = `period_disp'[1, `l']
        }
        else {
            local period_val = `l' - 1
        }
        local period_str = trim(string(`period_val', "%21.0g"))
        di as text %12s "nt=`period_str'" _c
    }
    di ""
    di as text "{hline 60}"
    
    // ATT row
    di as text "ATT_pool" _col(10) _c
    forvalues l = 1/`L_plus_1' {
        di as result %12.4f `att_disp'[1, `l'] _c
    }
    di ""
    
    // SE row
    di as text "SE" _col(10) _c
    forvalues l = 1/`L_plus_1' {
        di as text %12.4f `se_disp'[1, `l'] _c
    }
    di ""
    
    // CI row
    di as text "[`level'% CI]" _col(10) _c
    forvalues l = 1/`L_plus_1' {
        local lo = `ci_lo_disp'[1, `l']
        local hi = `ci_hi_disp'[1, `l']
        local ci_str : di %5.3f `lo' "," %5.3f `hi'
        di as text %12s "[`ci_str']" _c
    }
    di ""
    di as text "{hline 60}"
    
end

// ================================================================
// Mata function: core IVW computation
// ================================================================

mata:
void _pte_ivw_compute(real scalar level)
{
    real matrix ATT, SE, W
    real matrix ATT_pool, SE_pool, CI_lo, CI_hi, N_valid
    real scalar G, L_plus_1, g, l, n_v
    real scalar alpha, z_crit
    real colvector valid_idx, w_l, att_l
    
    // T4: Read input matrices
    ATT = st_matrix("e(att_cohort)")
    SE  = st_matrix("e(att_cohort_se)")
    
    G = rows(ATT)
    L_plus_1 = cols(ATT)
    
    // T5: Dimension validation
    if (rows(SE) != G | cols(SE) != L_plus_1) {
        errprintf("\nError 3016: Dimension mismatch\n")
        errprintf("  e(att_cohort): %g x %g\n", G, L_plus_1)
        errprintf("  e(att_cohort_se): %g x %g\n", rows(SE), cols(SE))
        exit(3016)
    }

    // Standard errors are scale parameters and must be nonnegative.
    // Negative inputs are invalid, not a cohort to be silently dropped.
    if (sum(vec((SE :< 0) :& !missing(SE))) > 0) {
        errprintf("\n{bf:pte error E-3016}: Negative SE values detected\n")
        errprintf("  e(att_cohort_se) must contain only nonnegative standard errors or missing values\n")
        exit(3016)
    }
    
    // T6-T7: Weight calculation with boundary handling
    W = J(G, L_plus_1, .)
    
    for (g=1; g<=G; g++) {
        for (l=1; l<=L_plus_1; l++) {
            if (!missing(ATT[g, l]) & !missing(SE[g, l]) & SE[g, l] > 0) {
                W[g, l] = 1 / (SE[g, l]^2)
            }
            else {
                W[g, l] = .
                if (missing(ATT[g, l])) {
                    printf("{txt}Warning W-3015: Cohort %g period %g: ATT missing, excluded\n", g, l-1)
                }
                else if (missing(SE[g, l])) {
                    printf("{txt}Warning W-3015: Cohort %g period %g: SE missing, excluded\n", g, l-1)
                }
                else {
                    printf("{txt}Warning W-3015: Cohort %g period %g: SE=0, excluded\n", g, l-1)
                }
            }
        }
    }
    
    // T8-T9: Weighted average ATT and pooled SE
    ATT_pool = J(1, L_plus_1, .)
    SE_pool  = J(1, L_plus_1, .)
    N_valid  = J(1, L_plus_1, .)
    
    for (l=1; l<=L_plus_1; l++) {
        valid_idx = selectindex(!rowmissing(W[., l]))
        n_v = length(valid_idx)
        N_valid[1, l] = n_v
        
        if (n_v == 0) {
            ATT_pool[1, l] = .
            SE_pool[1, l] = .
        }
        else if (n_v == 1) {
            ATT_pool[1, l] = ATT[valid_idx[1], l]
            SE_pool[1, l]  = SE[valid_idx[1], l]
        }
        else {
            w_l   = W[valid_idx, l]
            att_l = ATT[valid_idx, l]
            ATT_pool[1, l] = sum(w_l :* att_l) / sum(w_l)
            SE_pool[1, l]  = sqrt(1 / sum(w_l))
        }
    }
    
    // T10: Confidence intervals
    alpha = (100 - level) / 100
    z_crit = invnormal(1 - alpha/2)
    
    CI_lo = ATT_pool :- z_crit :* SE_pool
    CI_hi = ATT_pool :+ z_crit :* SE_pool
    
    // T12: Set column names
    string rowvector colnames
    colnames = J(1, L_plus_1, "")
    for (l=1; l<=L_plus_1; l++) {
        colnames[l] = "ATT" + strofreal(l - 1)
    }
    
    // Store to Stata matrices
    st_matrix(st_local("ATT_pool"), ATT_pool)
    st_matrixcolstripe(st_local("ATT_pool"), (J(L_plus_1, 1, ""), colnames'))
    
    st_matrix(st_local("SE_pool"), SE_pool)
    st_matrixcolstripe(st_local("SE_pool"), (J(L_plus_1, 1, ""), colnames'))
    
    st_matrix(st_local("CI_lo"), CI_lo)
    st_matrixcolstripe(st_local("CI_lo"), (J(L_plus_1, 1, ""), colnames'))
    
    st_matrix(st_local("CI_hi"), CI_hi)
    st_matrixcolstripe(st_local("CI_hi"), (J(L_plus_1, 1, ""), colnames'))
    
    st_matrix(st_local("IVW_W"), W)
    st_matrix(st_local("N_valid"), N_valid)
}
end
