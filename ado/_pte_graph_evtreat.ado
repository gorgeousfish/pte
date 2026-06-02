*! _pte_graph_evtreat.ado
*! Shared evolution-graph ever-treated state contract

version 14.0
program define _pte_graph_evtreat
    version 14.0

    syntax [, CONTEXT(string) CURRENTLAWCHECKED]

    if `"`context'"' == "" {
        local context "pte_graph, evolution"
    }

    _pte_validate_internal_state _pte_treat binary ///
        "`context' requires _pte_treat to remain the binary ever-treated bridge."

    _pte_validate_internal_state _pte_nt integer ///
        "`context' requires _pte_nt to remain the integer event-time bridge."

    local panelvar ""
    local setup_panel : char _dta[_pte_setup_panelvar]
    local setup_time : char _dta[_pte_setup_timevar]
    local setup_treatment : char _dta[_pte_setup_treatment]
    local setup_treatsig : char _dta[_pte_setup_treatsig]
    local setup_xtdelta : char _dta[_pte_setup_xtdelta]
    local live_id ""
    local live_time ""
    local live_treatsig ""
    local live_predict ""
    local live_treatment ""
    if "`e(cmd)'" == "pte" {
        capture local live_id = e(idvar)
        if _rc != 0 | inlist("`live_id'", "", ".") {
            capture local live_id = e(id)
        }
        if "`live_id'" == "." {
            local live_id ""
        }
        capture local live_time = e(timevar)
        if _rc != 0 | inlist("`live_time'", "", ".") {
            capture local live_time = e(time)
        }
        if "`live_time'" == "." {
            local live_time ""
        }
        capture local live_treatsig = e(treatsig)
        if _rc != 0 | "`live_treatsig'" == "." {
            local live_treatsig ""
        }
        capture local live_predict = e(predict)
        if _rc != 0 | "`live_predict'" == "." {
            local live_predict ""
        }
        capture local live_treatment = e(treatment)
        if _rc != 0 | "`live_treatment'" == "." {
            local live_treatment ""
        }
    }
    local have_setup_fragment = ///
        (`"`setup_panel'"' != "") | ///
        (`"`setup_time'"' != "") | ///
        (`"`setup_treatment'"' != "") | ///
        (`"`setup_treatsig'"' != "") | ///
        (`"`setup_xtdelta'"' != "")
    local have_live_panel_contract = ///
        (`"`live_id'"' != "") | (`"`live_time'"' != "") | (`"`live_treatsig'"' != "")
    local have_live_payload = ///
        (`"`live_predict'"' != "")
    // A pure compatibility stub may advertise only e(cmd)="pte" and nothing
    // else; keep the legacy _pte_firm fallback for that narrow case. Once
    // any additional live predict payload is present, evolution graphs must
    // honor the shared diagnostics contract instead of reviving legacy
    // fallback. A bare e(treatment) name alone does not certify the active
    // graph law.
    local have_live_pte = (`have_live_panel_contract' | `have_live_payload')

    if "`currentlawchecked'" == "" {
        if `have_setup_fragment' | `have_live_pte' {
            capture quietly _pte_diag_panel_contract, context("`context'") ///
                allowsetupmissingxtdelta
            local panel_contract_rc = _rc
            if `panel_contract_rc' == 0 {
                local panel_candidate "`r(idvar)'"
                if "`panel_candidate'" != "" {
                    capture confirm variable `panel_candidate', exact
                    if !_rc {
                        local panelvar "`panel_candidate'"
                    }
                }
            }
            else {
                exit `panel_contract_rc'
            }
        }
    }
    else {
        capture quietly xtset
        if _rc == 0 {
            local xtset_id "`r(panelvar)'"
        }
        if `"`setup_panel'"' != "" {
            local panelvar "`setup_panel'"
        }
        else if `"`live_id'"' != "" {
            local panelvar "`live_id'"
        }
        else if `"`xtset_id'"' != "" {
            local panelvar "`xtset_id'"
        }
    }
    if "`panelvar'" == "" & !`have_setup_fragment' & !`have_live_pte' {
        capture confirm variable _pte_firm, exact
        if !_rc {
            local panelvar "_pte_firm"
        }
    }
    if "`panelvar'" != "" {
        tempvar _pte_treat_sd
        quietly bysort `panelvar': egen double `_pte_treat_sd' = sd(_pte_treat)
        capture assert missing(`_pte_treat_sd') | `_pte_treat_sd' <= 1e-10
        if _rc {
            di as error "[pte] _pte_treat must remain constant within each panel unit."
            di as error "[pte] `context' requires the ever-treated bridge, not the current-period treatment path."
            di as error "[pte] Re-run pte to regenerate internal variables"
            exit 450
        }
    }
end
