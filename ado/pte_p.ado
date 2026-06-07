*! pte_p.ado
*! Postestimation predict interface for stored pte results.

version 14.0
capture program drop pte_p
program define pte_p, sortpreserve
    version 14.0

    syntax [anything(name=vlist)] [if] [in] [, ///
        OMEGA       ///
        PHI         ///
        RESIDuals   ///
        EXPonential ///
        PARameters  ///
        TT          ///
        ATT         ///
    ]

    // predict relies on stored e() results and generated working variables.
    if "`e(cmd)'" != "pte" {
        di as error "last estimates not found"
        di as error "You must run pte before predict"
        exit 301
    }

    // setup-selected helper variables and live pte estimates must agree on
    // the treatment law itself, not only on the treatment variable name.
    local pte_setup_treatment : char _dta[_pte_setup_treatment]
    local pte_setup_treatsig : char _dta[_pte_setup_treatsig]
    local pte_setup_panelvar : char _dta[_pte_setup_panelvar]
    local pte_setup_timevar : char _dta[_pte_setup_timevar]
    local pte_setup_xtdelta : char _dta[_pte_setup_xtdelta]
    local pte_live_treatment ""
    local pte_live_treatsig ""
    local pte_live_id ""
    local pte_live_time ""
    capture local pte_live_treatment = e(treatment)
    if `"`pte_live_treatment'"' == "." {
        local pte_live_treatment ""
    }
    capture local pte_live_treatsig = e(treatsig)
    capture local pte_live_id = e(idvar)
    if `"`pte_live_id'"' == "." {
        local pte_live_id ""
    }
    if _rc != 0 | `"`pte_live_id'"' == "" {
        capture local pte_live_id = e(id)
        if `"`pte_live_id'"' == "." {
            local pte_live_id ""
        }
    }
    capture local pte_live_time = e(timevar)
    if `"`pte_live_time'"' == "." {
        local pte_live_time ""
    }
    if _rc != 0 | `"`pte_live_time'"' == "" {
        capture local pte_live_time = e(time)
        if `"`pte_live_time'"' == "." {
            local pte_live_time ""
        }
    }
    local pte_live_xtdelta ""
    tempname pte_live_xtdelta_scalar
    capture scalar `pte_live_xtdelta_scalar' = e(xtdelta)
    if _rc == 0 & !missing(`pte_live_xtdelta_scalar') {
        local pte_live_xtdelta = strofreal(`pte_live_xtdelta_scalar')
    }
    if `"`pte_live_treatsig'"' == "." {
        local pte_live_treatsig ""
    }

    local pte_have_setup_panel = (`"`pte_setup_panelvar'"' != "")
    local pte_have_setup_time = (`"`pte_setup_timevar'"' != "")
    local pte_have_setup_treatment = (`"`pte_setup_treatment'"' != "")
    local pte_have_setup_treatsig = (`"`pte_setup_treatsig'"' != "")
    local pte_have_setup_xtdelta = (`"`pte_setup_xtdelta'"' != "")
    local pte_has_setup_contract = ///
        (`pte_have_setup_panel' | `pte_have_setup_time' | ///
         `pte_have_setup_treatment' | `pte_have_setup_treatsig' | ///
         `pte_have_setup_xtdelta')
    local pte_live_full_law = ///
        (`"`pte_live_id'"' != "") & ///
        (`"`pte_live_time'"' != "") & ///
        (`"`pte_live_treatment'"' != "") & ///
        (`"`pte_live_treatsig'"' != "")
    local pte_live_law_claim = ///
        (`"`pte_live_treatment'"' != "") | ///
        (`"`pte_live_treatsig'"' != "") | ///
        (`"`pte_live_id'"' != "") | ///
        (`"`pte_live_time'"' != "") | ///
        (`"`pte_live_xtdelta'"' != "")

    // pte_setup publishes a dataset-scoped panel/time/treatment contract as
    // one atomic bundle. A partial char set means the current helper-state
    // provenance is unknown, so predict must fail closed rather than mixing
    // live e() results with stale or corrupted setup metadata.
    if `pte_has_setup_contract' {
        if !`pte_have_setup_panel' | !`pte_have_setup_time' | ///
            !`pte_have_setup_treatment' | !`pte_have_setup_treatsig' | ///
            !`pte_have_setup_xtdelta' {
            di as error "predict after pte_setup requires a complete stored setup contract"
            di as error "The setup contract requires _dta[_pte_setup_panelvar], _dta[_pte_setup_timevar], _dta[_pte_setup_treatment], _dta[_pte_setup_treatsig], and _dta[_pte_setup_xtdelta] together."
            di as error "Re-run pte_setup on the current dataset before predict"
            exit 459
        }

        capture noisily _pte_assert_setup_current_law, ///
            panelvar(`pte_setup_panelvar') timevar(`pte_setup_timevar') ///
            treatment(`pte_setup_treatment') ///
            treatsig(`"`pte_setup_treatsig'"') ///
            context("predict after pte_setup")
        local pte_setup_current_law_rc = _rc
        if `pte_setup_current_law_rc' != 0 {
            exit `pte_setup_current_law_rc'
        }
    }

    // Without a stored setup contract, predict must still fail closed when
    // the live pte result claims a current treatment law. Otherwise stale
    // e(treatsig) metadata can survive after D changes and pte_p would keep
    // publishing TT/ATT values tied to the wrong event-time path.
    if !`pte_has_setup_contract' {
        if `pte_live_law_claim' & !`pte_live_full_law' {
            di as error "predict requires a complete live panel/treatment contract when no stored pte_setup contract is present"
            di as error "Publish e(idvar)/e(timevar) or legacy e(id)/e(time) together with e(treatment) and e(treatsig), or clear the live pte state before predict"
            exit 459
        }
        if `pte_live_full_law' {
            capture noisily _pte_assert_setup_current_law, ///
                panelvar(`pte_live_id') timevar(`pte_live_time') ///
                treatment(`pte_live_treatment') ///
                treatsig(`"`pte_live_treatsig'"') ///
                context("predict")
            local pte_live_current_law_rc = _rc
            if `pte_live_current_law_rc' != 0 {
                exit `pte_live_current_law_rc'
            }
        }
    }

    // Once pte_setup has published a dataset-scoped treatment-law signature,
    // any live pte result lacking e(treatsig) is uncertified for that law.
    if `"`pte_setup_treatsig'"' != "" & `"`pte_live_treatsig'"' == "" {
        di as error "predict after pte_setup requires live e(treatsig) to certify the current treatment path"
        di as error "Re-run pte on the current data before predict"
        exit 459
    }

    // The setup contract certifies a specific panel/time axis, so live
    // postestimation must publish panel metadata (canonical or legacy) before
    // any non-residual branch can consume stored omega/phi/ATT objects.
    if `"`pte_setup_panelvar'"' != "" & `"`pte_live_id'"' == "" {
        di as error "predict after pte_setup requires live e(idvar) or legacy e(id) to certify the current panel axis"
        di as error "Re-run pte on the current data before predict"
        exit 459
    }
    if `"`pte_setup_timevar'"' != "" & `"`pte_live_time'"' == "" {
        di as error "predict after pte_setup requires live e(timevar) or legacy e(time) to certify the current time axis"
        di as error "Re-run pte on the current data before predict"
        exit 459
    }

    if `"`pte_setup_panelvar'"' != "" & `"`pte_live_id'"' != "" & ///
        `"`pte_setup_panelvar'"' != `"`pte_live_id'"' {
        di as error "predict after pte_setup requires the same panel/time law as the live pte result"
        di as error "Re-run pte on the current data before predict"
        exit 459
    }
    if `"`pte_setup_timevar'"' != "" & `"`pte_live_time'"' != "" & ///
        `"`pte_setup_timevar'"' != `"`pte_live_time'"' {
        di as error "predict after pte_setup requires the same panel/time law as the live pte result"
        di as error "Re-run pte on the current data before predict"
        exit 459
    }
    if `"`pte_setup_treatment'"' != "" & `"`pte_live_treatment'"' != "" & ///
        `"`pte_setup_treatment'"' != `"`pte_live_treatment'"' {
        di as error "predict after pte_setup requires the same treatment() law as the live pte result"
        di as error "Re-run pte on the current data before predict"
        exit 459
    }
    if `"`pte_setup_treatsig'"' != "" & `"`pte_live_treatsig'"' != "" & ///
        `"`pte_setup_treatsig'"' != `"`pte_live_treatsig'"' {
        di as error "predict after pte_setup detected stale pte estimates for the current treatment path"
        di as error "Re-run pte on the current data before predict"
        exit 459
    }

    // Only one prediction target can be requested per call, including the
    // reporting-only parameters action.
    local opt_count = ("`omega'" != "") + ("`phi'" != "") + ///
                      ("`residuals'" != "") + ("`exponential'" != "") + ///
                      ("`parameters'" != "") + ("`tt'" != "") + ("`att'" != "")

    if `opt_count' > 1 {
        di as error "pte predict: options omega, phi, residuals, exponential, parameters, tt, and att are mutually exclusive"
        exit 198
    }

    local pte_predict_target ""
    if `opt_count' == 0 {
        local pte_predict_target "omega"
    }
    else if "`omega'" != "" {
        local pte_predict_target "omega"
    }
    else if "`phi'" != "" {
        local pte_predict_target "phi"
    }
    else if "`residuals'" != "" {
        local pte_predict_target "residuals"
    }
    else if "`exponential'" != "" {
        local pte_predict_target "exponential"
    }
    else if "`parameters'" != "" {
        local pte_predict_target "parameters"
    }
    else if "`tt'" != "" {
        local pte_predict_target "tt"
    }
    else if "`att'" != "" {
        local pte_predict_target "att"
    }

    // After pte_setup publishes a certified panel-spacing contract, all
    // predict branches except residual fallback require live e(xtdelta) to
    // certify that the active pte result was estimated under the same lag
    // law. residuals has its own legacy fallback that can rebuild lags from
    // the stored setup delta when the live result predates e(xtdelta).
    if `"`pte_setup_xtdelta'"' != "" & `"`pte_predict_target'"' != "residuals" {
        if `"`pte_live_xtdelta'"' == "" {
            di as error "predict after pte_setup requires live e(xtdelta) to certify the current panel spacing"
            di as error "Re-run pte on the current data before predict"
            exit 459
        }

        local pte_setup_xtdelta_clean = strtrim(`"`pte_setup_xtdelta'"')
        local pte_live_xtdelta_clean = strtrim(`"`pte_live_xtdelta'"')
        local pte_xtdelta_conflict = 0
        if `"`pte_setup_xtdelta_clean'"' != "" & `"`pte_live_xtdelta_clean'"' != "" {
            local pte_setup_xtdelta_num = real(`"`pte_setup_xtdelta_clean'"')
            local pte_live_xtdelta_num = real(`"`pte_live_xtdelta_clean'"')
            if !missing(`pte_setup_xtdelta_num') & !missing(`pte_live_xtdelta_num') {
                if `pte_setup_xtdelta_num' != `pte_live_xtdelta_num' {
                    local pte_xtdelta_conflict = 1
                }
            }
            else if `"`pte_setup_xtdelta_clean'"' != `"`pte_live_xtdelta_clean'"' {
                local pte_xtdelta_conflict = 1
            }
        }

        if `pte_xtdelta_conflict' {
            di as error "predict after pte_setup detected stale pte estimates for the current panel spacing"
            di as error "Re-run pte on the current data before predict"
            exit 459
        }
    }

    // parameters is a reporting action, not a generated-variable action.
    if "`parameters'" != "" {
        if `"`vlist'"' != "" {
            di as error "predict, parameters does not allow a new variable"
            exit 198
        }
        if `"`if'`in'"' != "" {
            di as error "predict, parameters does not allow if or in qualifiers"
            di as error "predict, parameters is a reporting action over stored e() results"
            exit 198
        }
        _pte_predict_parameters
        exit
    }

    if `"`vlist'"' == "" {
        di as error "something required"
        exit 100
    }

    gettoken typlist varlist : vlist
    if "`varlist'" == "" {
        local varlist "`typlist'"
        local typlist "float"
    }
    else {
        local _pte_typlist = lower("`typlist'")
        local _pte_has_storage_type = ///
            inlist("`_pte_typlist'", "byte", "int", "long", "float", "double")
        if !`_pte_has_storage_type' {
            if regexm("`_pte_typlist'", "^str([1-9][0-9]*|l)$") {
                di as error "pte predict: predictions must use a numeric storage type"
                exit 198
            }
        }
        if !`_pte_has_storage_type' {
            di as error "pte predict: only one new variable may be specified"
            exit 198
        }
        local _pte_newvar_words : word count `varlist'
        if `_pte_newvar_words' != 1 {
            di as error "pte predict: only one new variable may be specified"
            exit 198
        }
    }
    confirm new variable `varlist'

    // Default to the primary latent productivity object.
    if `opt_count' == 0 {
        local omega "omega"
    }

    // Respect if/in restrictions without reparsing the prediction varlist.
    marksample touse, novarlist

    // Each helper enforces the stored-result requirements for one target.
    if "`omega'" != "" {
        _pte_predict_omega `typlist' `varlist' `touse'
    }
    else if "`phi'" != "" {
        _pte_predict_phi `typlist' `varlist' `touse'
    }
    else if "`residuals'" != "" {
        _pte_predict_residuals `typlist' `varlist' `touse'
    }
    else if "`exponential'" != "" {
        _pte_predict_exponential `typlist' `varlist' `touse'
    }
    else if "`parameters'" != "" {
        _pte_predict_parameters
    }
    else if "`tt'" != "" {
        _pte_predict_tt `typlist' `varlist' `touse'
    }
    else if "`att'" != "" {
        _pte_predict_att `typlist' `varlist' `touse'
    }
