*! _pte_att_failure_cleanup.ado
*! Failure cleanup helper for _pte_att

version 14.0
capture program drop _pte_att_failure_cleanup
program define _pte_att_failure_cleanup
    version 14.0
    syntax [, CLEARECLASS ///
        HASTREATYEAR(integer 0) TREATYEARBACKUP(name) ///
        HASTREATALIAS(integer 0) TREATALIASBACKUP(name) ///
        HASNT(integer 0) NTBACKUP(name)]

    // Restore shared timing objects to their pre-_pte_att state when backups
    // are available. These may be published upstream by pte_setup or
    // _pte_verify_treatment, so failure cleanup must never delete them just
    // because a downstream ATT rerun failed.
    if `hastreatyear' {
        capture confirm variable `treatyearbackup', exact
        if !_rc {
            capture confirm variable _pte_treat_year, exact
            if !_rc {
                capture drop _pte_treat_year
            }
            clonevar _pte_treat_year = `treatyearbackup'
        }
    }
    else {
        capture confirm variable _pte_treat_year, exact
        if !_rc {
            capture drop _pte_treat_year
        }
    }

    if `hastreatalias' {
        capture confirm variable `treataliasbackup', exact
        if !_rc {
            capture confirm variable treat_yr0, exact
            if !_rc {
                capture drop treat_yr0
            }
            clonevar treat_yr0 = `treataliasbackup'
        }
    }
    else {
        capture confirm variable treat_yr0, exact
        if !_rc {
            capture drop treat_yr0
        }
    }

    if `hasnt' {
        capture confirm variable `ntbackup', exact
        if !_rc {
            capture confirm variable _pte_nt, exact
            if !_rc {
                capture drop _pte_nt
            }
            clonevar _pte_nt = `ntbackup'
        }
    }
    else {
        capture confirm variable _pte_nt, exact
        if !_rc {
            capture drop _pte_nt
        }
    }

    // Drop only ATT-owned bridge variables. This includes the event-time
    // outputs beyond the restored timing objects above. Do not touch shared
    // state such as _pte_active_sample or _pte_eps0.
    foreach _v in _pte_omega_0 _pte_omega_0_trim ///
        _pte_tt_raw _pte_tt _pte_tt_trim ///
        _pte_eps0_draw _pte_eps0_trim_draw ///
        _pte_tt_raw_sd _pte_tt_sd _pte_tt_trim_sd {
        capture confirm variable `_v', exact
        if !_rc {
            capture drop `_v'
        }
    }

    if "`cleareclass'" != "" {
        capture ereturn clear
    }
end
