*! _pte_assert_setup_current_law.ado
*! Fail closed when a stored setup contract no longer certifies the current data.

version 14.0
capture program drop _pte_assert_setup_current_law
program define _pte_assert_setup_current_law, rclass sortpreserve
    version 14.0

    syntax , PANELVAR(name) TIMEVAR(name) TREATment(name) TREATSIG(string) ///
        [CONTEXT(string)]

    local context = strtrim(`"`context'"')
    if `"`context'"' == "" {
        local context "post-setup consumer"
    }

    capture confirm variable `panelvar', exact
    if _rc != 0 {
        di as error "`context': stored setup panel variable `panelvar' not found in data"
        di as error "Re-run pte_setup on the current dataset before `context'"
        exit 111
    }
    capture confirm variable `timevar', exact
    if _rc != 0 {
        di as error "`context': stored setup time variable `timevar' not found in data"
        di as error "Re-run pte_setup on the current dataset before `context'"
        exit 111
    }
    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "`context': stored setup treatment variable `treatment' not found in data"
        di as error "Re-run pte_setup on the current dataset before `context'"
        exit 111
    }

    capture quietly _pte_treatment_signature, ///
        panelvar(`panelvar') timevar(`timevar') treatment(`treatment')
    local current_sig_rc = _rc
    local current_sig ""
    if `current_sig_rc' == 0 {
        local current_sig `"`r(signature)'"'
    }

    if `current_sig_rc' != 0 | `"`current_sig'"' == "" {
        di as error "`context': unable to certify the current treatment path against the stored pte_setup contract"
        if `current_sig_rc' != 0 {
            di as error "  _pte_treatment_signature returned rc=`current_sig_rc'"
        }
        di as error "Re-run pte_setup on the current dataset before `context'"
        exit 459
    }

    if `"`current_sig'"' != `"`treatsig'"' {
        di as error "`context': stored pte_setup treatment law no longer matches the current data"
        di as error "Re-run pte_setup on the current dataset before `context'"
        exit 459
    }

    return local signature `"`current_sig'"'
    return local panelvar "`panelvar'"
    return local timevar "`timevar'"
    return local treatment "`treatment'"
end