end


// Core postestimation state objects must remain numeric and semantically valid.
capture program drop _pte_validate_binary_state
program define _pte_validate_binary_state
    args varname context

    capture confirm variable `varname', exact
    if _rc {
        di as error "[pte] `varname' variable not found"
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 111
    }

    capture confirm numeric variable `varname'
    if _rc {
        di as error "[pte] `varname' must be numeric (0/1)."
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 111
    }

    capture assert inlist(`varname', 0, 1) if !missing(`varname')
    if _rc {
        di as error "[pte] `varname' must be binary (0/1)."
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 450
    }
end


capture program drop _pte_validate_integer_state
program define _pte_validate_integer_state
    args varname context

    capture confirm variable `varname', exact
    if _rc {
        di as error "[pte] `varname' variable not found"
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 111
    }

    capture confirm numeric variable `varname'
    if _rc {
        di as error "[pte] `varname' must be numeric."
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 111
    }

    capture assert abs(`varname' - round(`varname')) <= 1e-10 if !missing(`varname')
    if _rc {
        di as error "[pte] `varname' must be integer-valued when nonmissing."
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 450
    }
end


capture program drop _pte_validate_numeric_state
program define _pte_validate_numeric_state
    args varname context

    capture confirm variable `varname', exact
    if _rc {
        di as error "[pte] `varname' variable not found"
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 111
    }

    capture confirm numeric variable `varname'
    if _rc {
        di as error "[pte] `varname' must be numeric."
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 111
    }
end


// Grouped observation-level replay is only defined on the estimation-time
// partition published in e(groups). Current data may drop some groups, but it
// must not introduce new ones because there is no grouped law to map from.
capture program drop _pte_validate_group_route
program define _pte_validate_group_route
    args grouped_by grouped_labels touse route_label

    tempvar _pte_group_match
    quietly gen byte `_pte_group_match' = 0 if `touse'

    local grouped_by_numeric = 0
    capture confirm numeric variable `grouped_by'
    if _rc == 0 {
        local grouped_by_numeric = 1
    }

    local grouped_labels_work `"`grouped_labels'"'
    while `"`grouped_labels_work'"' != "" {
        gettoken grp grouped_labels_work : grouped_labels_work, quotes
        if `"`grp'"' == "" {
            continue
        }
        local grp_value `"`grp'"'
        if `grouped_by_numeric' {
            quietly replace `_pte_group_match' = 1 if `grouped_by' == `grp_value' & `touse'
        }
        else {
            quietly replace `_pte_group_match' = 1 if `grouped_by' == `grp_value' & `touse'
        }
    }

    quietly count if `touse' & !missing(`grouped_by') & `_pte_group_match' != 1
    local n_unmatched = r(N)
    if `n_unmatched' > 0 {
        di as error "[pte] `route_label' detected current-data groups outside the stored e(groups) route"
        di as error "[pte] Unmatched observations: `n_unmatched' using by() variable `grouped_by'"
        di as error "[pte] Re-run grouped pte on the current dataset or restrict predict to estimation-time groups only"
        exit 459
    }
