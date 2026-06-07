*! _pte_diag_panel_contract.ado
*! Resolve the panel/time variables for postestimation diagnostics.

version 14.0
capture program drop _pte_diag_panel_contract
program define _pte_diag_panel_contract, rclass
    version 14.0

    syntax [, CONTEXT(string) ALLOWSETUPMISSINGXTDELTA]

    local context = strtrim(`"`context'"')
    if `"`context'"' == "" {
        local context "diagnostics"
    }

    local idvar ""
    local timevar ""
    local est_treatment ""
    local est_treatsig ""
    local est_xtdelta ""
    local est_predict ""
    local setup_treatment : char _dta[_pte_setup_treatment]
    local setup_treatsig : char _dta[_pte_setup_treatsig]
    local setup_xtdelta : char _dta[_pte_setup_xtdelta]
    local contract_treatment `"`setup_treatment'"'
    local contract_treatsig `"`setup_treatsig'"'
    local xtdelta ""

    if "`e(cmd)'" == "pte" {
        capture local idvar = e(idvar)
        if `"`idvar'"' == "." {
            local idvar ""
        }
        if _rc != 0 | `"`idvar'"' == "" {
            capture local idvar = e(id)
            if `"`idvar'"' == "." {
                local idvar ""
            }
        }
        capture local timevar = e(timevar)
        if `"`timevar'"' == "." {
            local timevar ""
        }
        if _rc != 0 | `"`timevar'"' == "" {
            capture local timevar = e(time)
            if `"`timevar'"' == "." {
                local timevar ""
            }
        }
        capture local est_treatment = e(treatment)
        if `"`est_treatment'"' == "." {
            local est_treatment ""
        }
        capture local est_treatsig = e(treatsig)
        if `"`est_treatsig'"' == "." {
            local est_treatsig ""
        }
        capture local est_predict = e(predict)
        if `"`est_predict'"' == "." {
            local est_predict ""
        }
        tempname _pte_diag_xtdelta
        capture scalar `_pte_diag_xtdelta' = e(xtdelta)
        if _rc == 0 & !missing(`_pte_diag_xtdelta') {
            local est_xtdelta = strofreal(`_pte_diag_xtdelta')
        }
    }
    local live_idvar `"`idvar'"'
    local live_timevar `"`timevar'"'

    local setup_id : char _dta[_pte_setup_panelvar]
    local setup_time : char _dta[_pte_setup_timevar]
    local have_setup_id = (`"`setup_id'"' != "")
    local have_setup_time = (`"`setup_time'"' != "")
    local have_setup_treatment = (`"`setup_treatment'"' != "")
    local have_setup_treatsig = (`"`setup_treatsig'"' != "")
    local have_setup_xtdelta = (`"`setup_xtdelta'"' != "")
    local have_setup_fragment = ///
        (`have_setup_id' | `have_setup_time' | `have_setup_treatment' | ///
         `have_setup_treatsig' | `have_setup_xtdelta')
    local have_complete_live_current_law = ///
        (`"`live_idvar'"' != "") & ///
        (`"`live_timevar'"' != "") & ///
        (`"`est_treatment'"' != "") & ///
        (`"`est_treatsig'"' != "")
    local have_live_current_law_claim = ///
        (`"`live_idvar'"' != "") | ///
        (`"`live_timevar'"' != "") | ///
        (`"`est_treatsig'"' != "") | ///
        (`"`est_predict'"' != "") | ///
        (`"`est_xtdelta'"' != "")

    // pte_setup, check can intentionally invalidate the stored setup chars
    // while leaving previously generated helper variables untouched. Those
    // helpers are no longer certified treatment-timing objects, so ambient
    // xtset must not silently reactivate them for downstream consumers when
    // there is no live pte result to certify the current law.
    local have_canonical_helper = 0
    foreach helper in _pte_D _pte_treat _pte_nt _pte_mid _pte_cohort ///
        _pte_treat_year _pte_first_treat_year {
        capture confirm variable `helper', exact
        if _rc == 0 {
            local have_canonical_helper = 1
            continue, break
        }
    }

    // setup-selected panel/time/treatment metadata is an atomic contract.
    // A partial stored triplet indicates corrupted provenance and must not be
    // completed from ambient xtset or stale e() payloads, or downstream
    // diagnostics will silently consume helper variables from an unknown
    // treatment law.
    if `have_setup_fragment' {
        if !`have_setup_id' | !`have_setup_time' | !`have_setup_treatment' | !`have_setup_treatsig' | !`have_setup_xtdelta' {
            di as error "Stored setup panel/time/treatment contract is incomplete for `context'."
            di as error "The setup contract requires _dta[_pte_setup_panelvar], _dta[_pte_setup_timevar], _dta[_pte_setup_treatment], _dta[_pte_setup_treatsig], and _dta[_pte_setup_xtdelta] together."
            di as error "Re-run pte_setup on the current dataset before `context'."
            exit 459
        }

        capture confirm variable `setup_id', exact
        if _rc != 0 {
            di as error "Stored panel variable `setup_id' not found in data."
            di as error "Re-run pte_setup on the current dataset before `context'."
            exit 111
        }
        capture confirm variable `setup_time', exact
        if _rc != 0 {
            di as error "Stored time variable `setup_time' not found in data."
            di as error "Re-run pte_setup on the current dataset before `context'."
            exit 111
        }

        capture noisily _pte_assert_setup_current_law, ///
            panelvar(`setup_id') timevar(`setup_time') ///
            treatment(`setup_treatment') ///
            treatsig(`"`setup_treatsig'"') ///
            context("`context'")
        local _pte_setup_current_law_rc = _rc
        if `_pte_setup_current_law_rc' != 0 {
            exit `_pte_setup_current_law_rc'
        }

        // Once pte_setup publishes a complete dataset-scoped panel contract,
        // post-setup consumers must keep using that latest axis. But the live
        // pte result must still publish the exact current panel/time metadata
        // (canonical or legacy aliases) so the active e() state can be
        // certified against that setup-selected axis before any downstream
        // omega/eps0/graph consumer uses it.
        local idvar "`setup_id'"
        local timevar "`setup_time'"
    }

    // Without a stored setup contract, consumers that rely on the live pte
    // panel/treatment law must still certify that e(treatsig) describes the
    // current dataset. Otherwise graph/diagnose workers silently keep using
    // stale _pte_treat/_pte_nt/_pte_tt bundles after the caller changes the
    // treatment path but leaves live e() metadata behind.
    if !`have_setup_fragment' & "`e(cmd)'" == "pte" & `have_complete_live_current_law' {
        capture noisily _pte_assert_setup_current_law, ///
            panelvar(`live_idvar') timevar(`live_timevar') ///
            treatment(`est_treatment') ///
            treatsig(`"`est_treatsig'"') ///
            context("`context'")
        local _pte_live_current_law_rc = _rc
        if `_pte_live_current_law_rc' != 0 {
            exit `_pte_live_current_law_rc'
        }
        local contract_treatment `"`est_treatment'"'
        local contract_treatsig `"`est_treatsig'"'
    }

    // A pure live pte claimant that publishes any current-law fragment beyond
    // the bare treatment name must publish the full id/time/treatment/treatsig
    // bundle together. Otherwise xtset or legacy helpers would silently bridge
    // an uncertifiable live law, and downstream graph/diagnose consumers would
    // keep using stale treatment-timing objects after the current data change.
    if !`have_setup_fragment' & "`e(cmd)'" == "pte" & ///
        `have_live_current_law_claim' & !`have_complete_live_current_law' {
        di as error "Live pte panel/treatment contract is incomplete for `context'."
        di as error "Publish e(idvar)/e(timevar) or legacy e(id)/e(time) together with e(treatment) and e(treatsig), or clear the live pte state before `context'."
        exit 459
    }

    // A setup-backed public consumer combines dataset-scoped timing helpers
    // with live pte state. If the active pte result omits either side of the
    // panel axis, setup chars would silently mask a stale or partial live e()
    // contract. Fail closed instead of bridging missing live panel metadata.
    if `have_setup_fragment' & "`e(cmd)'" == "pte" {
        if `"`est_treatsig'"' != "" & `"`setup_treatsig'"' != "" & `"`est_treatsig'"' != `"`setup_treatsig'"' {
            di as error "Stored setup treatment law conflicts with live e(treatsig) for `context'."
            di as error "Re-run pte on the current treatment path or rerun pte_setup before `context'."
            exit 459
        }
        if `"`est_treatment'"' != "" & `"`setup_treatment'"' != "" & `"`est_treatment'"' != `"`setup_treatment'"' {
            di as error "Stored setup treatment `setup_treatment' conflicts with live e(treatment)=`est_treatment' for `context'."
            di as error "Re-run pte with treatment(`setup_treatment') or rerun pte_setup using the same treatment() as the active pte result."
            exit 459
        }
        if `"`setup_treatsig'"' != "" & `"`est_treatsig'"' == "" {
            di as error "Stored setup treatment law is present but live e(treatsig) is missing for `context'."
            di as error "Re-run pte on the current treatment path before `context'."
            exit 459
        }
        if `"`setup_xtdelta'"' != "" & `"`est_xtdelta'"' == "" & "`allowsetupmissingxtdelta'" == "" {
            di as error "Stored setup xtdelta is present but live e(xtdelta) is missing for `context'."
            di as error "Re-run pte on the current setup-selected panel spacing before `context'."
            exit 459
        }
        if `"`live_idvar'"' == "" {
            di as error "Stored setup panel contract is present but live e(idvar) or legacy e(id) is missing for `context'."
            di as error "Re-run pte on the current setup-selected panel axis before `context'."
            exit 459
        }
        if `"`live_timevar'"' == "" {
            di as error "Stored setup panel contract is present but live e(timevar) or legacy e(time) is missing for `context'."
            di as error "Re-run pte on the current setup-selected time axis before `context'."
            exit 459
        }
        // setup-backed consumers certify a single exact panel/time axis. If
        // the active live pte result claims a different axis, silently
        // returning setup_id/setup_time below would mask a stale live
        // contract and let downstream diagnostics/graphs mix producer and
        // consumer state from different panel declarations.
        if `"`setup_id'"' != "" & `"`live_idvar'"' != "" & `"`setup_id'"' != `"`live_idvar'"' {
            di as error "Stored setup panel variable `setup_id' conflicts with live e(idvar)=`live_idvar' for `context'."
            di as error "Re-run pte on the current setup-selected panel axis before `context'."
            exit 459
        }
        if `"`setup_time'"' != "" & `"`live_timevar'"' != "" & `"`setup_time'"' != `"`live_timevar'"' {
            di as error "Stored setup time variable `setup_time' conflicts with live e(timevar)=`live_timevar' for `context'."
            di as error "Re-run pte on the current setup-selected time axis before `context'."
            exit 459
        }
    }

    // Some diagnose-only consumers use just the certified panel/time axis and
    // the setup-published treatment helpers; for that narrow path, a complete
    // setup contract can bridge a missing live e(xtdelta) without weakening
    // the separate drift check below. Graph and lag-law consumers keep the
    // stricter default gate unless they opt into this bridge explicitly.
    if "`e(cmd)'" == "pte" & `"`est_xtdelta'"' == "" {
        if `"`setup_xtdelta'"' != "" & "`allowsetupmissingxtdelta'" != "" {
            local est_xtdelta `"`setup_xtdelta'"'
        }
        else if `"`setup_xtdelta'"' != "" {
            di as error "Stored setup xtdelta is present but live e(xtdelta) is missing for `context'."
            di as error "Re-run pte on the current setup-selected panel spacing before `context'."
            exit 459
        }
        else {
            di as error "Live e(xtdelta) is missing for `context'."
            di as error "Re-run pte on the current dataset before `context'."
            exit 459
        }
    }

    // Diagnostics consume treatment-timing helpers generated by pte_setup
    // together with omega/eps0 objects typically published by pte. Those two
    // state bundles must agree on treatment(); otherwise the wrapper silently
    // mixes one treatment law's timing groups with another law's productivity
    // objects.
    if `"`setup_treatment'"' != "" & `"`est_treatment'"' != "" ///
        & `"`setup_treatment'"' != `"`est_treatment'"' {
        di as error "Stored setup treatment `setup_treatment' conflicts with live e(treatment)=`est_treatment' for `context'."
        di as error "Re-run pte with treatment(`setup_treatment') or rerun pte_setup using the same treatment() as the active pte result."
        exit 459
    }
    if `"`setup_treatsig'"' != "" & `"`est_treatsig'"' != "" ///
        & `"`setup_treatsig'"' != `"`est_treatsig'"' {
        di as error "Stored setup treatment law conflicts with live e(treatsig) for `context'."
        di as error "Re-run pte on the current treatment path or rerun pte_setup before `context'."
        exit 459
    }
    // xtdelta is part of the lag-time law consumed by diagnostics/graphs.
    // If live e() advertises a different panel spacing than the setup
    // contract, silently preferring one side would mask stale estimates.
    local setup_xtdelta_clean = strtrim(`"`setup_xtdelta'"')
    local est_xtdelta_clean = strtrim(`"`est_xtdelta'"')
    if `"`setup_xtdelta_clean'"' != "" & `"`est_xtdelta_clean'"' != "" {
        local setup_xtdelta_num = real(`"`setup_xtdelta_clean'"')
        local est_xtdelta_num = real(`"`est_xtdelta_clean'"')
        local xtdelta_conflict = 0
        if !missing(`setup_xtdelta_num') & !missing(`est_xtdelta_num') {
            if `setup_xtdelta_num' != `est_xtdelta_num' {
                local xtdelta_conflict = 1
            }
        }
        else if `"`setup_xtdelta_clean'"' != `"`est_xtdelta_clean'"' {
            local xtdelta_conflict = 1
        }
        if `xtdelta_conflict' {
            di as error "Stored setup xtdelta=`setup_xtdelta_clean' conflicts with live e(xtdelta)=`est_xtdelta_clean' for `context'."
            di as error "Re-run pte on the current setup-selected panel spacing before `context'."
            exit 459
        }
    }

    if `"`setup_xtdelta'"' != "" {
        local xtdelta `"`setup_xtdelta'"'
    }
    else if `"`est_xtdelta'"' != "" {
        local xtdelta `"`est_xtdelta'"'
    }

    if !`have_setup_fragment' & "`e(cmd)'" != "pte" & `have_canonical_helper' {
        di as error "Canonical PTE helper variables are present but no certified setup contract is stored for `context'."
        di as error "Run pte_setup on the current dataset before `context'."
        exit 459
    }

    if `"`idvar'"' == "" | `"`timevar'"' == "" | `"`xtdelta'"' == "" {
        capture quietly xtset
        if _rc == 0 {
            local xtset_id = r(panelvar)
            local xtset_time = r(timevar)
            local xtset_delta = r(tdelta)

            // Without a stored setup contract, legacy live e() metadata may
            // still identify the panel axis. Ambient xtset can only complete
            // missing fields when it describes that same axis; otherwise it
            // would splice together incompatible lag laws.
            if !`have_setup_fragment' {
                if `"`idvar'"' != "" & `"`xtset_id'"' != "" & `"`idvar'"' != `"`xtset_id'"' {
                    di as error "Ambient xtset panel axis `xtset_id' conflicts with live e(idvar)=`idvar' for `context'."
                    di as error "Re-run pte on the current xtset axis or xtset the live pte panel before `context'."
                    exit 459
                }
                if `"`timevar'"' != "" & `"`xtset_time'"' != "" & `"`timevar'"' != `"`xtset_time'"' {
                    di as error "Ambient xtset time axis `xtset_time' conflicts with live e(timevar)=`timevar' for `context'."
                    di as error "Re-run pte on the current xtset axis or xtset the live pte time variable before `context'."
                    exit 459
                }
            }

            if `"`idvar'"' == "" local idvar = `"`xtset_id'"'
            if `"`timevar'"' == "" local timevar = `"`xtset_time'"'
            if `"`xtdelta'"' == "" local xtdelta = `"`xtset_delta'"'
        }
    }

    if `"`idvar'"' == "" | `"`timevar'"' == "" {
        di as error "Panel data not set for `context'."
        di as error "Re-run pte on the current dataset or xtset the panel before `context'."
        exit 459
    }

    capture confirm variable `idvar', exact
    if _rc != 0 {
        di as error "Stored panel variable `idvar' not found in data."
        di as error "Re-run pte on the current dataset before `context'."
        exit 111
    }

    capture confirm variable `timevar', exact
    if _rc != 0 {
        di as error "Stored time variable `timevar' not found in data."
        di as error "Re-run pte on the current dataset before `context'."
        exit 111
    }

    return local idvar "`idvar'"
    return local timevar "`timevar'"
    return local treatment `"`contract_treatment'"'
    return local treatsig `"`contract_treatsig'"'
    return local xtdelta `"`xtdelta'"'
end
