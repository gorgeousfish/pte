*! _pte_nonabsorbing.ado
*! Main orchestrator for non-absorbing treatment analysis.
*! Coordinates the full non-absorbing estimation pipeline:

version 14.0
capture program drop _pte_nonabsorbing
program define _pte_nonabsorbing, eclass
    version 14.0
    
    syntax varlist(min=1), TREATment(name) ///
        ID(name) Time(name) ///
        [PERSISTperiods(integer 0) noREPORT REPLACE]

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
    
    // ================================================================
    // Step 0: Input validation
    // ================================================================
    
    // Check panel structure
    capture _xt, trequired
    if _rc {
        di as error "[pte] data not xtset"
        di as error "use {bf:xtset} {it:panelvar timevar} before calling _pte_nonabsorbing"
        exit 459
    }
    quietly xtset
    if "`r(panelvar)'" != "`id'" | "`r(timevar)'" != "`time'" {
        di as error "[pte] xtset must match id() and time()"
        di as error "  current xtset: `r(panelvar)' `r(timevar)'"
        di as error "  requested:     `id' `time'"
        di as error "  run {bf:xtset `id' `time'} before calling _pte_nonabsorbing"
        exit 459
    }
    
    // Validate persistperiods
    if `persistperiods' < 0 {
        di as error "[pte] persistperiods() must be non-negative"
        exit 198
    }
    
    // ================================================================
    // Step 1: Treatment type detection
    // Call _pte_detect_treatment_type to determine absorbing vs non-absorbing
    // ================================================================
    
    if "`report'" == "" {
        di as txt ""
        di as txt "{hline 70}"
        di as txt "PTE Non-absorbing Treatment Analysis"
        di as txt "{hline 70}"
        di as txt ""
        di as txt "Step 1: Detecting treatment type..."
    }
    
    // Build options for detect command
    local detect_opts ""
    if "`report'" != "" {
        local detect_opts "nowarn"
    }
    
    _pte_detect_treatment_type `treatment', id(`id') time(`time') `detect_opts'
    
    // Capture return values before they are cleared
    local trt_type "`r(trt_type)'"
    local N_entry_detect = r(N_entry)
    local N_exit_detect = r(N_exit)
    local N_stay_detect = r(N_stay)
    local n_firms = r(n_firms)
    local N_valid = r(N_valid)
    
    // ================================================================
    // Step 2: Branch based on treatment type
    // ================================================================
    
    if "`trt_type'" == "absorbing" {
        // Absorbing treatment: no switching indicators needed
        if "`report'" == "" {
            di as txt ""
            di as txt "Treatment type: {res}absorbing"
            di as txt "  No exit events detected. Standard absorbing framework applies."
            di as txt "  Switch indicator generation skipped."
            di as txt "{hline 70}"
        }
        
        // Store results
        ereturn clear
        ereturn local trt_type "absorbing"
        ereturn local cmd "_pte_nonabsorbing"
        ereturn scalar nonabsorbing = 0
        ereturn scalar n_entry = `N_entry_detect'
        ereturn scalar n_exit = 0
        ereturn scalar n_stay = `N_stay_detect'
        ereturn scalar n_firms = `n_firms'
        
        exit 0
    }
    
    // ================================================================
    // Step 2b: Non-absorbing treatment - generate switch indicators
    // Call _pte_switch_indicator
    // ================================================================
    
    if "`report'" == "" {
        di as txt ""
        di as txt "Treatment type: {res}non-absorbing"
        di as txt "  Exit events detected. Proceeding with Appendix C.3 framework."
        di as txt ""
        di as txt "Step 2: Generating switch indicators (G, nt_plus, nt_minus)..."
    }
    
    // Build options for switch indicator command
    local switch_opts ""
    if "`replace'" != "" {
        local switch_opts "`switch_opts' replace"
    }
    if "`report'" != "" {
        local switch_opts "`switch_opts' noreport"
    }
    
    _pte_switch_indicator, treatment(`treatment') id(`id') time(`time') `switch_opts'
    
    // Capture return values
    local n_entry = r(n_entry)
    local n_exit = r(n_exit)
    // Publish stay counts on the same true-lag transition sample used
    // by the detector. _pte_switch_indicator counts first observed rows
    // in G==0, which is not the detector's transition-sample contract.
    local n_stay = `N_stay_detect'
    local n_firms_entry = r(n_firms_entry)
    local n_firms_exit = r(n_firms_exit)
    local n_multi_switch = r(n_multi_switch)
    local max_switches = r(max_switches)
    local n_consecutive = r(n_consecutive)
    
    // ================================================================
    // Step 3: Apply persistperiods filter (if specified)
    // Restrict to firms that persist in treatment for at least
    // persistperiods consecutive periods after a switch
    // ================================================================
    
    if `persistperiods' > 0 {
        if "`report'" == "" {
            di as txt ""
            di as txt "Step 2b: Applying persistperiods(`persistperiods') filter..."
        }

        quietly xtset
        local _pte_panel_delta = r(tdelta)
        tempvar _pte_entry_keep _pte_exit_keep _pte_switch_keep ///
            _pte_switch_keep_cum _pte_firm_switch_keep_max
        qui gen byte `_pte_entry_keep' = (G == 1)
        qui gen byte `_pte_exit_keep' = (G == -1)
        // Appendix C.3 defines ATT_{g,l}^{+/-} on firms that switch at g and
        // stay in the new treatment state through g+l. The preprocessing
        // counts must therefore drop switch events whose new status does not
        // persist for the requested number of consecutive observed periods.
        if `persistperiods' > 1 {
            forvalues h = 1/`=`persistperiods' - 1' {
                qui by `id' (`time'): replace `_pte_entry_keep' = 0 if ///
                    `_pte_entry_keep' == 1 & ///
                    (_n + `h' > _N | ///
                     `time'[_n + `h'] != `time' + `h' * `_pte_panel_delta' | ///
                     `treatment'[_n + `h'] != 1)
                qui by `id' (`time'): replace `_pte_exit_keep' = 0 if ///
                    `_pte_exit_keep' == 1 & ///
                    (_n + `h' > _N | ///
                     `time'[_n + `h'] != `time' + `h' * `_pte_panel_delta' | ///
                     `treatment'[_n + `h'] != 0)
            }
        }

        qui count if `_pte_entry_keep' == 1
        local n_entry = r(N)
        qui count if `_pte_exit_keep' == 1
        local n_exit = r(N)

        local n_firms_entry = 0
        qui tab `id' if `_pte_entry_keep' == 1, nofreq
        if r(N) > 0 {
            local n_firms_entry = r(r)
        }

        local n_firms_exit = 0
        qui tab `id' if `_pte_exit_keep' == 1, nofreq
        if r(N) > 0 {
            local n_firms_exit = r(r)
        }

        qui gen byte `_pte_switch_keep' = (`_pte_entry_keep' == 1 | `_pte_exit_keep' == 1)
        qui by `id' (`time'): gen int `_pte_switch_keep_cum' = sum(`_pte_switch_keep')
        qui by `id' (`time'): egen int `_pte_firm_switch_keep_max' = max(`_pte_switch_keep_cum')

        local n_multi_switch = 0
        qui tab `id' if `_pte_firm_switch_keep_max' > 1, nofreq
        if r(N) > 0 {
            local n_multi_switch = r(r)
        }

        qui summarize `_pte_firm_switch_keep_max', meanonly
        local max_switches = r(max)
        if missing(`max_switches') {
            local max_switches = 0
        }

        if "`report'" == "" {
            di as txt "  Stable entry events kept: " as result %10.0fc `n_entry'
            di as txt "  Stable exit events kept:  " as result %10.0fc `n_exit'
        }
    }
    
    // ================================================================
    // Step 4-6: Downstream modules (placeholders)
    // These will be implemented in future specs:
    // ================================================================
    
    if "`report'" == "" {
        di as txt ""
        di as txt "Step 3-6: Downstream estimation modules (pending implementation)"
        di as txt "  Separate evolution estimation"
        di as txt "  Bidirectional shock distribution"
        di as txt "  ATT+/ATT- estimation"
        di as txt "  Bootstrap inference"
        di as txt ""
        di as txt "{hline 70}"
        di as txt "Non-absorbing preprocessing complete."
        di as txt "  Variables created: G, _last_entry_yr, _last_exit_yr,"
        di as txt "                     nt_plus, nt_minus, n_switch"
        di as txt "{hline 70}"
    }
    
    // ================================================================
    // Store eclass results
    // ================================================================
    
    // ----------------------------------------------------------------
    // When downstream ATT estimation modules (/006/007) are
    // implemented, they will produce ATT_switchin, ATT_switchout, and
    // SE matrices. At that point, replace the basic ereturn block below
    // with a call to _pte_nonabs_ereturn for full result storage.
    //
    // Expected call pattern (activate when ATT matrices are available):
    //   _pte_nonabs_ereturn, ///
    //       attswitchin(ATT_switchin) ///
    //       attswitchinse(ATT_SE_switchin) ///
    //       attswitchout(ATT_switchout) ///
    //       attswitchoutse(ATT_SE_switchout) ///
    //       nswitchin(`n_entry') ///
    //       nswitchout(`n_exit') ///
    //       attperiods(ATT_periods) ///
    //       persistperiods(`persistperiods') ///
    //       sigmaeps0(`sigma_eps0') ///
    //       sigmaeps1(`sigma_eps1') ///
    //       sigmaeps0trim(`sigma_eps0_trim') ///
    //       sigmaeps1trim(`sigma_eps1_trim') ///
    //       cmdline(`"`0'"')
    // ----------------------------------------------------------------
    
    ereturn clear
    ereturn local trt_type "`trt_type'"
    ereturn local cmd "_pte_nonabsorbing"
    ereturn scalar nonabsorbing = 1
    ereturn scalar n_entry = `n_entry'
    ereturn scalar n_exit = `n_exit'
    ereturn scalar n_stay = `n_stay'
    ereturn scalar n_firms = `n_firms'
    ereturn scalar n_firms_entry = `n_firms_entry'
    ereturn scalar n_firms_exit = `n_firms_exit'
    ereturn scalar n_multi_switch = `n_multi_switch'
    ereturn scalar max_switches = `max_switches'
    ereturn scalar n_consecutive = `n_consecutive'
    ereturn scalar persistperiods = `persistperiods'
    
end
