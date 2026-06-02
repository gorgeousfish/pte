*! _pte_detect_treatment_type.ado
*! Classify the observed treatment path as absorbing or non-absorbing.
*! The classifier works on realized treatment transitions only. A row enters
*! the transition sample when both the current treatment and its true lagged
*! value are observed within the same panel and adjacent in calendar time.
*! Rows after panel gaps are excluded because D_{t-1} is not defined there.
*! Returns (rclass):
*! r(trt_type)          absorbing or non-absorbing
*! r(N_entry)           count of 0 -> 1 transitions
*! r(N_exit)            count of 1 -> 0 transitions
*! r(N_stay)            count of transitions with no status change
*! r(N_stay_untreated)  subset of stay rows with D_t = 0
*! r(N_stay_treated)    subset of stay rows with D_t = 1
*! r(n_missing)         excluded rows with missing treatment
*! r(n_firms)           firms in the marked sample
*! r(N_periods)         average marked rows per firm
*! r(N_valid)           rows with a valid t-1 treatment state

version 14.0
capture program drop _pte_detect_treatment_type
program define _pte_detect_treatment_type, rclass
    version 14.0
    
    // touse() lets downstream callers inherit an already-filtered sample
    // without mutating the source mark variable.
    syntax varname(numeric), id(varname) time(varname) [TOUSE(varname numeric) NOWarn]
    
    local treatment "`varlist'"
    tempvar _pte_touse
    if "`touse'" == "" {
        qui gen byte `_pte_touse' = 1
    }
    else {
        qui gen byte `_pte_touse' = (`touse' != 0 & !missing(`touse'))
    }
    
    // The detector allows degenerate all-0 or all-1 panels, but any realized
    // value outside {0,1} would break the entry/exit accounting below.
    qui count if `_pte_touse' & !missing(`treatment')
    if r(N) > 0 {
        qui summ `treatment' if `_pte_touse' & !missing(`treatment'), meanonly
        if r(min) < 0 | r(max) > 1 {
            di as error "[pte] Treatment variable must take values 0 or 1 only"
            di as error "[pte] Found range [" r(min) ", " r(max) "]"
            exit 459
        }
        
        qui tab `treatment' if `_pte_touse' & !missing(`treatment')
        if r(r) > 2 {
            di as error "[pte] Treatment variable must be binary (0 or 1)"
            di as error "[pte] Found " r(r) " distinct values"
            exit 459
        }
    }
    
    // Missing treatment rows are tracked separately so the diagnostic output
    // can explain why the usable transition count is smaller than the marked
    // sample size.
    qui count if `_pte_touse' & missing(`treatment')
    local n_missing = r(N)
    
    if `n_missing' > 0 & "`nowarn'" == "" {
        di as text "[pte] Warning: `n_missing' observations with" ///
            " missing treatment excluded"
    }
    
    // Confirm id/time explicitly because this helper is also used outside a
    // fully initialized pte estimation context.
    capture confirm variable `id'
    if _rc != 0 {
        di as error "[pte] Panel id variable `id' does not exist"
        exit 111
    }
    
    capture confirm variable `time'
    if _rc != 0 {
        di as error "[pte] Panel time variable `time' does not exist"
        exit 111
    }
    
    // Transition detection relies on adjacent within-firm rows. If the marked
    // sample is not uniquely sorted, sort in place and optionally tell the
    // caller that the original order was not a panel order.
    capture isid `id' `time' if `_pte_touse', sort
    if _rc != 0 {
        if "`nowarn'" == "" {
            di as text "[pte] Note: Data not uniquely sorted, sorting now"
        }
        sort `id' `time'
    }
    
    // Respect the true t-1 timing: rows after panel gaps do not have a
    // defined lagged treatment status and must not count as transitions.
    // When xtset matches id()/time(), reuse its delta; otherwise fall back
    // to a unit-step clock for standalone diagnostics.
    tempvar D_lag valid_sample gap_probe
    local _pte_dt = 1
    capture _xt, trequired
    if _rc == 0 {
        if "`r(ivar)'" == "`id'" & "`r(tvar)'" == "`time'" {
            local _pte_dt_try = real("`r(tdelta)'")
            if !missing(`_pte_dt_try') & abs(`_pte_dt_try') > 0 {
                local _pte_dt = abs(`_pte_dt_try')
            }
        }
    }
    local _pte_dt_tol = max(1e-10, abs(`_pte_dt') * 1e-10)

    qui bys `id' (`time'): gen double `gap_probe' = `time' - `time'[_n-1] ///
        if `_pte_touse' & _n > 1 & `_pte_touse'[_n-1] ///
        & !missing(`time', `time'[_n-1])
    qui bys `id' (`time'): gen double `D_lag' = `treatment'[_n-1] if _n > 1 ///
        & `_pte_touse' & `_pte_touse'[_n-1] ///
        & !missing(`treatment'[_n-1]) ///
        & abs(`gap_probe' - `_pte_dt') <= `_pte_dt_tol'
    qui gen byte `valid_sample' = `_pte_touse' & !missing(`D_lag') & !missing(`treatment')
    
    // Exit events certify that the realized treatment path is non-absorbing.
    tempvar exit_event
    qui gen byte `exit_event' = (`D_lag' == 1 & `treatment' == 0) ///
        if `valid_sample'
    qui count if `exit_event' == 1
    local N_exit = r(N)
    
    // Entry events matter for diagnostics even when the overall path remains
    // absorbing because they reveal when treatment first turns on.
    tempvar entry_event
    qui gen byte `entry_event' = (`D_lag' == 0 & `treatment' == 1) ///
        if `valid_sample'
    qui count if `entry_event' == 1
    local N_entry = r(N)
    
    // Stay counts partition valid transitions into untreated and treated
    // continuation paths, which is useful when checking support for Appendix C
    // style non-absorbing designs.
    tempvar stay_event
    qui gen byte `stay_event' = (`treatment' == `D_lag') if `valid_sample'
    
    qui count if `stay_event' == 1
    local N_stay = r(N)
    
    qui count if `stay_event' == 1 & `treatment' == 0
    local N_stay_untreated = r(N)
    
    qui count if `stay_event' == 1 & `treatment' == 1
    local N_stay_treated = r(N)
    
    // Every valid transition must be exactly one of entry, exit, or stay.
    // Failing this identity means the transition classifier is internally
    // inconsistent and its absorbing/non-absorbing verdict is unusable.
    qui count if `valid_sample'
    local N_valid = r(N)
    
    local check_sum = `N_entry' + `N_exit' + `N_stay'
    if `check_sum' != `N_valid' {
        di as error "[pte] Internal error: Event counts do not sum to" ///
            " valid observations"
        di as error "[pte] N_entry(`N_entry') + N_exit(`N_exit') +" ///
            " N_stay(`N_stay') = `check_sum' != N_valid(`N_valid')"
        exit 198
    }
    
    // Absorbing means the sample never records a realized 1 -> 0 exit. The
    // rule is intentionally descriptive: it classifies the observed panel and
    // does not prove that the underlying economic treatment is inherently
    // absorbing outside the sample window.
    if `N_exit' == 0 {
        local trt_type "absorbing"
    }
    else {
        local trt_type "non-absorbing"
    }
    
    // These summary counts describe the marked sample after touse() and
    // missing-treatment screening, not the full dataset on disk.
    qui tab `id' if `_pte_touse'
    local N_firms = r(r)
    qui count if `_pte_touse'
    local N_periods_avg = .
    if `N_firms' > 0 {
        local N_periods_avg = r(N) / `N_firms'
    }
    
    // The display is a diagnostic contract only; downstream logic should read
    // r() rather than scrape printed text.
    if "`nowarn'" == "" {
        di as text "{hline 60}"
        di as text "PTE Treatment Type Detection"
        di as text "{hline 60}"
        
        if "`trt_type'" == "absorbing" {
            di as text "Treatment type:    " as result "Absorbing"
            di as text "  (Once treated, firms remain treated)"
        }
        else {
            di as text "Treatment type:    " as result "Non-absorbing"
            di as text "  (Firms can exit treatment)"
        }
        
        di as text "{hline 60}"
        di as text "Panel structure:"
        di as text "  Firms:           " as result %9.0f `N_firms'
        di as text "  Avg periods:     " as result %9.1f `N_periods_avg'
        di as text "  Valid transitions:" as result %8.0f `N_valid'
        di as text "  Missing:         " as result %9.0f `n_missing'
        
        di as text "{hline 60}"
        di as text "Transition events:"
        di as text "  Entry (0->1):    " as result %9.0f `N_entry'
        di as text "  Exit  (1->0):    " as result %9.0f `N_exit'
        di as text "  Stay  (no chg):  " as result %9.0f `N_stay'
        di as text "    Stay untreated:" as result %9.0f `N_stay_untreated'
        di as text "    Stay treated:  " as result %9.0f `N_stay_treated'
        di as text "{hline 60}"
    }
    
    // Publish the complete transition accounting so later non-absorbing
    // helpers can branch without recomputing the event table.
    return local  trt_type "`trt_type'"
    return scalar N_entry = `N_entry'
    return scalar N_exit = `N_exit'
    return scalar N_stay = `N_stay'
    return scalar N_stay_untreated = `N_stay_untreated'
    return scalar N_stay_treated = `N_stay_treated'
    return scalar n_missing = `n_missing'
    return scalar n_firms = `N_firms'
    return scalar N_periods = `N_periods_avg'
    return scalar N_valid = `N_valid'
end
