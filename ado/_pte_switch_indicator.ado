*! _pte_switch_indicator.ado
*! Generates the switching indicator G ∈ {-1, 0, +1} and related
*! variables for non-absorbing treatment analysis.
*! Theory (Appendix C.3, Equation C.3):
*! G_it = sign(D_it - D_{it-1})
*! G = +1: entry into treatment (D_{t-1}=0, D_t=1)
*! G = -1: exit from treatment  (D_{t-1}=1, D_t=0)
*! G =  0: status unchanged     (D_t = D_{t-1}) or first period
*! Output variables:
*! G              - switching indicator {-1, 0, +1}
*! _last_entry_yr - most recent entry year (forward-filled)
*! _last_exit_yr  - most recent exit year (forward-filled)
*! nt_plus        - relative time since entry (for ATT+)
*! nt_minus       - relative time since exit (for ATT-)
*! n_switch       - cumulative number of switches per firm

version 14.0
capture program drop _pte_switch_indicator
program define _pte_switch_indicator, rclass sortpreserve
    version 14.0
    
    // Parse raw names first so the command can enforce exact-name contracts
    // before Stata expands unique abbreviations onto shadow variables.
    syntax, TREATment(name) ID(name) Time(name) ///
        [REPLACE noREPORT]
    
    // ================================================================
    // Step 0: Input validation
    // ================================================================
    
    // 0.1 Check panel structure (xtset required)
    capture _xt, trequired
    if _rc {
        di as error "[pte] data not xtset"
        di as error "use {bf:xtset} {it:panelvar timevar} before calling _pte_switch_indicator"
        exit 459
    }
    quietly xtset
    local _xt_panelvar "`r(panelvar)'"
    local _xt_timevar "`r(timevar)'"
    if "`_xt_panelvar'" != "`id'" | "`_xt_timevar'" != "`time'" {
        di as error "[pte] xtset must match id() and time()"
        di as error "  current xtset: `r(panelvar)' `r(timevar)'"
        di as error "  requested:     `id' `time'"
        di as error "  run {bf:xtset `id' `time'} before calling _pte_switch_indicator"
        exit 459
    }
    
    // 0.2 Check panel/treatment variables exist exactly
    capture confirm variable `id', exact
    if _rc {
        di as error "[pte] variable `id' not found"
        exit 111
    }

    capture confirm variable `time', exact
    if _rc {
        di as error "[pte] variable `time' not found"
        exit 111
    }

    capture confirm numeric variable `time'
    if _rc {
        di as error "[pte] variable `time' must be numeric"
        exit 111
    }

    capture confirm variable `treatment', exact
    if _rc {
        di as error "[pte] variable `treatment' not found"
        exit 111
    }

    capture confirm numeric variable `treatment'
    if _rc {
        di as error "[pte] variable `treatment' must be numeric"
        exit 111
    }
    
    // 0.3 Check treatment is binary (0/1) on observed rows.
    // Appendix C.3 defines G_it locally from the current and true adjacent
    // observed treatment states. Missing treatment rows therefore create
    // undefined local switch states rather than a dataset-wide fatal error.
    qui count if !missing(`treatment') & !inlist(`treatment', 0, 1)
    if r(N) > 0 {
        di as error "[pte] treatment variable must be binary (0/1)"
        di as error "  found `=r(N)' non-binary observations in `treatment'"
        exit 450
    }
    
    // 0.4 Handle variable conflicts
    if "`replace'" != "" {
        foreach var in G _last_entry_yr _last_exit_yr nt_plus nt_minus n_switch {
            capture confirm variable `var'
            if !_rc {
                di as txt "[pte] (replacing existing `var' variable)"
                drop `var'
            }
        }
    }
    else {
        foreach var in G _last_entry_yr _last_exit_yr nt_plus nt_minus n_switch {
            capture confirm new variable `var'
            if _rc {
                di as error "[pte] variable `var' already exists"
                di as error "use {bf:replace} option to overwrite, or {bf:drop `var'} first"
                exit 110
            }
        }
    }
    
    // ================================================================
    // Step 1: Generate switching indicator G
    // Eq.(C.3): G_it = sign(D_it - D_{it-1})
    //   G = +1: entry (D_{t-1}=0, D_t=1)
    //   G = -1: exit  (D_{t-1}=1, D_t=0)
    //   G =  0: stay  (D_t = D_{t-1}) or first period
    // ================================================================
    
    sort `id' `time'
    
    tempvar _pte_treat_lag _pte_switch_defined _pte_first_obs
    gen double `_pte_treat_lag' = L.`treatment'
    by `id' (`time'): gen byte `_pte_switch_defined' = !mi(`treatment', `_pte_treat_lag')
    by `id' (`time'): gen byte `_pte_first_obs' = (_n == 1 & !mi(`treatment'))

    // Gap observations with undefined D_{t-1} remain missing: Appendix C.3
    // defines G_it using the true adjacent period, not the previous row.
    gen byte G = sign(`treatment' - `_pte_treat_lag') if `_pte_switch_defined'
    replace G = 0 if `_pte_first_obs'
    
    label variable G "Switch indicator: +1=entry, -1=exit, 0=stay"
    
    // ================================================================
    // Step 2: Compute most recent entry year (_last_entry_yr)
    // Forward-fill algorithm: mark -> fill -> override on new event
    // Math: _last_entry_yr_it = max{s : s <= t, G_is = 1}
    // ================================================================
    
    gen double _last_entry_yr = `time' if G == 1

    // Continue the entry history only along an observed treated path.
    // Missing treatment rows or undefined switch states break the ATT+
    // persistence spell and must not be bridged by forward fill.
    by `id' (`time'): replace _last_entry_yr = _last_entry_yr[_n-1] ///
        if missing(_last_entry_yr) & _n > 1 & G == 0 & `treatment' == 1
    
    label variable _last_entry_yr "Most recent entry year (for ATT+)"
    
    // ================================================================
    // Step 3: Compute most recent exit year (_last_exit_yr)
    // Symmetric to Step 2
    // Math: _last_exit_yr_it = max{s : s <= t, G_is = -1}
    // ================================================================
    
    gen double _last_exit_yr = `time' if G == -1

    // Continue the exit history only along an observed untreated path.
    // Missing treatment rows or undefined switch states break the ATT-
    // persistence spell and must not be bridged by forward fill.
    by `id' (`time'): replace _last_exit_yr = _last_exit_yr[_n-1] ///
        if missing(_last_exit_yr) & _n > 1 & G == 0 & `treatment' == 0
    
    label variable _last_exit_yr "Most recent exit year (for ATT-)"
    
    // ================================================================
    // Step 4: Compute relative entry time (nt_plus)
    // nt_plus = t - _last_entry_yr, only for D=1 observations
    // Used for ATT+ dynamic effect estimation (ell-period effect)
    // ================================================================
    
    gen double nt_plus = `time' - _last_entry_yr ///
        if `treatment' == 1 & !missing(_last_entry_yr)
    
    label variable nt_plus "Relative time since entry (for ATT+)"
    
    // ================================================================
    // Step 5: Compute relative exit time (nt_minus)
    // nt_minus = t - _last_exit_yr, only for D=0 observations
    // Used for ATT- dynamic effect estimation (ell-period effect)
    // ================================================================
    
    gen double nt_minus = `time' - _last_exit_yr ///
        if `treatment' == 0 & !missing(_last_exit_yr)
    
    label variable nt_minus "Relative time since exit (for ATT-)"
    
    // ================================================================
    // Step 6: Cumulative switch count (n_switch)
    // Counts total number of switches (entries + exits) per firm
    // ================================================================
    
    by `id' (`time'): gen int n_switch = sum(!mi(G) & G != 0)
    
    label variable n_switch "Cumulative number of switches"
    
    // ================================================================
    // Step 7: Statistical report
    // Compute and display switching statistics
    // ================================================================
    
    // Event counts
    qui count if G == 1
    local n_entry = r(N)
    qui count if G == -1
    local n_exit = r(N)
    qui count if G == 0
    local n_stay = r(N)
    
    // Firm-level statistics: firms with entry events
    tempvar ever_entry ever_exit firm_max_switch
    by `id' (`time'): egen byte `ever_entry' = max(G == 1)
    by `id' (`time'): egen byte `ever_exit' = max(G == -1)
    by `id' (`time'): egen int `firm_max_switch' = max(n_switch)
    
    // Count distinct firms with entry events
    local n_firms_entry = 0
    qui tab `id' if `ever_entry' == 1, nofreq
    if r(N) > 0 {
        local n_firms_entry = r(r)
    }
    
    // Count distinct firms with exit events
    local n_firms_exit = 0
    qui tab `id' if `ever_exit' == 1, nofreq
    if r(N) > 0 {
        local n_firms_exit = r(r)
    }
    
    // Multi-switch statistics
    local n_multi_switch_firms = 0
    qui count if `firm_max_switch' > 1
    if r(N) > 0 {
        qui tab `id' if `firm_max_switch' > 1, nofreq
        local n_multi_switch_firms = r(r)
    }
    
    // Maximum switches per firm
    qui summ `firm_max_switch'
    local max_switches = r(max)
    
    // Consecutive switch detection
    // Paper Lines 881-883: high-frequency switching warning
    tempvar consecutive_switch
    by `id' (`time'): gen byte `consecutive_switch' = ///
        (!mi(G, G[_n-1]) & G != 0 & G[_n-1] != 0 & _n > 1)
    qui count if `consecutive_switch' == 1
    local n_consecutive = r(N)
    
    // ================================================================
    // Step 8: Display report (unless noreport)
    // ================================================================
    
    if "`report'" == "" {
        di as txt ""
        di as txt "{hline 70}"
        di as txt "Switch Indicator Generation"
        di as txt "{hline 70}"
        di as txt _col(3) "Switch events:"
        di as txt _col(5) "Entry events (G=+1):" ///
            _col(45) as result %10.0fc `n_entry'
        di as txt _col(5) "Exit events (G=-1):" ///
            _col(45) as result %10.0fc `n_exit'
        di as txt _col(5) "Stay observations (G=0):" ///
            _col(45) as result %10.0fc `n_stay'
        di as txt ""
        di as txt _col(3) "Firm-level statistics:"
        di as txt _col(5) "Firms with entry events:" ///
            _col(45) as result %10.0fc `n_firms_entry'
        di as txt _col(5) "Firms with exit events:" ///
            _col(45) as result %10.0fc `n_firms_exit'
        di as txt _col(5) "Firms with >1 switch:" ///
            _col(45) as result %10.0fc `n_multi_switch_firms'
        di as txt _col(5) "Maximum switches per firm:" ///
            _col(45) as result %10.0fc `max_switches'
        di as txt "{hline 70}"
        di as txt ""
    }
    
    // ================================================================
    // Step 9: Multi-switch warning
    // Paper Lines 881-883: matching cohort difficulty warning
    // ================================================================
    
    if `n_multi_switch_firms' > 0 & "`report'" == "" {
        di as txt "[pte] Warning: `n_multi_switch_firms' firms have multiple switches"
        di as txt "  Per Chen, Liao & Schurter (2026) Appendix C.3 (Lines 881-883):"
        di as txt "  'The g'-matching cohort is very hard to find'"
        di as txt "  ATT estimates may be less reliable"
        di as txt "  Consider: (1) restricting to first switch only, or"
        di as txt "            (2) increasing persistperiods option"
        di as txt ""
    }
    
    // Consecutive switch warning
    if `n_consecutive' > 0 & "`report'" == "" {
        di as error "[pte] Warning: `n_consecutive' observations with consecutive switches"
        di as error "  High-frequency switching may violate Assumption C.2"
        di as error ""
    }
    
    // ================================================================
    // Step 10: Store return values (r-class)
    // ================================================================
    
    return scalar n_entry = `n_entry'
    return scalar n_exit = `n_exit'
    return scalar n_stay = `n_stay'
    return scalar n_firms_entry = `n_firms_entry'
    return scalar n_firms_exit = `n_firms_exit'
    return scalar n_multi_switch = `n_multi_switch_firms'
    return scalar max_switches = `max_switches'
    return scalar n_consecutive = `n_consecutive'
    
end