end


// Reuse the stored latent-productivity series instead of recomputing it.
capture program drop _pte_predict_omega
program define _pte_predict_omega
    args typlist varlist touse

    capture confirm variable _pte_omega, exact
    if _rc {
        di as error "_pte_omega variable not found"
        di as error "Run pte before predict"
        exit 111
    }
    capture confirm numeric variable _pte_omega
    if _rc {
        di as error "_pte_omega must be numeric."
        di as error "Re-run pte before predict, omega, or rebuild _pte_omega from the live state."
        exit 111
    }

    quietly gen `typlist' `varlist' = _pte_omega if `touse'
    label variable `varlist' "Productivity omega from pte"
end


// Pass through the first-stage control-function object saved by pte.
capture program drop _pte_predict_phi
program define _pte_predict_phi
    args typlist varlist touse

    capture confirm variable _pte_phi, exact
    if _rc {
        di as error "_pte_phi variable not found"
        di as error "Run pte before predict"
        exit 111
    }
    capture confirm numeric variable _pte_phi
    if _rc {
        di as error "_pte_phi must be numeric."
        di as error "Re-run pte before predict, phi, or rebuild _pte_phi from the live state."
        exit 111
    }

    quietly gen `typlist' `varlist' = _pte_phi if `touse'
    label variable `varlist' "First-stage phi from pte"
end


