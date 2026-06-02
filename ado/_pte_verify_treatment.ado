*! _pte_verify_treatment.ado
*! Validate the observed treatment path before PTE constructs timing helpers.
*! This routine enforces the binary treatment law, checks whether the realized
*! path is absorbing when requested, and generates helper variables whose timing
*! semantics must stay aligned with the paper's entry-time notation. It also
*! preserves and restores the caller's xtset state whenever it temporarily
*! retunes the panel delta to match the observed spacing of the supplied panel.

version 14.0
capture program drop _pte_verify_treatment
program define _pte_verify_treatment, rclass
	version 14.0
	
	// The optional panel/time arguments let callers validate a dataset even when
	// xtset has not yet been established. strict gates the absorbing-treatment
	// design used in the baseline paper; nogenerate keeps the check read-only.
	syntax name(name=treatment) [, ///
		PANELvar(name) TIMEvar(name) ///
		DELTA(string) ///
		STRict    /// strict mode: error on non-absorbing
		REPlace   /// replace existing _pte_* variables
		NOGENerate /// skip variable generation
		VERbose   /// verbose output
	]

	capture confirm variable `treatment', exact
	if _rc != 0 {
		di as error "pte: treatment variable {bf:`treatment'} not found"
		exit 111
	}
	capture confirm numeric variable `treatment'
	if _rc != 0 {
		di as error "pte: treatment variable {bf:`treatment'} must be numeric"
		exit 198
	}
	if "`panelvar'" != "" {
		capture confirm variable `panelvar', exact
		if _rc != 0 {
			di as error "pte: panel variable {bf:`panelvar'} not found"
			exit 111
		}
	}
	if "`timevar'" != "" {
		capture confirm variable `timevar', exact
		if _rc != 0 {
			di as error "pte: time variable {bf:`timevar'} not found"
			exit 111
		}
	}

	local pte_had_xtset 0
	local pte_prev_panelvar ""
	local pte_prev_timevar ""
	local pte_prev_delta ""
	local pte_xtset_switched 0
	local pte_target_delta ""
	
	// The treatment helpers use time-series operators and relative-time math, so
	// the dataset must have a valid xtset definition before any lag logic runs.
	// When delta() is omitted, infer a constant observed gap and switch xtset
	// temporarily so _pte_nt uses the true panel spacing.
	if "`panelvar'" == "" | "`timevar'" == "" {
		capture qui xtset
		if _rc != 0 {
			di as error "[pte] panel data not set"
			di as error "run {bf:xtset} {it:panelvar timevar} first"
			exit 459
		}
		local pte_had_xtset 1
		local pte_prev_panelvar "`r(panelvar)'"
		local pte_prev_timevar "`r(timevar)'"
		local pte_prev_delta "`r(tdelta)'"
		local panelvar "`r(panelvar)'"
		local timevar "`r(timevar)'"
		if "`panelvar'" == "" | "`timevar'" == "" {
			di as error "[pte] panel data not set"
			di as error "run {bf:xtset} {it:panelvar timevar} first"
			exit 459
		}
		if "`delta'" != "" {
			local pte_target_delta = strtrim(`"`delta'"')
		}
		if "`pte_target_delta'" == "" {
			tempvar _pte_gap_probe
			quietly bysort `panelvar' (`timevar'): gen double `_pte_gap_probe' = ///
				`timevar' - `timevar'[_n-1] if _n > 1
			quietly count if !missing(`_pte_gap_probe')
			if r(N) > 0 {
				quietly summarize `_pte_gap_probe', meanonly
				local pte_gap_min = r(min)
				local pte_gap_max = r(max)
				if `pte_gap_min' > 0 & abs(`pte_gap_max' - `pte_gap_min') <= 1e-10 {
					local pte_target_delta : display %21.0g `pte_gap_min'
					local pte_target_delta = strtrim("`pte_target_delta'")
				}
			}
		}
		if "`pte_target_delta'" != "" & ///
			strtrim("`pte_prev_delta'") != strtrim("`pte_target_delta'") {
			quietly xtset `panelvar' `timevar', delta(`pte_target_delta')
			local pte_xtset_switched 1
		}
	}
	else {
		capture qui xtset
		if _rc == 0 {
			local pte_had_xtset 1
			local pte_prev_panelvar "`r(panelvar)'"
			local pte_prev_timevar "`r(timevar)'"
			local pte_prev_delta "`r(tdelta)'"
		}

		if "`delta'" != "" {
			local pte_target_delta = strtrim(`"`delta'"')
		}
		if "`pte_target_delta'" == "" {
			tempvar _pte_gap_probe
			quietly bysort `panelvar' (`timevar'): gen double `_pte_gap_probe' = ///
				`timevar' - `timevar'[_n-1] if _n > 1
			quietly count if !missing(`_pte_gap_probe')
			if r(N) > 0 {
				quietly summarize `_pte_gap_probe', meanonly
				local pte_gap_min = r(min)
				local pte_gap_max = r(max)
				if `pte_gap_min' > 0 & abs(`pte_gap_max' - `pte_gap_min') <= 1e-10 {
					local pte_target_delta : display %21.0g `pte_gap_min'
					local pte_target_delta = strtrim("`pte_target_delta'")
				}
			}
		}

		local pte_need_switch = ///
			(("`pte_prev_panelvar'" != "`panelvar'") | ("`pte_prev_timevar'" != "`timevar'"))
		if "`pte_target_delta'" != "" & "`pte_prev_panelvar'" == "`panelvar'" ///
			& "`pte_prev_timevar'" == "`timevar'" ///
			& strtrim("`pte_prev_delta'") != strtrim("`pte_target_delta'") {
			local pte_need_switch = 1
		}

		if `pte_need_switch' {
			local pte_xt_delta_opt ""
			if "`pte_target_delta'" != "" {
				local pte_xt_delta_opt ", delta(`pte_target_delta')"
			}
			quietly xtset `panelvar' `timevar'`pte_xt_delta_opt'
			local pte_xtset_switched 1
		}
	}

	quietly xtset
	local pte_panel_delta "`r(tdelta)'"
	local pte_time_delta = real("`pte_panel_delta'")
	if missing(`pte_time_delta') | `pte_time_delta' <= 0 {
		local pte_time_delta = 1
	}
	
	// Re-confirm the core treatment contract after xtset manipulation so later
	// maintenance edits cannot accidentally weaken the exact-name requirement.
	confirm variable `treatment', exact
	confirm numeric variable `treatment'
	
	// Delay any replace() side effect until every validation gate has passed.
	// That keeps failing calls from destroying helper variables that still match
	// the caller's last valid state.
	if "`nogenerate'" == "" {
		local pte_existing_helpers ""
		foreach v in _pte_D _pte_treat_year _pte_first_treat_year ///
			_pte_nt _pte_mid _pte_treat _pte_cohort {
			capture confirm variable `v'
			if _rc == 0 {
				if "`replace'" != "" {
					local pte_existing_helpers "`pte_existing_helpers' `v'"
				}
				else {
					di as error "pte: variable {bf:`v'} already exists"
					di as error "  use {bf:replace} option to overwrite"
					if `pte_xtset_switched' {
						if `pte_had_xtset' {
							local pte_restore_delta_opt ""
							if "`pte_prev_delta'" != "" {
								local pte_restore_delta_opt "delta(`pte_prev_delta')"
							}
							capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
						}
						else {
							capture quietly xtset, clear
						}
					}
					exit 110
				}
			}
		}
	}
	
	// Report missing treatment mass before the binary checks so users can tell
	// whether later failures come from coding errors or from partial coverage.
	qui count
	local N_total = r(N)
	
	qui count if missing(`treatment')
	local N_missing = r(N)
	
	local pct_missing = 0
	if `N_total' > 0 {
		local pct_missing = 100 * `N_missing' / `N_total'
	}
	
	if `N_missing' > 0 & "`verbose'" != "" {
		di as txt "  Missing treatment values: " as result `N_missing' ///
			as txt " (" as result %5.2f `pct_missing' as txt "%)"
		if `pct_missing' > 10 {
			di as txt "  {bf:Warning}: High proportion of missing values (>" ///
				as result %5.1f `pct_missing' as txt "%)"
			di as txt "    This may affect estimation precision"
		}
	}
	
	// Use three separate binary checks so the error path can distinguish between
	// extra categories, out-of-range values, and fractional coding drift.
	
	// Tabulation catches stray categories before relying on summary moments.
	qui tab `treatment'
	if r(r) > 2 {
		di as error "pte: treatment variable {bf:`treatment'} has more than 2 values"
		di as error "  treatment must be binary: D ∈ {0, 1}"
		if `pte_xtset_switched' {
			if `pte_had_xtset' {
				local pte_restore_delta_opt ""
				if "`pte_prev_delta'" != "" {
					local pte_restore_delta_opt "delta(`pte_prev_delta')"
				}
				capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
			}
			else {
				capture quietly xtset, clear
			}
		}
		exit 450
	}
	
	// Summary moments provide a fast guard against negative or >1 coding.
	qui summ `treatment'
	if r(min) < 0 | r(max) > 1 {
		di as error "pte: treatment variable {bf:`treatment'} has values outside [0, 1]"
		di as error "  found: min=" as result r(min) as error " max=" as result r(max)
		di as error "  treatment must be binary: D ∈ {0, 1}"
		if `pte_xtset_switched' {
			if `pte_had_xtset' {
				local pte_restore_delta_opt ""
				if "`pte_prev_delta'" != "" {
					local pte_restore_delta_opt "delta(`pte_prev_delta')"
				}
				capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
			}
			else {
				capture quietly xtset, clear
			}
		}
		exit 450
	}
	
	// The final assert catches fractional values such as 0.5 that can pass the
	// range test but still violate the treatment-law contract.
	capture assert `treatment' == 0 | `treatment' == 1 if !missing(`treatment')
	if _rc != 0 {
		di as error "pte: treatment variable {bf:`treatment'} contains non-integer values"
		di as error "  treatment must be binary: D ∈ {0, 1}"
		if `pte_xtset_switched' {
			if `pte_had_xtset' {
				local pte_restore_delta_opt ""
				if "`pte_prev_delta'" != "" {
					local pte_restore_delta_opt "delta(`pte_prev_delta')"
				}
				capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
			}
			else {
				capture quietly xtset, clear
			}
		}
		exit 450
	}
	
	if "`verbose'" != "" {
		di as txt "  Binary check: " as result "PASSED" ///
			as txt " (D ∈ {0, 1})"
	}
	
	// ATT estimation is undefined if the realized sample never exposes one side
	// of the treatment state space, so fail before building timing metadata.
	qui summ `treatment'
	local D_mean = r(mean)
	local D_min = r(min)
	local D_max = r(max)
	
	// Pure-control data cannot identify treated outcomes.
	if `D_max' == 0 {
		di as error "pte: all observations are untreated (D=0)"
		di as error "  cannot estimate treatment effects without treated units"
		if `pte_xtset_switched' {
			if `pte_had_xtset' {
				local pte_restore_delta_opt ""
				if "`pte_prev_delta'" != "" {
					local pte_restore_delta_opt "delta(`pte_prev_delta')"
				}
				capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
			}
			else {
				capture quietly xtset, clear
			}
		}
		exit 498
	}
	
	// Pure-treated data cannot identify the untreated counterfactual path.
	if `D_min' == 1 {
		di as error "pte: all observations are treated (D=1)"
		di as error "  cannot estimate treatment effects without control units"
		if `pte_xtset_switched' {
			if `pte_had_xtset' {
				local pte_restore_delta_opt ""
				if "`pte_prev_delta'" != "" {
					local pte_restore_delta_opt "delta(`pte_prev_delta')"
				}
				capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
			}
			else {
				capture quietly xtset, clear
			}
		}
		exit 498
	}
	
	// Observation counts are later echoed in the validation report and returns.
	qui count if `treatment' == 1 & !missing(`treatment')
	local N_treated_obs = r(N)
	
	qui count if `treatment' == 0 & !missing(`treatment')
	local N_untreated_obs = r(N)
	
	local N_valid = `N_treated_obs' + `N_untreated_obs'
	local pct_treated = 100 * `N_treated_obs' / `N_valid'
	
	if "`verbose'" != "" {
		di as txt "  Variation check: " as result "PASSED" ///
			as txt " (treated=" as result `N_treated_obs' ///
			as txt ", untreated=" as result `N_untreated_obs' as txt ")"
	}
	
	// Entry and exit counts classify the realized law of motion. The _n > 1
	// guard keeps true panel-first observations from manufacturing transitions
	// when the lag is structurally undefined.
	
	tempvar _entry _exit
	
	// Observed 0->1 switches pin down entry-based timing metadata.
	qui bys `panelvar' (`timevar'): gen byte `_entry' = ///
		(L.`treatment' == 0 & `treatment' == 1) if _n > 1
	qui count if `_entry' == 1
	local n_entry = r(N)
	
	// Any 1->0 switch reveals a non-absorbing realized treatment path.
	qui bys `panelvar' (`timevar'): gen byte `_exit' = ///
		(L.`treatment' == 1 & `treatment' == 0) if _n > 1
	qui count if `_exit' == 1
	local n_exit = r(N)
	
	// Baseline PTE focuses on the absorbing law, but the checker still records
	// whether the observed data violate that restriction.
	if `n_exit' > 0 {
		local trt_type "non-absorbing"
	}
	else {
		local trt_type "absorbing"
	}
	
	// strict turns the absorbing baseline into a hard gate instead of a warning.
	if "`strict'" != "" & `n_exit' > 0 {
		di as error "pte: non-absorbing treatment detected"
		di as error "  found `n_exit' exit event(s) (D: 1→0)"
		di as error "  absorbing treatment requires D_t >= D_{t-1}"
		di as error "  remove {bf:strict} option to allow non-absorbing treatment"
		if `pte_xtset_switched' {
			if `pte_had_xtset' {
				local pte_restore_delta_opt ""
				if "`pte_prev_delta'" != "" {
					local pte_restore_delta_opt "delta(`pte_prev_delta')"
				}
				capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
			}
			else {
				capture quietly xtset, clear
			}
		}
		exit 2003
	}
	
	if "`verbose'" != "" {
		di as txt "  Absorbing check: " as result "`trt_type'" ///
			as txt " (entries=" as result `n_entry' ///
			as txt ", exits=" as result `n_exit' as txt ")"
	}
	
	// Firm-level exposure counts are taken from the realized path before helper
	// generation so error exits can leave pre-existing helper state untouched.
	
	tempvar _firm_tag _ever_treated
	qui egen byte `_firm_tag' = tag(`panelvar')
	qui bys `panelvar': egen byte `_ever_treated' = max(`treatment')
	qui count if `_firm_tag' == 1 & `_ever_treated' == 1
	local N_treated_firms = r(N)
	qui count if `_firm_tag' == 1 & `_ever_treated' == 0
	local N_control_firms = r(N)
	
	// Stable untreated and stable treated pairs are the support cells needed for
	// the paper's Theorem 3.1 moments. Transition rows are counted separately
	// because the baseline estimator drops them from the GMM sample.
	
	local N_stable_0 = 0
	local N_stable_1 = 0
	local N_trans = 0
	local n_first_d1 = 0
	local n_cohorts = 0

	// Stable untreated observations identify the untreated evolution h_bar_0.
	qui count if `treatment' == L.`treatment' & `treatment' == 0
	local N_stable_0 = r(N)

	// Stable treated observations identify the treated evolution h_bar_1.
	qui count if `treatment' == L.`treatment' & `treatment' == 1
	local N_stable_1 = r(N)

	// Transition rows have an observed lag but switch regime, so they cannot be
	// used as stable-state moments even though they remain informative for timing.
	qui count if `treatment' != L.`treatment' & ///
		!missing(`treatment') & !missing(L.`treatment')
	local N_trans = r(N)

	// If the first nonmissing observed state is already treated, entry timing is
	// left-censored. Those firms stay ever-treated but must not receive a fake
	// observed entry year from the truncated panel.
	tempvar _first_nonmissing_time _first_d1_tag _firm_tag2
	qui bys `panelvar': egen double `_first_nonmissing_time' = ///
		min(cond(!missing(`treatment'), `timevar', .))
	qui gen byte `_first_d1_tag' = (`timevar' == `_first_nonmissing_time') & ///
		`treatment' == 1 if !missing(`_first_nonmissing_time')
	qui bys `panelvar': gen byte `_firm_tag2' = (_n == 1)
	qui count if `_first_d1_tag' == 1
	local n_first_d1 = r(N)
	qui count if `_firm_tag2' == 1
	local n_firms_total = r(N)
	if `n_firms_total' > 0 {
		local pct_first_d1 = `n_first_d1' / `n_firms_total' * 100
	}
	else {
		local pct_first_d1 = 0
	}

	// Cohorts are counted only from observed 0->1 entries. This keeps the cohort
	// count tied to realized entry events rather than inferred pre-sample timing.
	tempvar _cohort_year _cohort_tag
	qui bys `panelvar': egen double `_cohort_year' = ///
		min(cond(`_entry' == 1, `timevar', .))
	qui bys `_cohort_year': gen byte `_cohort_tag' = (_n == 1) ///
		if !missing(`_cohort_year')
	qui count if `_cohort_tag' == 1
	local n_cohorts = r(N)
	
	// Emit a compact summary before helper generation so validation failures are
	// visible even in read-only mode.
	di as txt ""
	di as txt "=== Treatment Variable Verification Summary ==="
	di as txt "  Observations:     " as result %10.0fc `N_total'
	di as txt "  Treated (D=1):    " as result %10.0fc `N_treated_obs' ///
		as txt " (" as result %5.2f `pct_treated' as txt "%)"
	di as txt "  Untreated (D=0):  " as result %10.0fc `N_untreated_obs'
	if `N_missing' > 0 {
		di as txt "  Missing:          " as result %10.0fc `N_missing' ///
			as txt " (" as result %5.2f `pct_missing' as txt "%)"
	}
	di as txt "  Treated firms:    " as result %10.0fc `N_treated_firms'
	di as txt "  Control firms:    " as result %10.0fc `N_control_firms'
	di as txt "  Treatment type:   " as result "`trt_type'"
	if `n_entry' > 0 | `n_exit' > 0 {
		di as txt "  Entry events:     " as result %10.0fc `n_entry'
		di as txt "  Exit events:      " as result %10.0fc `n_exit'
	}
	
	// nogenerate suppresses helper creation only; it must not weaken the support
	// checks that protect the production-function moments from empty cells.
	if `N_stable_0' == 0 {
		di as error "pte: no stable untreated observations (D=L.D=0)"
		di as error "  Assumption 3.3 condition (i) violated"
		if `pte_xtset_switched' {
			if `pte_had_xtset' {
				local pte_restore_delta_opt ""
				if "`pte_prev_delta'" != "" {
					local pte_restore_delta_opt "delta(`pte_prev_delta')"
				}
				capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
			}
			else {
				capture quietly xtset, clear
			}
		}
		exit 2001
	}
	if `N_stable_1' == 0 {
		di as error "pte: no stable treated observations (D=L.D=1)"
		di as error "  Assumption 3.3 condition (ii) violated"
		if `pte_xtset_switched' {
			if `pte_had_xtset' {
				local pte_restore_delta_opt ""
				if "`pte_prev_delta'" != "" {
					local pte_restore_delta_opt "delta(`pte_prev_delta')"
				}
				capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
			}
			else {
				capture quietly xtset, clear
			}
		}
		exit 2001
	}
	if `N_stable_0' < 30 {
		di as txt "  {bf:Warning}: Few stable untreated obs" ///
			" (`N_stable_0' < 30)"
	}
	if `N_stable_1' < 30 {
		di as txt "  {bf:Warning}: Few stable treated obs" ///
			" (`N_stable_1' < 30)"
	}

	if "`nogenerate'" == "" {
		// Build helper variables only after every validation gate passes so the
		// caller never loses a previously valid helper bundle on failure.
		if "`replace'" != "" & `"`pte_existing_helpers'"' != "" {
			drop `pte_existing_helpers'
		}
		qui bys `panelvar': egen double _pte_treat_year = ///
			min(cond(`_entry' == 1, `timevar', .))
		label variable _pte_treat_year "PTE: observed treatment entry year (e_i)"
		qui gen byte _pte_treat = `_ever_treated'
		label variable _pte_treat "PTE: ever-treated indicator"
		qui gen double _pte_first_treat_year = _pte_treat_year
		label variable _pte_first_treat_year "PTE: observed treatment entry year (alias)"
		qui gen byte _pte_D = `treatment'
		label variable _pte_D "PTE: treatment status (copy of `treatment')"
		qui gen double _pte_nt = (`timevar' - _pte_treat_year) / `pte_time_delta'
		qui replace _pte_nt = round(_pte_nt) if ///
			!missing(_pte_nt) & abs(_pte_nt - round(_pte_nt)) <= 1e-10
		label variable _pte_nt "PTE: relative time to observed treatment entry"
		tempvar _pte_mid_first_obs
		qui bys `panelvar' (`timevar'): gen byte `_pte_mid_first_obs' = (_n == 1)
		qui bys `panelvar' (`timevar'): gen byte _pte_mid = ///
			(_pte_D != L._pte_D) if !missing(L._pte_D)
		// The paper/DO convention assigns mid=0 only to the true first observed
		// row of a panel. Interior gaps with undefined lag treatment must stay
		// missing so downstream code does not mistake them for stable moments.
		qui replace _pte_mid = 0 if `_pte_mid_first_obs' & !missing(_pte_D)
		label variable _pte_mid "PTE: transition period indicator (D_t != D_{t-1})"
		qui gen double _pte_cohort = _pte_treat_year
		label variable _pte_cohort "PTE: treatment cohort (= observed entry year)"
		if "`trt_type'" == "absorbing" {
			capture assert _pte_mid == 1 if _pte_nt == 0 ///
				& !missing(_pte_nt)
			if _rc != 0 {
				di as txt "  {bf:Warning}: mid ⟺ nt==0 equivalence check failed"
				di as txt "    This may indicate data inconsistency"
			}
		}
		if "`verbose'" != "" {
			di as txt ""
			di as txt "{hline 60}"
			di as txt "Core Variable Diagnostics"
			di as txt "{hline 60}"
			di as txt "  Variables created:"
			di as txt "    _pte_treat_year        Observed treatment entry year"
			di as txt "    _pte_first_treat_year"
			di as txt "    _pte_nt                Relative time to observed entry"
			di as txt "    _pte_mid               Transition indicator"
			di as txt "    _pte_treat             Ever-treated indicator"
			di as txt "    _pte_cohort            Observed-entry cohort"
			di as txt "    _pte_D                 Treatment copy"
			di as txt ""
			di as txt "  Sample composition (Assumption 3.3):"
			di as txt "    Stable untreated (D=L.D=0):  " ///
				as result %10.0fc `N_stable_0'
			di as txt "    Stable treated (D=L.D=1):    " ///
				as result %10.0fc `N_stable_1'
			di as txt "    Transition obs (mid=1):      " ///
				as result %10.0fc `N_trans'
			di as txt ""
			di as txt "  Firm composition:"
			di as txt "    Treated firms:               " ///
				as result %10.0fc `N_treated_firms'
			di as txt "    Control firms:               " ///
				as result %10.0fc `N_control_firms'
			di as txt "    Number of cohorts:           " ///
				as result %10.0fc `n_cohorts'
			di as txt ""
			di as txt "  First-period D=1 firms:        " ///
				as result %10.0fc `n_first_d1' ///
				as txt " (" as result %4.1f `pct_first_d1' as txt "%)"
			if `pct_first_d1' > 10 {
				di as txt ""
				di as error "  Warning: >10% firms have D=1 at first observation"
				di as error "  These firms keep _pte_treat==1 but timing metadata stays missing"
				di as error "  This may indicate data truncation issues"
			}
			di as txt "{hline 60}"
		}
	}

	di as txt "=== Treatment Variable Verification: " ///
		as result "PASSED" as txt " ==="
	
	di as txt ""
	
	// r() mirrors the printed validation summary so later stages can branch on
	// the realized treatment law without reparsing console output.
	return clear
	return scalar N_obs = `N_total'
	return scalar N_treated_obs = `N_treated_obs'
	return scalar N_untreated_obs = `N_untreated_obs'
	return scalar N_missing = `N_missing'
	return scalar pct_treated = `pct_treated'
	return scalar N_treated_firms = `N_treated_firms'
	return scalar N_control_firms = `N_control_firms'
	return scalar N_entry_events = `n_entry'
	return scalar N_exit_events = `n_exit'
	return local trt_type "`trt_type'"
	return scalar treat_verified = 1
	
	// Stable-state counts are returned because later stages gate estimation and
	// diagnostics on the same support cells checked here.
	return scalar N_stable_0 = `N_stable_0'
	return scalar N_stable_1 = `N_stable_1'
	return scalar N_trans = `N_trans'
	return scalar n_first_d1 = `n_first_d1'
	return scalar pct_first_d1 = `pct_first_d1'
	return scalar n_cohorts = `n_cohorts'

	if `pte_xtset_switched' {
		if `pte_had_xtset' {
			local pte_restore_delta_opt ""
			if "`pte_prev_delta'" != "" {
				local pte_restore_delta_opt "delta(`pte_prev_delta')"
			}
			capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar', `pte_restore_delta_opt'
		}
		else {
			capture quietly xtset, clear
		}
	}
	
end
