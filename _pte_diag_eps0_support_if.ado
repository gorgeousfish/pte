*! _pte_diag_eps0_support_if.ado
*! Resolve the default eps0 support contract for diagnostic consumers.

version 14.0
capture program drop _pte_diag_eps0_support_if
program define _pte_diag_eps0_support_if, rclass
    version 14.0

    syntax , EPSVAR(name) [CONTEXT(string)]

    local context = strtrim(`"`context'"')
    if `"`context'"' == "" {
        local context "eps0 diagnostics"
    }

    local sample_if "!missing(`epsvar')"
    local uses_support = 0

    // The exact untreated-innovation support is observable only on the
    // package-owned default eps0 object. User-supplied eps0() overrides are
    // treated as standalone diagnostic inputs because no public support
    // indicator is defined for arbitrary variables.
    if `"`epsvar'"' == "_pte_eps0" {
        local setup_panel : char _dta[_pte_setup_panelvar]
        local setup_time : char _dta[_pte_setup_timevar]
        local setup_treatment : char _dta[_pte_setup_treatment]
        local setup_treatsig : char _dta[_pte_setup_treatsig]
        local setup_xtdelta : char _dta[_pte_setup_xtdelta]
        local have_setup_fragment = ///
            (`"`setup_panel'"' != "") | ///
            (`"`setup_time'"' != "") | ///
            (`"`setup_treatment'"' != "") | ///
            (`"`setup_treatsig'"' != "") | ///
            (`"`setup_xtdelta'"' != "")
        local have_complete_setup_contract = ///
            (`"`setup_panel'"' != "") & ///
            (`"`setup_time'"' != "") & ///
            (`"`setup_treatment'"' != "") & ///
            (`"`setup_treatsig'"' != "") & ///
            (`"`setup_xtdelta'"' != "")

        local live_id ""
        local live_time ""
        local live_treatsig ""
        local live_predict ""
        local live_treatment ""
        local live_xtdelta ""
        if "`e(cmd)'" == "pte" {
            capture local live_id = e(idvar)
            if _rc != 0 | inlist(`"`live_id'"', "", ".") {
                capture local live_id = e(id)
            }
            if `"`live_id'"' == "." {
                local live_id ""
            }
            capture local live_time = e(timevar)
            if _rc != 0 | inlist(`"`live_time'"', "", ".") {
                capture local live_time = e(time)
            }
            if `"`live_time'"' == "." {
                local live_time ""
            }
            capture local live_treatsig = e(treatsig)
            if _rc != 0 | `"`live_treatsig'"' == "." {
                local live_treatsig ""
            }
            capture local live_predict = e(predict)
            if _rc != 0 | `"`live_predict'"' == "." {
                local live_predict ""
            }
            capture local live_treatment = e(treatment)
            if _rc != 0 | `"`live_treatment'"' == "." {
                local live_treatment ""
            }
            tempname _pte_eps0_support_xtdelta
            capture scalar `_pte_eps0_support_xtdelta' = e(xtdelta)
            if _rc == 0 & !missing(`_pte_eps0_support_xtdelta') {
                local live_xtdelta = strofreal(`_pte_eps0_support_xtdelta')
            }
        }

        local have_complete_live_contract = ///
            (`"`live_id'"' != "") & ///
            (`"`live_time'"' != "") & ///
            (`"`live_treatment'"' != "") & ///
            (`"`live_treatsig'"' != "") & ///
            (`"`live_xtdelta'"' != "")
        local have_certified_live_pte = (`have_complete_live_contract')
        local have_live_current_law_claim = ///
            (`"`live_id'"' != "") | ///
            (`"`live_time'"' != "") | ///
            (`"`live_treatsig'"' != "") | ///
            (`"`live_predict'"' != "") | ///
            (`"`live_xtdelta'"' != "")

        local have_default_eps0_state_marker = 0
        foreach _pte_eps0_marker in _pte_active_sample _pte_eps0_trim {
            capture confirm variable `_pte_eps0_marker', exact
            if _rc == 0 {
                local have_default_eps0_state_marker = 1
                continue, break
            }
        }

        capture confirm variable _pte_eps0_ind, exact
        local have_support_indicator = (_rc == 0)

        if (`have_setup_fragment' | `have_live_current_law_claim') & ///
            (`have_default_eps0_state_marker' | `have_support_indicator') {
            // The package-owned default eps0 object is meaningful only under
            // the treatment law that produced its support indicator or helper
            // state. Reuse the shared setup/live panel resolver here so the
            // qq-only path cannot diverge from the grouped CDF path on
            // setup/live conflicts, incomplete setup fragments, or bridged
            // setup-backed xtdelta certification.
            capture noisily _pte_diag_panel_contract, ///
                context("`context'") allowsetupmissingxtdelta
            local _pte_eps0_panel_contract_rc = _rc
            if `_pte_eps0_panel_contract_rc' != 0 {
                exit `_pte_eps0_panel_contract_rc'
            }
        }

        if `have_support_indicator' {
            capture confirm numeric variable _pte_eps0_ind
            if _rc != 0 {
                di as error "`context': _pte_eps0_ind must be numeric"
                exit 111
            }
            capture assert inlist(_pte_eps0_ind, 0, 1) if !missing(_pte_eps0_ind)
            if _rc != 0 {
                di as error "`context': _pte_eps0_ind must be binary (0/1)"
                di as error "`context': the exact untreated innovation support must not be inferred from stale nonmissing _pte_eps0 values"
                exit 459
            }
            local sample_if "_pte_eps0_ind == 1 & !missing(`epsvar')"
            local uses_support = 1
        }
        else if (`have_complete_setup_contract' | `have_certified_live_pte') & ///
            `have_default_eps0_state_marker' {
            di as error "`context': default _pte_eps0 requires the exact untreated-innovation support indicator _pte_eps0_ind"
            di as error "`context': re-run pte/pte_setup on the current dataset or keep _pte_eps0_ind alongside _pte_eps0"
            exit 111
        }
    }

    return local sample_if "`sample_if'"
    return scalar uses_support = `uses_support'
end