// Recover untreated productivity innovations where the untreated law of motion
// is identified. Exact _pte_eps0 values take priority; otherwise use the
// stored untreated evolution law and lagged realized omega, then mask
// observations that are outside that untreated interpretation.
capture program drop _pte_predict_residuals
program define _pte_predict_residuals
    args typlist varlist touse

    local pte_setup_xtdelta : char _dta[_pte_setup_xtdelta]
    local _pte_resid_treat_context "predict, residuals requires _pte_treat to be the binary ever-treated bridge used to mask treated observations."
    local _pte_resid_nt_context "predict, residuals requires _pte_nt to be the integer event-time bridge published by ATT recovery when present."
    local _pte_resid_D_context "predict, residuals requires _pte_D to be the binary realized-treatment bridge used by the fallback mask."
    local _pte_resid_mid_context "predict, residuals requires _pte_mid to be the binary transition-state bridge."

    capture confirm variable _pte_treat, exact
    if !_rc {
        _pte_validate_binary_state _pte_treat `"`_pte_resid_treat_context'"'
    }

    capture confirm variable _pte_nt, exact
    if !_rc {
        _pte_validate_integer_state _pte_nt `"`_pte_resid_nt_context'"'
    }

    capture confirm variable _pte_D, exact
    if !_rc {
        _pte_validate_binary_state _pte_D `"`_pte_resid_D_context'"'
    }

    capture confirm variable _pte_mid, exact
    if !_rc {
        _pte_validate_binary_state _pte_mid `"`_pte_resid_mid_context'"'
    }

    local has_active_sample = 0
    capture confirm variable _pte_active_sample, exact
    if !_rc {
        capture confirm numeric variable _pte_active_sample
        if _rc {
            di as error "_pte_active_sample must be numeric when present."
            di as error "Re-run pte before predict, residuals."
            exit 111
        }
        local has_active_sample = 1
    }

    // _pte_eps0 is stored only on the support used for untreated innovations.
    local has_eps0 = 0
    capture confirm variable _pte_eps0, exact
    if !_rc {
        capture confirm numeric variable _pte_eps0
        if _rc {
            di as error "_pte_eps0 must be numeric."
            di as error "Re-run pte before predict, residuals, or rebuild _pte_eps0 from the live state."
            exit 111
        }
        local has_eps0 = 1
    }

    // When the stored eps0 values are absent, the support indicator remains
    // the authoritative boundary for which untreated innovations are defined.
    local has_eps0_ind = 0
    capture confirm variable _pte_eps0_ind, exact
    if !_rc {
        capture confirm numeric variable _pte_eps0_ind
        if _rc {
            di as error "_pte_eps0_ind must be numeric."
            di as error "Re-run pte before predict, residuals, or rebuild _pte_eps0_ind from the live state."
            exit 111
        }
        capture assert inlist(_pte_eps0_ind, 0, 1) if !missing(_pte_eps0_ind)
        if _rc {
            di as error "_pte_eps0_ind must be binary (0/1)."
            di as error "Re-run pte before predict, residuals, or rebuild _pte_eps0_ind from the live state."
            exit 450
        }
        local has_eps0_ind = 1
    }

    // A positive eps0window() means the innovation support was restricted to a
    // common untreated pre-treatment window at estimation time. If both the
    // stored eps0 values and the corresponding support indicator are gone,
    // residual fallback would leak outside the identified support.
    local eps0window = 0
    capture local eps0window = e(eps0window)
    if _rc != 0 | missing(`eps0window') {
        local eps0window = 0
    }
    if !`has_eps0' & !`has_eps0_ind' & `eps0window' > 0 {
        di as error "_pte_eps0_ind variable not found"
        di as error "predict, residuals cannot rebuild eps0 safely when eps0window()>0 and _pte_eps0 is unavailable"
        di as error "Re-run pte before predict, residuals, or keep _pte_eps0/_pte_eps0_ind in the current data"
        exit 111
    }

    // The fallback requires the stored untreated evolution coefficients.
    local grouped_by ""
    capture local grouped_by = e(by)
    if _rc == 0 & `"`grouped_by'"' == "." {
        local grouped_by ""
    }
    local grouped_labels `"`e(groups)'"'
    if `"`grouped_labels'"' == "." {
        local grouped_labels ""
    }
    local has_grouped_by = (`"`grouped_by'"' != "")
    local has_grouped_labels = (`"`grouped_labels'"' != "")
    local has_grouped_rho_payload = 0
    capture confirm matrix e(rho_by)
    if _rc == 0 {
        local has_grouped_rho_payload = 1
    }
    local has_grouped_rho = 0
    if `has_grouped_by' & `has_grouped_labels' & `has_grouped_rho_payload' {
        local has_grouped_rho = 1
    }

    // Grouped untreated-law rows cannot be mapped without the full grouped
    // route metadata. Falling back to serial rho_0 would silently rewrite a
    // grouped state into a pooled law, so fail closed unless exact eps0 cache
    // values remain available.
    if `has_grouped_rho_payload' & !`has_eps0' {
        if !`has_grouped_by' | !`has_grouped_labels' {
            di as error "Grouped residual fallback requires e(rho_by) together with e(by) and e(groups)."
            di as error "predict, residuals cannot fall back to serial rho_0 when grouped untreated-law payloads are active."
            di as error "Re-run grouped pte before predict, residuals, or keep _pte_eps0 in the current data."
            exit 301
        }
    }

    local p = e(omegapoly)
    local fallback_ready = 1
    local fallback_mode ""

    capture confirm variable _pte_omega, exact
    if _rc {
        local fallback_ready = 0
    }

    if `p' < 1 | `p' > 4 {
        local fallback_ready = 0
    }

    if `has_grouped_rho' {
        local fallback_mode "grouped"
    }
    else {
        capture matrix list e(rho_0)
        if _rc == 0 {
            local fallback_mode "serial"
        }
    }

    if "`fallback_mode'" == "" {
        local fallback_ready = 0
    }

    if !`fallback_ready' & !`has_eps0' {
        capture confirm variable _pte_omega, exact
        if _rc {
            di as error "_pte_omega variable not found"
            di as error "Cannot compute residuals without omega. Run pte first."
            exit 111
        }
        if `p' < 1 | `p' > 4 {
            di as error "Invalid omegapoly value: `p'. Must be 1-4."
            exit 198
        }
        if `"`grouped_by'"' != "" {
            di as error "Grouped residual fallback requires e(rho_by) or stored _pte_eps0."
            di as error "Re-run grouped pte before predict, residuals, or keep _pte_eps0 in the current data."
            exit 111
        }
        di as error "e(rho_0) matrix not found. Run pte first."
        exit 111
    }

    if `has_eps0' {
        // The stored eps0 cache is safe only when the exact support indicator
        // survives. _pte_active_sample is a wider productivity-recovery bridge and cannot
        // reconstruct the precise untreated-innovation support after cached
        // values go stale or the current data are subsetted.
        if !`has_eps0_ind' {
            di as error "_pte_eps0_ind variable not found"
            di as error "predict, residuals cannot validate stored _pte_eps0 safely when the exact untreated-support indicator is unavailable"
            di as error "Re-run pte before predict, residuals, or keep _pte_eps0_ind in the current data"
            exit 111
        }
        quietly gen `typlist' `varlist' = _pte_eps0 if `touse'
        quietly replace `varlist' = . if _pte_eps0_ind != 1 & `touse'
    }
    else if `fallback_ready' {
        if !`has_eps0_ind' & !`has_active_sample' {
            di as error "_pte_active_sample variable not found"
            di as error "predict, residuals cannot rebuild eps0 support safely when _pte_eps0_ind is unavailable"
            di as error "Re-run pte before predict, residuals, or keep _pte_eps0_ind/_pte_active_sample in the current data"
            exit 111
        }

        // Residual fallback must use the estimation panel structure stored by
        // pte, not whatever xtset happens to be active in the caller session.
        local pte_panel "`e(idvar)'"
        if `"`pte_panel'"' == "." {
            local pte_panel ""
        }
        if "`pte_panel'" == "" {
            local pte_panel "`e(id)'"
            if `"`pte_panel'"' == "." {
                local pte_panel ""
            }
        }
        local pte_time "`e(timevar)'"
        if `"`pte_time'"' == "." {
            local pte_time ""
        }
        if "`pte_time'" == "" {
            local pte_time "`e(time)'"
            if `"`pte_time'"' == "." {
                local pte_time ""
            }
        }
        local pte_delta ""
        tempname pte_delta_scalar
        capture scalar `pte_delta_scalar' = e(xtdelta)
        if _rc == 0 & !missing(`pte_delta_scalar') {
            local pte_delta = `pte_delta_scalar'
        }
        if "`pte_delta'" == "" & "`pte_setup_xtdelta'" != "" {
            local pte_delta "`pte_setup_xtdelta'"
        }

        if "`pte_panel'" == "" | "`pte_time'" == "" {
            di as error "Stored pte panel structure not found in e()."
            di as error "Re-run pte before predict, residuals."
            exit 301
        }

        local pte_setup_xtdelta_clean = strtrim(`"`pte_setup_xtdelta'"')
        local pte_delta_clean = strtrim(`"`pte_delta'"')
        local pte_delta_mismatch = 0
        if `"`pte_setup_xtdelta_clean'"' != "" & `"`pte_delta_clean'"' != "" {
            local pte_setup_xtdelta_num = real(`"`pte_setup_xtdelta_clean'"')
            local pte_delta_num = real(`"`pte_delta_clean'"')
            if !missing(`pte_setup_xtdelta_num') & !missing(`pte_delta_num') {
                if `pte_setup_xtdelta_num' != `pte_delta_num' {
                    local pte_delta_mismatch = 1
                }
            }
            else if `"`pte_setup_xtdelta_clean'"' != `"`pte_delta_clean'"' {
                local pte_delta_mismatch = 1
            }
        }

        if `pte_delta_mismatch' {
            di as error "predict, residuals detected a delta() mismatch between pte_setup and the live pte result"
            di as error "Re-run pte on the current setup-selected panel declaration before predict, residuals."
            exit 459
        }

        capture confirm variable `pte_panel', exact
        if _rc {
            di as error "Stored panel variable `pte_panel' not found in data."
            di as error "Re-run pte on the current dataset before predict, residuals."
            exit 111
        }

        capture confirm variable `pte_time', exact
        if _rc {
            di as error "Stored time variable `pte_time' not found in data."
            di as error "Re-run pte on the current dataset before predict, residuals."
            exit 111
        }

        // Legacy results may predate e(xtdelta). In that case, rebuild the
        // lag law from the exact current panel/time variables rather than
        // borrowing whatever ambient xtset spacing happens to be active.
        if "`pte_delta'" == "" {
            tempvar _pte_gap_probe
            quietly bysort `pte_panel' (`pte_time'): gen double `_pte_gap_probe' = ///
                `pte_time' - `pte_time'[_n-1] if _n > 1
            quietly count if !missing(`_pte_gap_probe')
            if r(N) > 0 {
                quietly summarize `_pte_gap_probe', meanonly
                if r(min) > 0 & abs(r(max) - r(min)) <= 1e-10 {
                    local pte_delta : display %21.0g r(min)
                    local pte_delta = strtrim("`pte_delta'")
                }
            }
        }

        if "`pte_delta'" == "" {
            di as error "predict, residuals could not certify a panel delta for lag-based fallback"
            di as error "Re-run pte on the current dataset, or re-run pte_setup so predict can certify the panel spacing before rebuilding residuals."
            exit 459
        }

        local had_xtset = 0
        local current_panel ""
        local current_time ""
        local current_delta ""
        capture quietly xtset
        if _rc == 0 {
            local had_xtset = 1
            local current_panel "`r(panelvar)'"
            local current_time "`r(timevar)'"
            local current_delta "`r(tdelta)'"
        }

        local restore_xtset = 0
        local pte_delta_mismatch = 0
        if "`pte_delta'" != "" & `had_xtset' == 1 ///
            & "`current_panel'" == "`pte_panel'" & "`current_time'" == "`pte_time'" ///
            & "`current_delta'" != "`pte_delta'" {
            local pte_delta_mismatch = 1
        }

        if `had_xtset' == 0 | "`current_panel'" != "`pte_panel'" | ///
            "`current_time'" != "`pte_time'" | `pte_delta_mismatch' {
            local pte_delta_opt ""
            if "`pte_delta'" != "" {
                local pte_delta_opt "delta(`pte_delta')"
            }
            capture quietly xtset `pte_panel' `pte_time', `pte_delta_opt'
            local _pte_predict_xtset_rc = _rc
            if `_pte_predict_xtset_rc' {
                di as error "predict, residuals could not restore xtset `pte_panel' `pte_time'."
                di as error "Ensure the current data still matches the last pte estimation sample."
                exit `_pte_predict_xtset_rc'
            }
            local restore_xtset = 1
        }

        // Project the untreated next-period component from lagged omega.
        // This branch temporarily restores the estimation-time xtset state;
        // any failure after that point must still unwind the caller session.
        tempvar omega_hat
        local fallback_rc = 0
        capture noisily {
            tempvar active_support
            quietly gen double `omega_hat' = . if `touse'
            quietly gen byte `active_support' = `touse'
            if `has_active_sample' {
                quietly replace `active_support' = ///
                    (`active_support' & _pte_active_sample == 1 & L._pte_active_sample == 1)
            }

            if "`fallback_mode'" == "serial" {
                tempname Rho
                matrix `Rho' = e(rho_0)

                quietly replace `omega_hat' = `Rho'[1,1] + `Rho'[1,2] * L._pte_omega if `active_support'
                if `p' >= 2 {
                    quietly replace `omega_hat' = `omega_hat' + `Rho'[1,3] * (L._pte_omega)^2 if `active_support'
                }
                if `p' >= 3 {
                    quietly replace `omega_hat' = `omega_hat' + `Rho'[1,4] * (L._pte_omega)^3 if `active_support'
                }
                if `p' >= 4 {
                    quietly replace `omega_hat' = `omega_hat' + `Rho'[1,5] * (L._pte_omega)^4 if `active_support'
                }
            }
            else if "`fallback_mode'" == "grouped" {
                capture confirm variable `grouped_by', exact
                if _rc {
                    di as error "[pte] grouped residual fallback requires the stored by() variable `grouped_by' in the current data"
                    di as error "[pte] Re-run grouped pte on the current dataset before predict, residuals."
                    exit 111
                }

                local grouped_by_numeric = 0
                capture confirm numeric variable `grouped_by'
                if _rc == 0 {
                    local grouped_by_numeric = 1
                }

                // The grouped untreated-law rows are identified by the
                // estimation-time group order stored in e(groups). Current
                // data may be a subset of those groups, so rebuilding the
                // row order from the live data would misalign e(rho_by).
                if `"`grouped_labels'"' == "" {
                    di as error "[pte] grouped residual fallback requires e(groups)"
                    di as error "[pte] Re-run grouped pte, by()/industry() to restore grouped metadata."
                    exit 301
                }

                tempname RhoBy
                matrix `RhoBy' = e(rho_by)
                if colsof(`RhoBy') != `p' + 1 {
                    di as error "[pte] grouped evolution matrix dimension mismatch with e(omegapoly)"
                    di as error "[pte] Expected colsof(e(rho_by))=" `p' + 1 ", got " colsof(`RhoBy')
                    exit 503
                }

                local g = 0
                // e(groups) already preserves embedded spaces as one token.
                // Re-wrapping the whole list breaks valid string labels like
                // "High tech" into malformed pseudo-tokens.
                local grouped_labels_work `"`grouped_labels'"'
                while `"`grouped_labels_work'"' != "" {
                    gettoken grp grouped_labels_work : grouped_labels_work, quotes
                    if `"`grp'"' == "" {
                        continue
                    }
                    local grp_value `"`grp'"'
                    local ++g
                    if `g' > rowsof(`RhoBy') {
                        di as error "[pte] e(groups) has more entries than grouped evolution rows"
                        di as error "[pte] groups parsed=" `g' " rowsof(e(rho_by))=" rowsof(`RhoBy')
                        exit 503
                    }

                    if `grouped_by_numeric' {
                        quietly replace `omega_hat' = el(`RhoBy', `g', 1) + ///
                            el(`RhoBy', `g', 2) * L._pte_omega if `grouped_by' == `grp_value' & `active_support'
                        if `p' >= 2 {
                            quietly replace `omega_hat' = `omega_hat' + ///
                                el(`RhoBy', `g', 3) * (L._pte_omega)^2 if `grouped_by' == `grp_value' & `active_support'
                        }
                        if `p' >= 3 {
                            quietly replace `omega_hat' = `omega_hat' + ///
                                el(`RhoBy', `g', 4) * (L._pte_omega)^3 if `grouped_by' == `grp_value' & `active_support'
                        }
                        if `p' >= 4 {
                            quietly replace `omega_hat' = `omega_hat' + ///
                                el(`RhoBy', `g', 5) * (L._pte_omega)^4 if `grouped_by' == `grp_value' & `active_support'
                        }
                    }
                    else {
                        // Stored e(groups) tokens keep the estimation-time row
                        // order. After re-wrapping the recovered e(groups)
                        // payload, grp_value is already a compound-quoted
                        // string literal and can be used directly.
                        quietly replace `omega_hat' = el(`RhoBy', `g', 1) + ///
                            el(`RhoBy', `g', 2) * L._pte_omega if `grouped_by' == `grp_value' & `active_support'
                        if `p' >= 2 {
                            quietly replace `omega_hat' = `omega_hat' + ///
                                el(`RhoBy', `g', 3) * (L._pte_omega)^2 if `grouped_by' == `grp_value' & `active_support'
                        }
                        if `p' >= 3 {
                            quietly replace `omega_hat' = `omega_hat' + ///
                                el(`RhoBy', `g', 4) * (L._pte_omega)^3 if `grouped_by' == `grp_value' & `active_support'
                        }
                        if `p' >= 4 {
                            quietly replace `omega_hat' = `omega_hat' + ///
                                el(`RhoBy', `g', 5) * (L._pte_omega)^4 if `grouped_by' == `grp_value' & `active_support'
                        }
                    }
                }

                if `g' != rowsof(`RhoBy') {
                    di as error "[pte] e(groups) count does not match grouped evolution rows"
                    di as error "[pte] groups parsed=" `g' " rowsof(e(rho_by))=" rowsof(`RhoBy')
                    exit 503
                }

                _pte_validate_group_route `grouped_by' `"`grouped_labels'"' `touse' "grouped residual fallback"
            }

            quietly gen `typlist' `varlist' = _pte_omega - `omega_hat' if `touse'
            if `has_eps0_ind' {
                quietly replace `varlist' = . if _pte_eps0_ind != 1 & `touse'
            }
            else if `has_active_sample' {
                quietly replace `varlist' = . if `active_support' != 1 & `touse'
            }
        }
        local fallback_rc = _rc

        if `restore_xtset' {
            if `had_xtset' {
                local restore_delta_opt ""
                if "`current_delta'" != "" {
                    local restore_delta_opt "delta(`current_delta')"
                }
                capture quietly xtset `current_panel' `current_time', `restore_delta_opt'
            }
            else {
                capture quietly xtset, clear
            }
        }

        if `fallback_rc' {
            capture drop `varlist'
            exit `fallback_rc'
        }
    }
    else {
        quietly gen `typlist' `varlist' = . if `touse'
    }

    // Post-entry treated observations are not draws from the untreated shock
    // law because realized omega already loads treatment effects there. Prefer
    // the precise event-time mask, then fall back to current D_it, then to the
    // ever-treated indicator when only that weaker support marker exists.
    capture confirm variable _pte_nt, exact
    local has_nt = (_rc == 0)
    capture confirm variable _pte_treat, exact
    local has_treat = (_rc == 0)
    capture confirm variable _pte_D, exact
    local has_currentD = (_rc == 0)
    if `has_nt' & `has_treat' {
        quietly replace `varlist' = . if _pte_treat == 1 ///
            & _pte_nt >= 0 & !missing(_pte_nt) & `touse'

        // Left-censored treated rows can carry missing event time even though
        // the current observation is already treated. Fall back row-by-row to
        // the live treatment state so treated observations never leak into the
        // untreated innovation support when _pte_nt is unavailable.
        if `has_currentD' {
            quietly replace `varlist' = . if missing(_pte_nt) ///
                & _pte_D == 1 & `touse'
        }
        else {
            quietly replace `varlist' = . if _pte_treat == 1 ///
                & missing(_pte_nt) & `touse'
        }
    }
    else if `has_currentD' {
        // Without event time, fall back to the realized treatment path.
        quietly replace `varlist' = . if _pte_D == 1 & `touse'
    }
    else if `has_treat' {
        // Last resort: mask all ever-treated observations.
        quietly replace `varlist' = . if _pte_treat == 1 & `touse'
    }

    // Transition periods are excluded from the production-function moments.
    capture confirm variable _pte_mid, exact
    if !_rc {
        quietly replace `varlist' = . if _pte_mid == 1
    }

    label variable `varlist' "Productivity shock epsilon from pte"
end


// TT exists only for treated observations on or after treatment entry.
capture program drop _pte_predict_tt
program define _pte_predict_tt
    args typlist varlist touse

    // TT is created only when the ATT stage runs.
    if e(noatt) == 1 {
        di as error "[pte] ATT estimation was skipped (noatt option specified)"
        di as error "[pte] Cannot predict tt without ATT estimation"
        di as error "[pte] Suggested fix: Re-run pte without the noatt option"
        exit 301
    }

    capture confirm variable _pte_tt, exact
    if _rc {
        di as error "[pte] _pte_tt variable not found"
        di as error "[pte] This may indicate an incomplete ATT estimation"
        exit 111
    }

    _pte_validate_numeric_state _pte_tt ///
        "predict, tt requires _pte_tt to remain the numeric firm-level TT bridge."

    // TT semantics require the treated-group and event-time masks.
    _pte_validate_binary_state _pte_treat ///
        "predict, tt requires _pte_treat to identify treated observations."

    _pte_validate_integer_state _pte_nt ///
        "predict, tt requires _pte_nt to identify post-treatment periods."

    // TT support must follow the stored ATT horizon exactly; stale _pte_tt
    // values outside e(attperiods) are not part of the identified TT path.
    capture matrix list e(attperiods)
    if _rc {
        di as error "[pte] e(attperiods) matrix not found in e()"
        di as error "[pte] predict, tt requires e(attperiods) to define the supported event times"
        exit 301
    }
    tempname tt_p
    matrix `tt_p' = e(attperiods)
    local tt_support_cols = colsof(`tt_p')
    quietly _pte_attperiods_support `tt_p' `tt_support_cols' "predict, tt"
    matrix `tt_p' = e(attperiods)

    // The exact supported TT horizon must remain realized in the stored
    // firm-time bridge. If an event time listed in e(attperiods) has no
    // nonmissing treated TT observations anywhere in the current dataset,
    // predict, tt would otherwise publish a partially empty certified path.
    forvalues j = 1/`tt_support_cols' {
        local period = el(`tt_p', 1, `j')
        quietly count if !missing(_pte_tt) & _pte_treat == 1 & _pte_nt == `period'
        if r(N) == 0 {
            di as error "[pte] supported TT period `period' has no nonmissing treated observations"
            di as error "[pte] predict, tt requires every event time listed in e(attperiods) to remain realized in the stored _pte_tt bridge"
            di as error "[pte] Re-run pte so e(attperiods) reflects realized TT support, or repair the damaged _pte_tt/_pte_nt bridge before prediction"
            exit 198
        }
    }

    quietly gen `typlist' `varlist' = . if `touse'
    forvalues j = 1/`tt_support_cols' {
        local period = el(`tt_p', 1, `j')
        quietly replace `varlist' = _pte_tt ///
            if _pte_treat == 1 & _pte_nt == `period' & `touse'
    }

    // TT is undefined for controls, treated pre-period observations, and
    // treated observations whose event time is unknown.
    quietly replace `varlist' = . if _pte_treat != 1
    quietly replace `varlist' = . if _pte_nt < 0
    quietly replace `varlist' = . if missing(_pte_nt)

    label variable `varlist' "Treatment effect on treated (TT)"

    // Emit diagnostics only in noisy mode.
    if c(noisily) {
        quietly count if !missing(`varlist') & `touse'
        local n_valid = r(N)

        local n_control = 0
        quietly count if missing(`varlist') & `touse' & _pte_treat == 0
        local n_control = r(N)

        local n_pre = 0
        quietly count if missing(`varlist') & `touse' ///
            & _pte_treat == 1 & _pte_nt < 0
        local n_pre = r(N)

        local n_unknown = 0
        quietly count if missing(`varlist') & `touse' ///
            & _pte_treat == 1 & missing(_pte_nt)
        local n_unknown = r(N)

        quietly summ `varlist' if `touse'
        local tt_min = r(min)
        local tt_max = r(max)
        local tt_mean = r(mean)

        di as text ""
        di as text "{hline 50}"
        di as text "predict, tt: Treatment effect on treated"
        di as text "{hline 50}"
        di as text "  Valid TT observations:     " %9.0f `n_valid'
        if `n_control' > 0 {
            di as text "  Missing (control group):   " %9.0f `n_control'
        }
        if `n_pre' > 0 {
            di as text "  Missing (pre-treatment):   " %9.0f `n_pre'
        }
        if `n_unknown' > 0 {
            di as text "  Missing (unknown nt):      " %9.0f `n_unknown'
        }
        if !missing(`tt_min') {
            di as text "  TT range:                  [" ///
                %9.4f `tt_min' ", " %9.4f `tt_max' "]"
            di as text "  TT mean:                   " %9.6f `tt_mean'
        }
        di as text "{hline 50}"
    }
end


// Map stored event-time ATT estimates back to treated observations. The final
// e(att) column is the pooled ATT summary and has no observation-level target.
capture program drop _pte_predict_att
program define _pte_predict_att
    args typlist varlist touse

    // Observation-level ATT predictions require the ATT stage.
    if e(noatt) == 1 {
        di as error "[pte] ATT estimation was skipped (noatt option specified)"
        di as error "[pte] Cannot predict att without ATT estimation"
        di as error "[pte] Suggested fix: Re-run pte without the noatt option"
        exit 301
    }

    // Event time is the index used to align rows with e(attperiods).
    _pte_validate_integer_state _pte_nt ///
        "predict, att requires _pte_nt to supply the event-time index."

    // ATT predictions are defined only for treated observations.
    _pte_validate_binary_state _pte_treat ///
        "predict, att requires _pte_treat to identify treated observations."

    local grouped_by ""
    capture local grouped_by = e(by)
    if _rc == 0 & `"`grouped_by'"' == "." {
        local grouped_by ""
    }
    local grouped_labels `"`e(groups)'"'
    if `"`grouped_labels'"' == "." {
        local grouped_labels ""
    }
    local has_grouped_by = (`"`grouped_by'"' != "")
    local has_grouped_labels = (`"`grouped_labels'"' != "")
    quietly _pte_has_grouped_att_payload
    local has_grouped_att_family = r(has_grouped_att)
    local grouped_att_payloads `"`r(grouped_payloads)'"'
    local has_grouped_att_payload = 0
    local grouped_att_mat "att_by"
    capture confirm matrix e(att_by)
    if _rc == 0 {
        local has_grouped_att_payload = 1
    }
    else {
        capture confirm matrix e(att_by_point)
        if _rc == 0 {
            local has_grouped_att_payload = 1
            local grouped_att_mat "att_by_point"
        }
    }
    local has_grouped_att = 0
    if `has_grouped_by' & `has_grouped_labels' & `has_grouped_att_payload' {
        local has_grouped_att = 1
    }
    if `has_grouped_att_family' & !`has_grouped_att_payload' {
        if !`has_grouped_by' | !`has_grouped_labels' {
            di as error "[pte] grouped ATT payloads remain active but e(by) and e(groups) are incomplete"
            if `"`grouped_att_payloads'"' != "" {
                di as error "[pte] detected grouped payload(s): `macval(grouped_att_payloads)'"
            }
            di as error "[pte] grouped bootstrap/postestimation results cannot be mapped from pooled e(att) alone"
            di as error "[pte] Re-run grouped pte, by()/industry() to restore e(att_by)/e(att_by_point) together with grouped route metadata"
            exit 301
        }
        di as error "[pte] grouped ATT payloads remain active but e(att_by) / e(att_by_point) are unavailable"
        if `"`grouped_att_payloads'"' != "" {
            di as error "[pte] detected grouped payload(s): `macval(grouped_att_payloads)'"
        }
        di as error "[pte] grouped bootstrap/postestimation results cannot be mapped from pooled e(att) alone"
        di as error "[pte] Re-run grouped pte, by()/industry() to restore grouped point-mapping payloads"
        exit 301
    }
    if `has_grouped_att_payload' & (!`has_grouped_by' | !`has_grouped_labels') {
        di as error "[pte] grouped ATT mapping requires e(att_by) or e(att_by_point) together with e(by) and e(groups)"
        di as error "[pte] grouped results cannot be mapped from pooled e(att) alone"
        di as error "[pte] Re-run grouped pte, by()/industry() to restore grouped ATT route metadata"
        exit 301
    }
    if `has_grouped_by' & !`has_grouped_att' {
        di as error "[pte] grouped ATT mapping requires e(att_by) or e(att_by_point)"
        di as error "[pte] grouped results cannot be mapped from pooled e(att) alone"
        di as error "[pte] Re-run pte, by()/industry() to restore grouped ATT payloads"
        exit 301
    }

    // Read the stored event-time support from e(attperiods); do not infer it
    // from display macros because row-level mapping must follow the matrix.
    capture matrix list e(attperiods)
    if _rc {
        di as error "[pte] e(attperiods) matrix not found in e()"
        di as error "[pte] predict, att requires e(attperiods) to be a 1×(L+1) matrix"
        exit 301
    }
    tempname att_p att_mat
    matrix `att_p' = e(attperiods)
    local att_support_cols = colsof(`att_p')
    quietly _pte_attperiods_support `att_p' `att_support_cols' "predict, att"
    matrix `att_p' = e(attperiods)

    // The stored event-time support must remain realized in the current
    // treated bridge. Otherwise predict, att would silently publish a partial
    // observation-level path after the current data dropped or damaged one of
    // the supported ATT periods.
    forvalues j = 1/`att_support_cols' {
        local period = el(`att_p', 1, `j')
        quietly count if _pte_treat == 1 & _pte_nt == `period'
        if r(N) == 0 {
            di as error "[pte] supported ATT period `period' has no treated observations in the current data"
            di as error "[pte] predict, att requires every event time listed in e(attperiods) to remain realized in the stored _pte_nt/_pte_treat bridge"
            di as error "[pte] Re-run pte so e(attperiods) reflects realized ATT support, or repair the damaged current data before prediction"
            exit 198
        }
    }

    if `has_grouped_att' {
        tempname att_by_mat
        matrix `att_by_mat' = e(`grouped_att_mat')
        if colsof(`att_by_mat') != `att_support_cols' + 1 {
            di as error "[pte] grouped ATT matrix dimension mismatch with e(attperiods)"
            di as error "[pte] Expected colsof(e(`grouped_att_mat'))=" ///
                `att_support_cols' + 1 ", got " colsof(`att_by_mat')
            di as error "[pte] e(attperiods) colsof=" `att_support_cols'
            exit 503
        }
        quietly _pte_dynamic_colstripe_contract `att_by_mat' `att_p' ///
            `att_support_cols' "predict, att" "e(`grouped_att_mat')"

        capture confirm variable `grouped_by', exact
        if _rc {
            di as error "[pte] grouped ATT mapping requires the stored by() variable `grouped_by' in the current data"
            di as error "[pte] Re-run pte on the current dataset or restore variable `grouped_by'"
            exit 111
        }

        if `"`grouped_labels'"' == "" {
            di as error "[pte] grouped ATT mapping requires e(groups)"
            di as error "[pte] Re-run pte, by()/industry() to restore grouped metadata"
            exit 301
        }

        local grouped_by_numeric = 0
        capture confirm numeric variable `grouped_by'
        if _rc == 0 {
            local grouped_by_numeric = 1
        }

        local g = 0
        // Consume the stored group-label token list exactly as published by
        // the grouped producer. The tokenization itself already preserves
        // embedded spaces for string labels.
        local grouped_labels_work `"`grouped_labels'"'
        while `"`grouped_labels_work'"' != "" {
            gettoken grp grouped_labels_work : grouped_labels_work, quotes
            if `"`grp'"' == "" {
                continue
            }
            local ++g
            if `g' > rowsof(`att_by_mat') {
                di as error "[pte] e(groups) has more entries than grouped ATT rows"
                di as error "[pte] groups parsed=" `g' " rowsof(e(`grouped_att_mat'))=" rowsof(`att_by_mat')
                exit 503
            }
        }

        if `g' != rowsof(`att_by_mat') {
            di as error "[pte] e(groups) count does not match grouped ATT rows"
            di as error "[pte] groups parsed=" `g' " rowsof(e(`grouped_att_mat'))=" rowsof(`att_by_mat')
            exit 503
        }

        scalar __pte_grouped_att_missing = 0
        forvalues g = 1/`=rowsof(`att_by_mat')' {
            forvalues j = 1/`att_support_cols' {
                if missing(el(`att_by_mat', `g', `j')) {
                    scalar __pte_grouped_att_missing = 1
                    continue, break
                }
            }
            if scalar(__pte_grouped_att_missing) {
                continue, break
            }
        }
        if scalar(__pte_grouped_att_missing) {
            di as error "[pte] grouped ATT point estimates are incomplete on e(attperiods)"
            di as error "[pte] every supported event time in e(attperiods) must have a nonmissing grouped ATT value"
            capture scalar drop __pte_grouped_att_missing
            exit 198
        }
        capture scalar drop __pte_grouped_att_missing

        _pte_validate_group_route `grouped_by' `"`grouped_labels'"' `touse' "grouped ATT mapping"

        // Start with missing and fill only supported treated event times.
        quietly gen `typlist' `varlist' = . if `touse'
        local g = 0
        local grouped_labels_work `"`grouped_labels'"'
        while `"`grouped_labels_work'"' != "" {
            gettoken grp grouped_labels_work : grouped_labels_work, quotes
            if `"`grp'"' == "" {
                continue
            }
            local grp_value `"`grp'"'
            local ++g
            forvalues j = 1/`att_support_cols' {
                local period = el(`att_p', 1, `j')
                if `grouped_by_numeric' {
                    quietly replace `varlist' = el(`att_by_mat', `g', `j') ///
                        if `grouped_by' == `grp_value' & _pte_nt == `period' ///
                        & _pte_treat == 1 & `touse'
                }
                else {
                    quietly replace `varlist' = el(`att_by_mat', `g', `j') ///
                        if `grouped_by' == `grp_value' & _pte_nt == `period' ///
                        & _pte_treat == 1 & `touse'
                }
            }
        }
    }
    else {
        // e(att) stores the event-time effects plus the overall ATT summary.
        capture matrix list e(att)
        if _rc {
            di as error "[pte] ATT estimates not found in e()"
            di as error "[pte] This may occur if estimates were cleared"
            di as error "[pte] Re-run pte to regenerate estimates"
            exit 301
        }

        // One ATT coefficient per event time plus one pooled ATT summary column.
        tempname att_mat
        matrix `att_mat' = e(att)
        if rowsof(`att_mat') != 1 {
            di as error "[pte] e(att) must be a row vector (1×(K+1))"
            di as error "[pte] Dimension diagnostic: rowsof=" ///
                rowsof(`att_mat') " colsof=" colsof(`att_mat')
            exit 503
        }
        if colsof(`att_mat') != `att_support_cols' + 1 {
            di as error "[pte] e(att) dimension mismatch with e(attperiods)"
            di as error "[pte] Expected colsof(e(att))=" ///
                `att_support_cols' + 1 ", got " colsof(`att_mat')
            di as error "[pte] e(attperiods) colsof=" `att_support_cols'
            exit 503
        }
        quietly _pte_dynamic_colstripe_contract `att_mat' `att_p' ///
            `att_support_cols' "predict, att" "e(att)"

        forvalues j = 1/`att_support_cols' {
            if missing(el(`att_mat', 1, `j')) {
                di as error "[pte] ATT point estimates are incomplete on e(attperiods)"
                di as error "[pte] every supported event time in e(attperiods) must have a nonmissing ATT value"
                exit 198
            }
        }

        // Start with missing and fill only supported treated event times.
        quietly gen `typlist' `varlist' = . if `touse'

        // The pooled ATT column is intentionally excluded from row-level output.
        forvalues j = 1/`att_support_cols' {
            local period = el(`att_p', 1, `j')
            quietly replace `varlist' = el(`att_mat', 1, `j') ///
                if _pte_nt == `period' & _pte_treat == 1 & `touse'
        }
    }

    label variable `varlist' "Average treatment effect on treated"

    // Emit diagnostics only in noisy mode.
    if c(noisily) {
        quietly count if !missing(`varlist') & `touse'
        local n_valid = r(N)
        quietly count if missing(`varlist') & `touse'
        local n_missing = r(N)

        // Controls can share event-time labels but never receive ATT values.
        local n_ctrl_excl = 0
        forvalues j = 1/`att_support_cols' {
            local period = el(`att_p', 1, `j')
            quietly count if _pte_nt == `period' & _pte_treat != 1 & `touse'
            local n_ctrl_excl = `n_ctrl_excl' + r(N)
        }

        // Pre-treatment treated observations are outside the ATT support.
        local n_pre = 0
        quietly count if _pte_treat == 1 & _pte_nt < 0 & `touse'
        local n_pre = r(N)

        // Display the event-time support exactly as stored in e(attperiods).
        local attperiods_list ""
        forvalues j = 1/`att_support_cols' {
            local _p = el(`att_p', 1, `j')
            local attperiods_list "`attperiods_list' `_p'"
        }
        local attperiods_list = trim("`attperiods_list'")

        di as text ""
        di as text "{hline 50}"
        di as text "predict, att: Average treatment effect on treated"
        di as text "{hline 50}"
        di as text "  ATT periods:               `attperiods_list'"
        di as text "  Valid ATT observations:    " %9.0f `n_valid'
        di as text "  Missing (outside window):  " %9.0f `n_missing'
        if `n_ctrl_excl' > 0 {
            di as text "  Control obs excluded:      " %9.0f `n_ctrl_excl'
        }
        if `n_pre' > 0 {
            di as text "  Treated pre-treatment:     " %9.0f `n_pre'
        }
        di as text "{hline 50}"
    }
