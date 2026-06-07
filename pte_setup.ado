*! pte_setup.ado
*! Prepare panel metadata and treatment-path diagnostics for public PTE workflows.

version 14.0
capture program drop pte_setup
program define pte_setup, rclass sortpreserve
    version 14.0

    syntax , TREATment(name) ///
        [FIRMid(name) TIMEvar(name) CHECK ABSorbing REPort ///
         GENerate(string) REPLACE OUTput(string) FREE(string) ///
         STATe(string) PROXy(string) MINTHreshold(integer 100)]

    // Public setup must bind treatment() to the exact D_t column. Allowing
    // abbreviation expansion here can silently switch the audited treatment
    // path before any helper variables are generated.
    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "pte_setup: variable `treatment' not found"
        exit 111
    }
    // Reject nonnumeric treatment variables before any panel setup or helper
    // generation side effects occur.
    capture confirm numeric variable `treatment'
    if _rc != 0 {
        di as error "pte_setup: treatment() must be a numeric 0/1 variable"
        di as error "  Specified: treatment(`treatment')"
        exit 198
    }

    quietly count if !missing(`treatment')
    if r(N) == 0 {
        di as error "pte_setup: treatment() is all missing"
        di as error "  treatment() must contain at least one nonmissing 0/1 observation"
        exit 416
    }

    // Public setup may need a temporary panel declaration even when the
    // caller started without xtset. Preserve the entry contract so helper
    // generation, diagnostics, and failure branches can restore the exact
    // ambient state instead of leaking the setup axis.
    local pte_orig_had_xtset 0
    local pte_orig_panel ""
    local pte_orig_time ""
    local pte_orig_delta ""
    capture quietly xtset
    if _rc == 0 {
        local pte_orig_had_xtset 1
        local pte_orig_panel "`r(panelvar)'"
        local pte_orig_time "`r(timevar)'"
        local pte_orig_delta "`r(tdelta)'"
    }

    // check mode is documented as non-mutating, so preserve the caller's
    // xtset state even when the setup helpers need a temporary panel context.
    local pte_check_had_xtset 0
    local pte_check_prev_panel ""
    local pte_check_prev_time ""
    local pte_check_prev_delta ""
    if "`check'" != "" {
        capture quietly xtset
        if _rc == 0 {
            local pte_check_had_xtset 1
            local pte_check_prev_panel "`r(panelvar)'"
            local pte_check_prev_time "`r(timevar)'"
            local pte_check_prev_delta "`r(tdelta)'"
        }
    }

    if `minthreshold' < 0 {
        di as error "pte_setup: minthreshold() must be nonnegative"
        di as error "  Specified: minthreshold(`minthreshold')"
        exit 198
    }

    // Panel overrides define the structural i,t axes used downstream for
    // transition timing and cohort construction, so the public contract must
    // not silently expand abbreviations to shadow columns.
    if "`firmid'" != "" {
        capture confirm variable `firmid', exact
        if _rc != 0 {
            di as error "pte_setup: variable `firmid' not found"
            di as error "  firmid() must match an existing panel id column exactly"
            exit 111
        }
    }
    if "`timevar'" != "" {
        capture confirm variable `timevar', exact
        if _rc != 0 {
            di as error "pte_setup: variable `timevar' not found"
            di as error "  timevar() must match an existing time column exactly"
            exit 111
        }
    }

    // Public input-role validation is an audit surface, so it must preserve
    // the caller's literal variable names until exact-name checks run here.
    _pte_setup_confirm_exact_list, role(output) vars(`"`output'"') single
    local output `"`r(vars)'"'
    _pte_setup_confirm_exact_list, role(free) vars(`"`free'"')
    local free `"`r(vars)'"'
    _pte_setup_confirm_exact_list, role(state) vars(`"`state'"')
    local state `"`r(vars)'"'
    _pte_setup_confirm_exact_list, role(proxy) vars(`"`proxy'"')
    local proxy `"`r(vars)'"'

    // Downstream helpers assume the canonical _pte_* workspace variables.
    // Restrict generate() to that namespace to avoid partial renaming.
    if "`generate'" != "" {
        local generate_clean = trim("`generate'")
        if !inlist("`generate_clean'", "_pte_", "_pte") {
            di as error "pte_setup: generate() currently supports only the default _pte_ prefix"
            di as error "  Specified: `generate'"
            exit 198
        }
    }

    // Numeric input-role admissibility is a public contract independent of
    // panel setup, so reject string candidates before xtset()/id()/time()
    // requirements can mask the caller's actual option error.
    foreach _pte_role in output free state proxy {
        local _pte_role_vars ``_pte_role''
        if `"`_pte_role_vars'"' == "" {
            continue
        }
        foreach _pte_var of local _pte_role_vars {
            capture confirm numeric variable `_pte_var'
            if _rc != 0 {
                di as error "pte_setup: variable `_pte_var' is not numeric"
                di as error "  `_pte_role'() requires existing numeric variable(s)"
                exit 109
            }
        }
    }

    // Forward only the options that resolve panel structure here.
    local panel_opts ""
    if "`firmid'" != "" {
        local panel_opts "`panel_opts' id(`firmid')"
    }
    if "`timevar'" != "" {
        local panel_opts "`panel_opts' time(`timevar')"
    }
    if "`report'" != "" {
        local panel_opts "`panel_opts' verbose"
    }

    if "`check'" != "" {
        capture quietly _pte_setup_panel, treatment(`treatment') `panel_opts'
        local pte_setup_panel_rc = _rc
        if `pte_setup_panel_rc' != 0 {
            if `pte_check_had_xtset' {
                local pte_check_restore_delta_opt ""
                if "`pte_check_prev_delta'" != "" {
                    local pte_check_restore_delta_opt "delta(`pte_check_prev_delta')"
                }
                capture quietly xtset `pte_check_prev_panel' `pte_check_prev_time', `pte_check_restore_delta_opt'
            }
            else {
                capture quietly xtset, clear
            }
            exit `pte_setup_panel_rc'
        }
    }
    else {
        quietly _pte_setup_panel, treatment(`treatment') `panel_opts'
    }
    local panelvar "`r(panelvar)'"
    local timevar_resolved "`r(timevar)'"
    local panel_delta "`r(tdelta)'"
    local balanced = r(balanced)
    local regular = r(regular)
    local n_obs = r(n_obs)
    local n_groups = r(n_groups)

    // Variable-role validation is optional because pte_setup also serves as a
    // treatment-path audit before the production-function inputs are finalized.
    if "`output'`free'`state'`proxy'" != "" {
        if "`check'" != "" {
            capture noisily _pte_setup_validate_inputs, output(`output') free(`free') state(`state') proxy(`proxy')
            local pte_validate_rc = _rc
            if `pte_validate_rc' != 0 {
                if `pte_check_had_xtset' {
                    local pte_check_restore_delta_opt ""
                    if "`pte_check_prev_delta'" != "" {
                        local pte_check_restore_delta_opt "delta(`pte_check_prev_delta')"
                    }
                    capture quietly xtset `pte_check_prev_panel' `pte_check_prev_time', `pte_check_restore_delta_opt'
                }
                else {
                    capture quietly xtset, clear
                }
                exit `pte_validate_rc'
            }
        }
        else {
            capture noisily _pte_setup_validate_inputs, output(`output') free(`free') state(`state') proxy(`proxy')
            local pte_validate_rc = _rc
            if `pte_validate_rc' != 0 {
                if `pte_orig_had_xtset' {
                    local pte_orig_restore_delta_opt ""
                    if "`pte_orig_delta'" != "" {
                        local pte_orig_restore_delta_opt "delta(`pte_orig_delta')"
                    }
                    capture quietly xtset `pte_orig_panel' `pte_orig_time', `pte_orig_restore_delta_opt'
                }
                else {
                    capture quietly xtset, clear
                }
                exit `pte_validate_rc'
            }
        }
        local input_validation_passed = r(validation_passed)
        local total_invalid_inputs = r(total_invalid)
        local total_nonpos = r(total_nonpos)
        local total_miss = r(total_miss)
        local n_invalid_obs = r(n_invalid_obs)
    }
    else {
        local input_validation_passed = .
        local total_invalid_inputs = .
        local total_nonpos = .
        local total_miss = .
        local n_invalid_obs = .
    }

    // Rebuilding setup helpers under the same treatment() variable name can
    // still imply a different treatment law if the caller rewired the column
    // contents. Snapshot the existing helper bundle before regeneration so we
    // can clear stale pte e() results when the rebuilt law drifts.
    local pte_prev_helper_snapshot 0
    local pte_prev_helper_complete 1
    local pte_prev_helper_changed 0
    local pte_prev_helper_vars "_pte_treat _pte_mid _pte_cohort _pte_treat_year _pte_nt _pte_first_treat_year _pte_D"
    local pte_prev_helper_keys "treat mid cohort treatyear nt firstyear D"
    local pte_prev_helper_n : word count `pte_prev_helper_vars'
    forvalues _pte_i = 1/`pte_prev_helper_n' {
        local _pte_key : word `_pte_i' of `pte_prev_helper_keys'
        local pte_has_prev_`_pte_key' 0
    }
    if "`check'" == "" {
        forvalues _pte_i = 1/`pte_prev_helper_n' {
            local _pte_helper : word `_pte_i' of `pte_prev_helper_vars'
            local _pte_key : word `_pte_i' of `pte_prev_helper_keys'
            capture confirm variable `_pte_helper', exact
            if _rc == 0 {
                tempvar pte_prev_`_pte_key'
                quietly clonevar `pte_prev_`_pte_key'' = `_pte_helper'
                local pte_has_prev_`_pte_key' 1
                local pte_prev_helper_snapshot 1
            }
            else {
                local pte_prev_helper_complete 0
            }
        }
    }

    // check mode suppresses helper-variable creation so the audit can run
    // without mutating the caller's dataset.
    local verify_opts "panelvar(`panelvar') timevar(`timevar_resolved')"
    if "`panel_delta'" != "" {
        local verify_opts "`verify_opts' delta(`panel_delta')"
    }
    if "`replace'" != "" {
        local verify_opts "`verify_opts' replace"
    }
    if "`absorbing'" != "" {
        local verify_opts "`verify_opts' strict"
    }
    if "`check'" != "" {
        local verify_opts "`verify_opts' nogenerate"
    }
    if "`report'" != "" {
        local verify_opts "`verify_opts' verbose"
    }

    if "`check'" != "" {
        capture noisily _pte_verify_treatment `treatment', `verify_opts'
        local pte_verify_rc = _rc
        if `pte_verify_rc' != 0 {
            if `pte_check_had_xtset' {
                local pte_check_restore_delta_opt ""
                if "`pte_check_prev_delta'" != "" {
                    local pte_check_restore_delta_opt "delta(`pte_check_prev_delta')"
                }
                capture quietly xtset `pte_check_prev_panel' `pte_check_prev_time', `pte_check_restore_delta_opt'
            }
            else {
                capture quietly xtset, clear
            }
            exit `pte_verify_rc'
        }
    }
    else {
        capture noisily _pte_verify_treatment `treatment', `verify_opts'
        local pte_verify_rc = _rc
        if `pte_verify_rc' != 0 {
            if `pte_orig_had_xtset' {
                local pte_orig_restore_delta_opt ""
                if "`pte_orig_delta'" != "" {
                    local pte_orig_restore_delta_opt "delta(`pte_orig_delta')"
                }
                capture quietly xtset `pte_orig_panel' `pte_orig_time', `pte_orig_restore_delta_opt'
            }
            else {
                capture quietly xtset, clear
            }
            exit `pte_verify_rc'
        }
    }

    local N_total = r(N_obs)
    local N_treated_obs = r(N_treated_obs)
    local N_untreated_obs = r(N_untreated_obs)
    local N_missing = r(N_missing)
    local pct_treated = r(pct_treated)
    local N_treated_firms = r(N_treated_firms)
    local N_control_firms = r(N_control_firms)
    local N_entry_events = r(N_entry_events)
    local N_exit_events = r(N_exit_events)
    local trt_type "`r(trt_type)'"
    local N_stable_0 = r(N_stable_0)
    local N_stable_1 = r(N_stable_1)
    local N_trans = r(N_trans)
    local n_first_d1 = r(n_first_d1)
    capture scalar _pte_tmp = r(pct_first_d1)
    if _rc == 0 {
        local pct_first_d1 = r(pct_first_d1)
    }
    else {
        local pct_first_d1 = .
    }
    capture scalar _pte_tmp = r(n_cohorts)
    if _rc == 0 {
        local n_cohorts = r(n_cohorts)
    }
    else {
        local n_cohorts = 0
    }

    local pte_setup_treatsig ""
    capture quietly _pte_treatment_signature, ///
        panelvar(`panelvar') timevar(`timevar_resolved') treatment(`treatment')
    local pte_treatsig_rc = _rc
    if `pte_treatsig_rc' == 0 {
        local pte_setup_treatsig `"`r(signature)'"'
    }
    if `pte_treatsig_rc' != 0 | `"`pte_setup_treatsig'"' == "" {
        if "`check'" == "" {
            // Treatment-law certification happens after helper regeneration.
            // A failed certification must therefore restore the last
            // certified helper bundle (or clear the fresh helpers when no
            // prior bundle existed) so helper-state and setup chars remain
            // atomic.
            forvalues _pte_i = 1/`pte_prev_helper_n' {
                local _pte_helper : word `_pte_i' of `pte_prev_helper_vars'
                local _pte_key : word `_pte_i' of `pte_prev_helper_keys'
                capture confirm variable `_pte_helper', exact
                if _rc == 0 {
                    capture drop `_pte_helper'
                }
                if `pte_has_prev_`_pte_key'' {
                    quietly clonevar `_pte_helper' = `pte_prev_`_pte_key''
                }
            }
        }
        if "`check'" != "" {
            if `pte_check_had_xtset' {
                local pte_check_restore_delta_opt ""
                if "`pte_check_prev_delta'" != "" {
                    local pte_check_restore_delta_opt "delta(`pte_check_prev_delta')"
                }
                capture quietly xtset `pte_check_prev_panel' `pte_check_prev_time', `pte_check_restore_delta_opt'
            }
            else {
                capture quietly xtset, clear
            }
        }
        else {
            if `pte_orig_had_xtset' {
                local pte_orig_restore_delta_opt ""
                if "`pte_orig_delta'" != "" {
                    local pte_orig_restore_delta_opt "delta(`pte_orig_delta')"
                }
                capture quietly xtset `pte_orig_panel' `pte_orig_time', `pte_orig_restore_delta_opt'
            }
            else {
                capture quietly xtset, clear
            }
        }
        di as error "pte_setup: unable to certify the treatment-law signature"
        if `pte_treatsig_rc' != 0 {
            di as error "  _pte_treatment_signature returned rc=`pte_treatsig_rc'"
        }
        di as error "  setup contract publication requires panel/time/treatment/treatsig/xtdelta together"
        exit 459
    }

    if "`check'" == "" {
        if `pte_prev_helper_snapshot' & `pte_prev_helper_complete' {
            forvalues _pte_i = 1/`pte_prev_helper_n' {
                local _pte_helper : word `_pte_i' of `pte_prev_helper_vars'
                local _pte_key : word `_pte_i' of `pte_prev_helper_keys'
                capture confirm variable `_pte_helper', exact
                if _rc != 0 {
                    local pte_prev_helper_changed 1
                    continue, break
                }
                capture assert `pte_prev_`_pte_key'' == `_pte_helper' | ///
                    (missing(`pte_prev_`_pte_key'') & missing(`_pte_helper'))
                if _rc != 0 {
                    local pte_prev_helper_changed 1
                    continue, break
                }
            }
        }

        local pte_prev_panel ""
        local pte_prev_time ""
        local pte_prev_delta ""
        local pte_had_xtset 0
        local pte_sum_xtset_sw 0

        capture quietly xtset
        if _rc == 0 {
            local pte_had_xtset 1
            local pte_prev_panel "`r(panelvar)'"
            local pte_prev_time "`r(timevar)'"
            local pte_prev_delta "`r(tdelta)'"
        }

        if `pte_had_xtset' == 0 ///
            | "`pte_prev_panel'" != "`panelvar'" ///
            | "`pte_prev_time'" != "`timevar_resolved'" ///
            | ("`panel_delta'" != "" & "`pte_prev_delta'" != "`panel_delta'") {
            if "`panel_delta'" != "" {
                quietly xtset `panelvar' `timevar_resolved', delta(`panel_delta')
            }
            else {
                quietly xtset `panelvar' `timevar_resolved'
            }
            local pte_sum_xtset_sw 1
        }

        local pte_sum_rc 0
        local pte_report_rc 0

        capture quietly _pte_setup_summary, treatment(`treatment') minthreshold(`minthreshold')
        local pte_sum_rc = _rc
        if `pte_sum_rc' == 0 {
            capture scalar _pte_tmp = r(pre_periods)
            if _rc == 0 {
                local avg_pre = r(pre_periods)
                local avg_post = r(post_periods)
                local assumption_pass = r(assumption_33_pass)
            }
            else {
                local avg_pre = .
                local avg_post = .
                local assumption_pass = .
            }

            if "`report'" != "" {
                capture noisily _pte_setup_summary, treatment(`treatment') report minthreshold(`minthreshold')
                local pte_report_rc = _rc
            }
        }
        else {
            local avg_pre = .
            local avg_post = .
            local assumption_pass = .
        }

        if `pte_sum_xtset_sw' {
            if `pte_had_xtset' {
                local pte_restore_delta_opt ""
                if "`pte_prev_delta'" != "" {
                    local pte_restore_delta_opt "delta(`pte_prev_delta')"
                }
                capture quietly sort `pte_prev_panel' `pte_prev_time'
                capture quietly xtset `pte_prev_panel' `pte_prev_time', `pte_restore_delta_opt'
            }
            else {
                capture quietly xtset, clear
            }
        }

        if `pte_sum_rc' != 0 | `pte_report_rc' != 0 {
            // A late setup failure must leave the helper-state contract at the
            // last successful bundle. Otherwise diagnostics/predict can
            // consume a failed treatment law against stale dataset chars.
            forvalues _pte_i = 1/`pte_prev_helper_n' {
                local _pte_helper : word `_pte_i' of `pte_prev_helper_vars'
                local _pte_key : word `_pte_i' of `pte_prev_helper_keys'
                capture confirm variable `_pte_helper', exact
                if _rc == 0 {
                    capture drop `_pte_helper'
                }
                if `pte_has_prev_`_pte_key'' {
                    quietly clonevar `_pte_helper' = `pte_prev_`_pte_key''
                }
            }
        }

        if `pte_sum_rc' != 0 {
            exit `pte_sum_rc'
        }
        if `pte_report_rc' != 0 {
            exit `pte_report_rc'
        }
    }
    else {
        local avg_pre = .
        local avg_post = .
        local assumption_pass = (`N_stable_0' >= `minthreshold') & (`N_stable_1' >= `minthreshold')
        local N_total_firms = `n_groups'

        if "`report'" != "" {
            di as text _n "{hline 70}"
            di as text "PTE Data Setup Summary"
            di as text "{hline 70}"
            di as text _n "Panel structure:" _col(30) as result "`panelvar' x `timevar_resolved'"
            di as text "Total observations:" _col(30) as result %12.0fc `N_total'
            di as text "Total firms:" _col(30) as result %12.0fc `N_total_firms'
            di as text _n "Treatment Summary:"
            di as text "  Treated firms:" _col(30) as result %12.0fc `N_treated_firms'
            di as text "  Control firms:" _col(30) as result %12.0fc `N_control_firms'
            di as text "  Treatment type:" _col(30) as result "`trt_type'"
            di as text "  Entry events:" _col(30) as result %12.0fc `N_entry_events'
            di as text "  Exit events:" _col(30) as result %12.0fc `N_exit_events'
            di as text "  Transition observations:" _col(30) as result %12.0fc `N_trans'
            di as text _n "Stable-support diagnostics:"
            di as text "  Stable untreated (D=L.D=0):" _col(30) as result %12.0fc `N_stable_0'
            di as text "  Stable treated (D=L.D=1):" _col(30) as result %12.0fc `N_stable_1'
            di as text "  Assumption 3.3 flag:" _col(30) as result %12.0fc `assumption_pass'
            di as text _n "check mode note: helper variables are not created, so avg_pre and avg_post are not returned."
            di as text "{hline 70}"
        }
    }

    if "`check'" != "" {
        local pte_stored_panel : char _dta[_pte_setup_panelvar]
        local pte_stored_time : char _dta[_pte_setup_timevar]
        local pte_stored_treatment : char _dta[_pte_setup_treatment]
        local pte_stored_treatsig : char _dta[_pte_setup_treatsig]
        local pte_stored_xtdelta : char _dta[_pte_setup_xtdelta]
        local pte_stored_xtdelta_clean = strtrim(`"`pte_stored_xtdelta'"')
        local pte_panel_delta_clean = strtrim(`"`panel_delta'"')
        local pte_stored_xtdelta_stale = 0
        local pte_have_stored_contract = ///
            (`"`pte_stored_panel'"' != "") | ///
            (`"`pte_stored_time'"' != "") | ///
            (`"`pte_stored_treatment'"' != "") | ///
            (`"`pte_stored_treatsig'"' != "") | ///
            (`"`pte_stored_xtdelta'"' != "")
        local pte_contract_stale = 0

        if `"`pte_stored_xtdelta_clean'"' != "" & `"`pte_panel_delta_clean'"' != "" {
            local pte_stored_xtdelta_num = real(`"`pte_stored_xtdelta_clean'"')
            local pte_panel_delta_num = real(`"`pte_panel_delta_clean'"')
            if !missing(`pte_stored_xtdelta_num') & !missing(`pte_panel_delta_num') {
                if `pte_stored_xtdelta_num' != `pte_panel_delta_num' {
                    local pte_stored_xtdelta_stale = 1
                }
            }
            else if `"`pte_stored_xtdelta_clean'"' != `"`pte_panel_delta_clean'"' {
                local pte_stored_xtdelta_stale = 1
            }
        }

        if `pte_have_stored_contract' {
            if `"`pte_stored_panel'"' == "" | `"`pte_stored_time'"' == "" | ///
                `"`pte_stored_treatment'"' == "" | `"`pte_stored_treatsig'"' == "" | ///
                `"`pte_stored_xtdelta'"' == "" {
                local pte_contract_stale = 1
            }
            else if `"`pte_stored_panel'"' != `"`panelvar'"' | ///
                `"`pte_stored_time'"' != `"`timevar_resolved'"' | ///
                `"`pte_stored_treatment'"' != `"`treatment'"' | ///
                `pte_stored_xtdelta_stale' | ///
                `"`pte_setup_treatsig'"' == "" | ///
                `"`pte_stored_treatsig'"' != `"`pte_setup_treatsig'"' {
                local pte_contract_stale = 1
            }
        }

        if `pte_contract_stale' {
            char _dta[_pte_setup_panelvar]
            char _dta[_pte_setup_timevar]
            char _dta[_pte_setup_treatment]
            char _dta[_pte_setup_treatsig]
            char _dta[_pte_setup_xtdelta]
        }

        // check mode validates the current treatment law but intentionally
        // does not rebuild helpers. Any live pte result that cannot be
        // certified against the audited panel/time/treatment contract must
        // therefore be cleared to prevent pte_p from consuming stale state.
        capture local _pte_prev_cmd = e(cmd)
        if _rc == 0 & `"`_pte_prev_cmd'"' == "pte" {
            local _pte_est_id ""
            local _pte_est_time ""
            capture local _pte_est_id = e(idvar)
            if `"`_pte_est_id'"' == "." {
                local _pte_est_id ""
            }
            if _rc != 0 | `"`_pte_est_id'"' == "" {
                capture local _pte_est_id = e(id)
                if `"`_pte_est_id'"' == "." {
                    local _pte_est_id ""
                }
            }
            capture local _pte_est_time = e(timevar)
            if `"`_pte_est_time'"' == "." {
                local _pte_est_time ""
            }
            if _rc != 0 | `"`_pte_est_time'"' == "" {
                capture local _pte_est_time = e(time)
                if `"`_pte_est_time'"' == "." {
                    local _pte_est_time ""
                }
            }
            local _pte_est_treatment ""
            capture local _pte_est_treatment = e(treatment)
            if `"`_pte_est_treatment'"' == "." {
                local _pte_est_treatment ""
            }
            local _pte_est_treatsig ""
            capture local _pte_est_treatsig = e(treatsig)
            if `"`_pte_est_treatsig'"' == "." {
                local _pte_est_treatsig ""
            }
            local _pte_est_xtdelta ""
            tempname _pte_est_xtdelta_scalar
            capture scalar `_pte_est_xtdelta_scalar' = e(xtdelta)
            if _rc == 0 & !missing(`_pte_est_xtdelta_scalar') {
                local _pte_est_xtdelta = strofreal(`_pte_est_xtdelta_scalar')
            }
            local _pte_panel_delta_clean = strtrim(`"`panel_delta'"')
            local _pte_est_xtdelta_clean = strtrim(`"`_pte_est_xtdelta'"')
            local _pte_xtdelta_conflict = 0
            local _pte_live_law_claim = ///
                (`"`_pte_est_id'"' != "") | ///
                (`"`_pte_est_time'"' != "") | ///
                (`"`_pte_est_treatment'"' != "") | ///
                (`"`_pte_est_treatsig'"' != "") | ///
                (`"`_pte_est_xtdelta_clean'"' != "")
            local _pte_live_full_law = ///
                (`"`_pte_est_id'"' != "") & ///
                (`"`_pte_est_time'"' != "") & ///
                (`"`_pte_est_treatment'"' != "") & ///
                (`"`_pte_est_treatsig'"' != "") & ///
                (`"`_pte_est_xtdelta_clean'"' != "")
            local _pte_incomplete_live_law = ///
                (`_pte_live_law_claim' == 1 & `_pte_live_full_law' == 0)
            if `"`_pte_panel_delta_clean'"' != "" & `"`_pte_est_xtdelta_clean'"' != "" {
                local _pte_panel_delta_num = real(`"`_pte_panel_delta_clean'"')
                local _pte_est_xtdelta_num = real(`"`_pte_est_xtdelta_clean'"')
                if !missing(`_pte_panel_delta_num') & !missing(`_pte_est_xtdelta_num') {
                    if `_pte_panel_delta_num' != `_pte_est_xtdelta_num' {
                        local _pte_xtdelta_conflict = 1
                    }
                }
                else if `"`_pte_panel_delta_clean'"' != `"`_pte_est_xtdelta_clean'"' {
                    local _pte_xtdelta_conflict = 1
                }
            }

            // check mode audits the current panel/time/treatment law even
            // when it does not publish dataset chars. A partial live bundle
            // cannot be certified against that audited law, so any claimant
            // that advertises only a subset of panel/time/treatment/treatsig/
            // xtdelta must fail closed before downstream replay consumers see
            // it.
            if `_pte_incomplete_live_law' | ///
                `"`_pte_est_id'"' != `"`panelvar'"' | ///
                `"`_pte_est_time'"' != `"`timevar_resolved'"' | ///
                (`"`_pte_est_treatment'"' != "" & ///
                 `"`_pte_est_treatment'"' != `"`treatment'"') | ///
                (`"`pte_setup_treatsig'"' != "" & `"`_pte_est_treatsig'"' == "") | ///
                (`"`_pte_panel_delta_clean'"' != "" & `"`_pte_est_xtdelta_clean'"' == "") | ///
                `_pte_xtdelta_conflict' | ///
                (`"`_pte_est_treatsig'"' != "" & ///
                 `"`pte_setup_treatsig'"' != "" & ///
                 `"`_pte_est_treatsig'"' != `"`pte_setup_treatsig'"') {
                capture ereturn clear
            }
        }

        if `pte_check_had_xtset' {
            local pte_check_restore_delta_opt ""
            if "`pte_check_prev_delta'" != "" {
                local pte_check_restore_delta_opt "delta(`pte_check_prev_delta')"
            }
            capture quietly xtset `pte_check_prev_panel' `pte_check_prev_time', `pte_check_restore_delta_opt'
        }
        else {
            capture quietly xtset, clear
        }
    }
    else {
        // Diagnostics run after pte_setup may execute without an active e()
        // result and after the caller's original xtset has been restored.
        // Persist the setup-selected contract on the dataset so post-setup
        // consumers can resolve the same firm/time axes and treatment law.
        char _dta[_pte_setup_panelvar] "`panelvar'"
        char _dta[_pte_setup_timevar] "`timevar_resolved'"
        char _dta[_pte_setup_treatment] "`treatment'"
        char _dta[_pte_setup_treatsig] "`pte_setup_treatsig'"
        char _dta[_pte_setup_xtdelta] "`panel_delta'"

        // A successful non-check setup can redefine the dataset-scoped panel
        // contract independently of the last pte estimation. If a stale pte
        // result advertises a different (i,t) axis, downstream diagnostics
        // must not keep consuming that old e() payload against the freshly
        // rebuilt _pte_* helpers and setup chars.
        capture local _pte_prev_cmd = e(cmd)
        if _rc == 0 & `"`_pte_prev_cmd'"' == "pte" {
            local _pte_est_id ""
            local _pte_est_time ""
            capture local _pte_est_id = e(idvar)
            if `"`_pte_est_id'"' == "." {
                local _pte_est_id ""
            }
            if _rc != 0 | `"`_pte_est_id'"' == "" {
                capture local _pte_est_id = e(id)
                if `"`_pte_est_id'"' == "." {
                    local _pte_est_id ""
                }
            }
            capture local _pte_est_time = e(timevar)
            if `"`_pte_est_time'"' == "." {
                local _pte_est_time ""
            }
            if _rc != 0 | `"`_pte_est_time'"' == "" {
                capture local _pte_est_time = e(time)
                if `"`_pte_est_time'"' == "." {
                    local _pte_est_time ""
                }
            }
            local _pte_est_treatment ""
            capture local _pte_est_treatment = e(treatment)
            if `"`_pte_est_treatment'"' == "." {
                local _pte_est_treatment ""
            }
            local _pte_est_treatsig ""
            capture local _pte_est_treatsig = e(treatsig)
            if `"`_pte_est_treatsig'"' == "." {
                local _pte_est_treatsig ""
            }
            local _pte_est_xtdelta ""
            tempname _pte_est_xtdelta_scalar
            capture scalar `_pte_est_xtdelta_scalar' = e(xtdelta)
            if _rc == 0 & !missing(`_pte_est_xtdelta_scalar') {
                local _pte_est_xtdelta = strofreal(`_pte_est_xtdelta_scalar')
            }
            local _pte_panel_delta_clean = strtrim(`"`panel_delta'"')
            local _pte_est_xtdelta_clean = strtrim(`"`_pte_est_xtdelta'"')
            local _pte_xtdelta_conflict = 0
            local _pte_live_law_claim = ///
                (`"`_pte_est_id'"' != "") | ///
                (`"`_pte_est_time'"' != "") | ///
                (`"`_pte_est_treatment'"' != "") | ///
                (`"`_pte_est_treatsig'"' != "") | ///
                (`"`_pte_est_xtdelta_clean'"' != "")
            local _pte_live_full_law = ///
                (`"`_pte_est_id'"' != "") & ///
                (`"`_pte_est_time'"' != "") & ///
                (`"`_pte_est_treatment'"' != "") & ///
                (`"`_pte_est_treatsig'"' != "") & ///
                (`"`_pte_est_xtdelta_clean'"' != "")
            if `"`_pte_panel_delta_clean'"' != "" & `"`_pte_est_xtdelta_clean'"' != "" {
                local _pte_panel_delta_num = real(`"`_pte_panel_delta_clean'"')
                local _pte_est_xtdelta_num = real(`"`_pte_est_xtdelta_clean'"')
                if !missing(`_pte_panel_delta_num') & !missing(`_pte_est_xtdelta_num') {
                    if `_pte_panel_delta_num' != `_pte_est_xtdelta_num' {
                        local _pte_xtdelta_conflict = 1
                    }
                }
                else if `"`_pte_panel_delta_clean'"' != `"`_pte_est_xtdelta_clean'"' {
                    local _pte_xtdelta_conflict = 1
                }
            }

            if `"`_pte_est_id'"' != `"`panelvar'"' | ///
                `"`_pte_est_time'"' != `"`timevar_resolved'"' | ///
                (`"`_pte_panel_delta_clean'"' != "" & `"`_pte_est_xtdelta_clean'"' == "") | ///
                `_pte_xtdelta_conflict' | ///
                (`"`pte_setup_treatsig'"' != "" & `"`_pte_est_treatsig'"' == "") | ///
                (`"`_pte_est_treatsig'"' != "" & ///
                 `"`pte_setup_treatsig'"' != "" & ///
                 `"`_pte_est_treatsig'"' != `"`pte_setup_treatsig'"') | ///
                (`"`_pte_est_treatment'"' != "" & ///
                 `"`_pte_est_treatment'"' != `"`treatment'"') {
                capture ereturn clear
            }
        }

        if `pte_orig_had_xtset' {
            local pte_orig_restore_delta_opt ""
            if "`pte_orig_delta'" != "" {
                local pte_orig_restore_delta_opt "delta(`pte_orig_delta')"
            }
            capture quietly xtset `pte_orig_panel' `pte_orig_time', `pte_orig_restore_delta_opt'
        }
        else {
            capture quietly xtset, clear
        }
    }

    return clear
    return scalar N_obs = `N_total'
    return scalar N_treated_obs = `N_treated_obs'
    return scalar N_untreated_obs = `N_untreated_obs'
    return scalar N_missing = `N_missing'
    return scalar pct_treated = `pct_treated'
    return scalar N_treated_firms = `N_treated_firms'
    return scalar N_control_firms = `N_control_firms'
    return scalar N_entry_events = `N_entry_events'
    return scalar N_exit_events = `N_exit_events'
    return scalar N_stable_0 = `N_stable_0'
    return scalar N_stable_1 = `N_stable_1'
    return scalar N_trans = `N_trans'
    return scalar n_first_d1 = `n_first_d1'
    return scalar pct_first_d1 = `pct_first_d1'
    return scalar n_cohorts = `n_cohorts'
    return scalar balanced = `balanced'
    return scalar regular = `regular'
    return scalar panel_n_obs = `n_obs'
    return scalar panel_n_groups = `n_groups'
    return scalar input_validation_passed = `input_validation_passed'
    return scalar total_invalid_inputs = `total_invalid_inputs'
    return scalar total_nonpos = `total_nonpos'
    return scalar total_miss = `total_miss'
    return scalar n_invalid_obs = `n_invalid_obs'
    return scalar avg_pre = `avg_pre'
    return scalar avg_post = `avg_post'
    return scalar assumption_pass = `assumption_pass'
    return local trt_type "`trt_type'"
    return local panelvar "`panelvar'"
    return local timevar "`timevar_resolved'"
    return local treatment "`treatment'"
    return local generate "_pte_"
    return local cmd "pte_setup"
end

capture program drop _pte_setup_confirm_exact_list
program define _pte_setup_confirm_exact_list, rclass
    version 14.0

    syntax , ROLE(string) [VARS(string) SINGLE]

    local vars_clean = strtrim(`"`vars'"')
    if `"`vars_clean'"' == "" {
        return local vars ""
        exit
    }

    if "`single'" != "" {
        local n_words : word count `vars_clean'
        if `n_words' != 1 {
            di as error "pte_setup: `role'() must name exactly one variable"
            exit 198
        }
    }

    foreach var of local vars_clean {
        capture confirm variable `var', exact
        if _rc != 0 {
            di as error "pte_setup: variable `var' not found"
            di as error "  `role'() must match existing variable name(s) exactly"
            exit 111
        }
    }

    return local vars `"`vars_clean'"'
end
