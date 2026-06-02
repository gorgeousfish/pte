*! _pte_nonabs_sample.ado

version 14.0
capture program drop _pte_nonabs_sample
program define _pte_nonabs_sample, rclass sortpreserve
    version 14.0

    syntax, TREATment(varname numeric) ID(varname) Time(varname numeric) ///
        ATTperiods(integer) [PERSISTperiods(integer 0) REPLACE noREPORT]

    if `attperiods' < 0 {
        di as error "[pte] attperiods() must be non-negative"
        exit 198
    }
    if `persistperiods' < 0 {
        di as error "[pte] persistperiods() must be non-negative"
        exit 198
    }

    if "`replace'" != "" {
        foreach var in att_plus_sample att_minus_sample {
            capture confirm variable `var'
            if !_rc {
                drop `var'
            }
        }
    }
    else {
        foreach var in att_plus_sample att_minus_sample {
            capture confirm new variable `var'
            if _rc {
                di as error "[pte] variable `var' already exists"
                di as error "use {bf:replace} option to overwrite, or {bf:drop `var'} first"
                exit 110
            }
        }
    }

    local switch_opts ""
    if "`replace'" != "" {
        local switch_opts "`switch_opts' replace"
    }
    if "`report'" != "" {
        local switch_opts "`switch_opts' noreport"
    }

    quietly _pte_switch_indicator, treatment(`treatment') id(`id') time(`time') `switch_opts'
    quietly xtset
    local xt_panelvar = r(panelvar)
    local xt_timevar = r(timevar)
    if "`xt_panelvar'" != "`id'" | "`xt_timevar'" != "`time'" {
        di as error "[pte] current xtset must match id() and time()"
        di as error "  xtset: `xt_panelvar' `xt_timevar'"
        di as error "  args : `id' `time'"
        exit 459
    }
    local panel_delta = r(tdelta)

    sort `id' `time'

    tempvar _pte_entry_keep _pte_exit_keep
    gen byte `_pte_entry_keep' = (G == 1)
    gen byte `_pte_exit_keep' = (G == -1)
    // Appendix C.3 studies ATT_{g,l}^{+/-} only for firms that switch at g
    // and keep the new treatment status through g+l. Enforce the same
    // consecutive-observation law at sample-construction time so unstable
    // switches never open ATT windows.
    if `persistperiods' > 1 {
        forvalues h = 1/`=`persistperiods' - 1' {
            by `id' (`time'): replace `_pte_entry_keep' = 0 if ///
                `_pte_entry_keep' == 1 & ///
                (_n + `h' > _N | ///
                 `time'[_n + `h'] != `time' + `h' * `panel_delta' | ///
                 `treatment'[_n + `h'] != 1)
            by `id' (`time'): replace `_pte_exit_keep' = 0 if ///
                `_pte_exit_keep' == 1 & ///
                (_n + `h' > _N | ///
                 `time'[_n + `h'] != `time' + `h' * `panel_delta' | ///
                 `treatment'[_n + `h'] != 0)
        }
    }

    replace nt_plus = .
    replace nt_minus = .

    gen byte att_plus_sample = 0
    gen byte att_minus_sample = 0

    by `id' (`time'): replace nt_plus = -1 if _n < _N ///
        & G[_n+1] == 1 ///
        & `_pte_entry_keep'[_n+1] == 1 ///
        & `time'[_n+1] == `time' + `panel_delta' ///
        & `treatment' == 0
    by `id' (`time'): replace att_plus_sample = 1 if nt_plus == -1

    replace nt_plus = 0 if G == 1 & `_pte_entry_keep' == 1 & `treatment' == 1
    replace att_plus_sample = 1 if nt_plus == 0

    forvalues h = 1/`attperiods' {
        by `id' (`time'): replace nt_plus = `h' if _n > 1 ///
            & missing(nt_plus) ///
            & `treatment' == 1 ///
            & `time' == `time'[_n-1] + `panel_delta' ///
            & nt_plus[_n-1] == `=`h' - 1' ///
            & att_plus_sample[_n-1] == 1
        replace att_plus_sample = 1 if nt_plus == `h'
    }

    by `id' (`time'): replace nt_minus = -1 if _n < _N ///
        & G[_n+1] == -1 ///
        & `_pte_exit_keep'[_n+1] == 1 ///
        & `time'[_n+1] == `time' + `panel_delta' ///
        & `treatment' == 1
    by `id' (`time'): replace att_minus_sample = 1 if nt_minus == -1

    replace nt_minus = 0 if G == -1 & `_pte_exit_keep' == 1 & `treatment' == 0
    replace att_minus_sample = 1 if nt_minus == 0

    forvalues h = 1/`attperiods' {
        by `id' (`time'): replace nt_minus = `h' if _n > 1 ///
            & missing(nt_minus) ///
            & `treatment' == 0 ///
            & `time' == `time'[_n-1] + `panel_delta' ///
            & nt_minus[_n-1] == `=`h' - 1' ///
            & att_minus_sample[_n-1] == 1
        replace att_minus_sample = 1 if nt_minus == `h'
    }

    quietly count if att_plus_sample == 1
    local n_att_plus_sample = r(N)
    return scalar n_att_plus_sample = `n_att_plus_sample'

    quietly count if att_minus_sample == 1
    local n_att_minus_sample = r(N)
    return scalar n_att_minus_sample = `n_att_minus_sample'

    quietly count if nt_plus == -1
    local n_att_plus_lag = r(N)
    return scalar n_att_plus_lag = `n_att_plus_lag'

    quietly count if nt_minus == -1
    local n_att_minus_lag = r(N)
    return scalar n_att_minus_lag = `n_att_minus_lag'

    return scalar attperiods = `attperiods'
    return scalar persistperiods = `persistperiods'

    if "`report'" == "" {
        di as txt ""
        di as txt "{hline 70}"
        di as txt "Non-absorbing ATT sample preparation"
        di as txt "{hline 70}"
        di as txt _col(3) "ATT+ sample observations:" _col(40) as result %10.0fc `n_att_plus_sample'
        di as txt _col(3) "ATT- sample observations:" _col(40) as result %10.0fc `n_att_minus_sample'
        di as txt _col(3) "ATT+ lag rows (nt_plus=-1):" _col(40) as result %10.0fc `n_att_plus_lag'
        di as txt _col(3) "ATT- lag rows (nt_minus=-1):" _col(40) as result %10.0fc `n_att_minus_lag'
        di as txt _col(3) "Persistence requirement:" _col(40) as result %10.0fc `persistperiods'
        di as txt "{hline 70}"
    }
end