end

// Exponentiate log productivity to recover the level index.
capture program drop _pte_predict_exponential
program define _pte_predict_exponential
    args typlist varlist touse

    capture confirm variable _pte_omega, exact
    if _rc {
        di as error "_pte_omega variable not found"
        di as error "Run pte before predict"
        exit 111
    }
    capture confirm numeric variable _pte_omega
    if _rc {
        di as error "_pte_omega must be numeric."
        di as error "Re-run pte before predict, exponential, or rebuild _pte_omega from the live state."
        exit 111
    }

    quietly gen `typlist' `varlist' = exp(_pte_omega) if `touse'
    label variable `varlist' "Productivity level exp(omega) from pte"
end


// Display stored production-function coefficients without generating output.
capture program drop _pte_predict_parameters
program define _pte_predict_parameters

    local grouped_by ""
    local has_grouped_by = 0
    capture local grouped_by = e(by)
    if _rc == 0 & `"`grouped_by'"' == "." {
        local grouped_by ""
    }
    if _rc == 0 & `"`grouped_by'"' != "" {
        local has_grouped_by = 1
    }
    local grouped_labels ""
    local has_grouped_labels = 0
    capture local grouped_labels = e(groups)
    if _rc == 0 & `"`grouped_labels'"' != "" & `"`grouped_labels'"' != "." {
        local has_grouped_labels = 1
    }
    local has_grouped_point = 0
    capture confirm matrix e(b_by)
    if _rc == 0 local has_grouped_point = 1
    local has_grouped_aux = 0
    foreach grouped_mat in rho_by sigma_by N_by N_firms_by att_by att_by_point {
        capture confirm matrix e(`grouped_mat')
        if _rc == 0 local has_grouped_aux = 1
    }
    capture scalar _pte_grouped_n = e(n_groups)
    if _rc == 0 & !missing(_pte_grouped_n) local has_grouped_aux = 1
    capture scalar drop _pte_grouped_n
    capture scalar _pte_grouped_ng = e(ngroups)
    if _rc == 0 & !missing(_pte_grouped_ng) local has_grouped_aux = 1
    capture scalar drop _pte_grouped_ng
    local has_grouped_context = `has_grouped_by' | `has_grouped_labels' | `has_grouped_aux'

    quietly _pte_has_grouped_beta_payload
    local has_grouped_boot = r(has_grouped_beta)

    // Grouped bootstrap stores coefficient draws, not one public point vector.
    // The draw payload itself is enough to make observation-free parameter
    // display ambiguous; if grouped route metadata has drifted away, fail
    // closed rather than silently falling back to serial e(beta_*) scalars.
    if `has_grouped_boot' {
        di as error "predict, parameters is not available after grouped bootstrap pte results."
        di as error "Grouped bootstrap stores coefficient draws, not one public point-estimate matrix."
        di as error "Inspect e(beta_boot_g#) and e(beta_se_g#) for grouped bootstrap coefficient summaries."
        exit 198
    }

    // Grouped point estimation publishes e(b_by) as the public coefficient
    // matrix. This reporting-only path does not map rows back to
    // observations, so e(by)/e(groups) are optional echo metadata rather
    // than prerequisites for consuming the live grouped point surface. Guard
    // grouped bootstrap first because stale e(b_by) payloads must not
    // override the coefficient-draw contract.
    if `has_grouped_point' {
        _pte_predict_parameters_bygroup
        exit
    }

    // Grouped point estimation is publicly identified by e(b_by). If
    // grouped auxiliary payloads survive without that coefficient surface,
    // falling back to serial beta_* scalars would silently collapse a
    // grouped state into pooled parameters.
    if `has_grouped_context' {
        di as error "predict, parameters requires e(b_by) when grouped point-estimate payloads are active."
        di as error "Current e() results still contain grouped by()/industry() state but no public grouped coefficient matrix."
        di as error "Re-run grouped pte to restore e(b_by), or clear the stale grouped replay payload before reporting parameters."
        exit 301
    }

    if "`e(PFtype)'" == "Cobb-Douglas" {
        di as text ""
        di as text "{hline 50}"
        di as text "Cobb-Douglas Production Function Parameters"
        di as text "{hline 50}"
        di as text "  beta_l (free):   " as result %9.6f e(beta_l)
        di as text "  beta_k (state):  " as result %9.6f e(beta_k)
        _pte_predict_parameters_controls
        di as text ""
        di as text "  Returns to scale:" as result %9.6f (e(beta_l) + e(beta_k))
        di as text "{hline 50}"
    }
    else if "`e(PFtype)'" == "translog" {
        di as text ""
        di as text "{hline 50}"
        di as text "Translog Production Function Parameters"
        di as text "{hline 50}"
        di as text "  beta_l  (free):      " as result %9.6f e(beta_l)
        di as text "  beta_k  (state):     " as result %9.6f e(beta_k)
        di as text "  beta_ll (free^2):    " as result %9.6f e(beta_ll)
        di as text "  beta_kk (state^2):   " as result %9.6f e(beta_kk)
        di as text "  beta_lk (free*state):" as result %9.6f e(beta_lk)
        _pte_predict_parameters_controls
        di as text "{hline 50}"
        di as text ""
        di as text "  Output elasticity w.r.t. free (at mean):"
        di as text "    e_l = beta_l + 2*beta_ll*l_bar + beta_lk*k_bar"
        di as text ""
        di as text "  Output elasticity w.r.t. state (at mean):"
        di as text "    e_k = beta_k + 2*beta_kk*k_bar + beta_lk*l_bar"
        di as text "{hline 50}"
    }
    else {
        di as error "Unknown production function type: `e(PFtype)'"
        exit 198
    }
end

capture program drop _pte_predict_parameters_controls
program define _pte_predict_parameters_controls
    tempname Bctrl

    capture matrix `Bctrl' = e(beta_controls)
    if _rc != 0 {
        exit
    }

    local n_ctrl = colsof(`Bctrl')
    if `n_ctrl' <= 0 {
        exit
    }

    local ctrl_names : colnames `Bctrl'
    if `"`ctrl_names'"' == "" {
        forvalues j = 1/`n_ctrl' {
            local ctrl_names "`ctrl_names' control_`j'"
        }
    }

    if `n_ctrl' == 1 {
        capture scalar _pte_beta_t = e(beta_t)
        if _rc == 0 {
            local ctrl_name : word 1 of `ctrl_names'
            di as text "  beta_t (`ctrl_name'): " as result %9.6f _pte_beta_t
            capture scalar drop _pte_beta_t
            exit
        }
    }

    di as text ""
    di as text "  Control coefficients:"
    forvalues j = 1/`n_ctrl' {
        local ctrl_name : word `j' of `ctrl_names'
        local ctrl_val = `Bctrl'[1, `j']
        di as text "    `ctrl_name':" as result %16.6f `ctrl_val'
    }
end


// Display the grouped point-estimate coefficient matrix published by the
// public by()/industry() path. This keeps the postestimation contract aligned
// with the grouped e() surface instead of rejecting a valid public result.
capture program drop _pte_predict_parameters_bygroup
program define _pte_predict_parameters_bygroup
    tempname B

    matrix `B' = e(b_by)
    local b_rows = rowsof(`B')

    local grouped_by ""
    capture local grouped_by = e(by)
    if _rc == 0 & `"`grouped_by'"' == "." {
        local grouped_by ""
    }

    local groups ""
    capture local groups = e(groups)
    if _rc == 0 & `"`groups'"' == "." {
        local groups ""
    }

    local group_count = .
    if `"`groups'"' != "" {
        local groups_work `"`groups'"'
        local group_count = 0
        while `"`groups_work'"' != "" {
            gettoken grp groups_work : groups_work, quotes
            if `"`grp'"' == "" {
                continue
            }
            local group_count = `group_count' + 1
        }
        if `group_count' != `b_rows' {
            di as error "e(groups) count does not match grouped coefficient rows"
            di as error "groups parsed = `group_count'; rowsof(e(b_by)) = `b_rows'"
            exit 503
        }
    }

    capture scalar _pte_group_n = e(n_groups)
    if _rc == 0 & !missing(_pte_group_n) & _pte_group_n != `b_rows' {
        di as error "e(n_groups) does not match grouped coefficient rows"
        di as error "e(n_groups) = " %12.0f _pte_group_n "; rowsof(e(b_by)) = `b_rows'"
        capture scalar drop _pte_group_n
        exit 503
    }
    capture scalar drop _pte_group_n

    capture scalar _pte_group_ng = e(ngroups)
    if _rc == 0 & !missing(_pte_group_ng) & _pte_group_ng != `b_rows' {
        di as error "e(ngroups) does not match grouped coefficient rows"
        di as error "e(ngroups) = " %12.0f _pte_group_ng "; rowsof(e(b_by)) = `b_rows'"
        capture scalar drop _pte_group_ng
        exit 503
    }
    capture scalar drop _pte_group_ng

    di as text ""
    di as text "{hline 78}"
    di as text "By-group Production Function Parameters"
    di as text "{hline 78}"
    if `"`grouped_by'"' != "" {
        di as text "  Grouping variable:   " as result "`grouped_by'"
    }
    if `"`e(PFtype)'"' != "" {
        di as text "  Production function: " as result "`e(PFtype)'"
    }
    if `"`groups'"' != "" {
        di as text "  Group labels:        " as result "stored in e(groups)"
    }
    di as text ""
    matrix list `B'
    di as text "{hline 78}"
end
