*! _pte_setup_panel.ado
*! Detect or repair xtset/tsset state and return panel diagnostics for pte_setup.

version 14.0
capture program drop _pte_setup_panel
program define _pte_setup_panel, rclass
	version 14.0
	
	// Check for an empty dataset before syntax parsing so the helper can emit
	// a clean setup error instead of failing on missing varname metadata.
	
	qui count
	if r(N) == 0 {
		di as error "[pte] no observations in dataset"
		exit 2000
	}
	
	syntax , TREATment(name) [ID(name) Time(name) VERbose]

	capture confirm variable `treatment', exact
	if _rc != 0 {
		di as error "[pte] treatment variable `treatment' not found"
		exit 111
	}

	if "`id'" != "" {
		capture confirm variable `id', exact
		if _rc != 0 {
			di as error "[pte] panel id variable `id' not found"
			di as error "id() must match an existing variable name exactly"
			exit 111
		}
		capture confirm numeric variable `id'
		if _rc != 0 {
			di as error "[pte] panel id variable `id' must be numeric"
			exit 111
		}
	}
	if "`time'" != "" {
		capture confirm variable `time', exact
		if _rc != 0 {
			di as error "[pte] time variable `time' not found"
			di as error "time() must match an existing variable name exactly"
			exit 111
		}
		capture confirm numeric variable `time'
		if _rc != 0 {
			di as error "[pte] time variable `time' must be numeric"
			exit 111
		}
	}

	// Read the caller's current xtset declaration first. PTE accepts an
	// already-configured panel, but it may need to refine that declaration
	// when the user supplies only one axis as an override.
	local panel_already_set = 0
	local panelvar ""
	local timevar ""
	local pte_prev_panel ""
	local pte_prev_time ""
	local pte_prev_delta ""
	local pte_active_delta ""
	local pte_target_delta ""
	local pte_xtset_sw 0
	
	capture xtset
	if _rc == 0 {
		local panelvar "`r(panelvar)'"
		local timevar "`r(timevar)'"
		local pte_prev_panel "`r(panelvar)'"
		local pte_prev_time "`r(timevar)'"
		local pte_prev_delta "`r(tdelta)'"
		local pte_active_delta "`r(tdelta)'"
		local panel_already_set = 1
		
		if "`verbose'" != "" {
			di as txt "[pte] panel structure detected: panelvar=`panelvar', timevar=`timevar'"
		}
	}

	// Panel-only xtset is not enough for event time, transition detection, or
	// lag operators. Require a time axis now unless time() can repair it.
	if `panel_already_set' == 1 & "`timevar'" == "" & "`time'" == "" {
		di as error "[pte] panel time variable not set"
		di as error "use {bf:xtset} {it:panelvar timevar}, specify {bf:time()} to complete the current panel declaration, or specify both {bf:id()} and {bf:time()} options"
		exit 459
	}
	
	if `panel_already_set' == 0 {
		if "`id'" == "" | "`time'" == "" {
			di as error "[pte] panel structure not set"
			di as error "use {bf:xtset} {it:panelvar timevar} or specify both {bf:id()} and {bf:time()} options"
			exit 459
		}
		
		// A fully missing time axis would let xtset parse but would make every
		// event-time object degenerate, so reject it explicitly.
		qui count if !mi(`time')
		if r(N) == 0 {
			di as error "[pte] time variable `time' is all missing"
			exit 2005
		}
		
		tempvar _pte_gap_probe
		qui bysort `id' (`time'): gen double `_pte_gap_probe' = ///
			`time' - `time'[_n-1] if _n > 1
		qui count if !mi(`_pte_gap_probe')
		if r(N) > 0 {
			qui su `_pte_gap_probe', meanonly
			if r(min) > 0 & abs(r(max) - r(min)) <= 1e-10 {
				local pte_target_delta : display %21.0g r(min)
				local pte_target_delta = strtrim("`pte_target_delta'")
			}
		}

		// When the observed gap is constant, carry that delta into xtset so
		// ts operators later inherit the panel's actual spacing.
		if "`pte_target_delta'" != "" {
			capture qui xtset `id' `time', delta(`pte_target_delta')
			if _rc != 0 {
				qui xtset `id' `time'
			}
		}
		else {
			qui xtset `id' `time'
		}
		local panelvar "`id'"
		local timevar "`time'"
		quietly xtset
		local pte_active_delta "`r(tdelta)'"
		
		if "`verbose'" != "" {
			di as txt "[pte] panel structure set: xtset `panelvar' `timevar'"
		}
	}
	else {
		// Explicit overrides apply axis by axis; any omitted axis inherits the
		// caller's current xtset declaration instead of forcing a full reset.
		if "`id'" != "" {
			local panelvar "`id'"
		}
		if "`time'" != "" {
			local timevar "`time'"
		}
		if "`id'`time'" != "" {
			tempvar _pte_gap_probe
			qui bysort `panelvar' (`timevar'): gen double `_pte_gap_probe' = ///
				`timevar' - `timevar'[_n-1] if _n > 1
			qui count if !mi(`_pte_gap_probe')
			if r(N) > 0 {
				qui su `_pte_gap_probe', meanonly
				if r(min) > 0 & abs(r(max) - r(min)) <= 1e-10 {
					local pte_target_delta : display %21.0g r(min)
					local pte_target_delta = strtrim("`pte_target_delta'")
				}
			}

			if "`pte_target_delta'" != "" {
				capture qui xtset `panelvar' `timevar', delta(`pte_target_delta')
				if _rc != 0 {
					qui xtset `panelvar' `timevar'
				}
			}
			else {
				qui xtset `panelvar' `timevar'
			}
			quietly xtset
			local pte_active_delta "`r(tdelta)'"
			if "`pte_prev_panel'" != "`panelvar'" ///
				| "`pte_prev_time'" != "`timevar'" ///
				| strtrim("`pte_prev_delta'") != strtrim("`pte_active_delta'") {
				local pte_xtset_sw 1
			}
			
			if "`verbose'" != "" {
				di as txt "[pte] panel structure re-set: xtset `panelvar' `timevar'"
			}
		}
		else if "`timevar'" != "" {
			tempvar _pte_gap_probe
			qui bysort `panelvar' (`timevar'): gen double `_pte_gap_probe' = ///
				`timevar' - `timevar'[_n-1] if _n > 1
			qui count if !mi(`_pte_gap_probe')
			if r(N) > 0 {
				qui su `_pte_gap_probe', meanonly
				if r(min) > 0 & abs(r(max) - r(min)) <= 1e-10 {
					local pte_target_delta : display %21.0g r(min)
					local pte_target_delta = strtrim("`pte_target_delta'")
				}
			}
			if "`pte_target_delta'" != "" & ///
				strtrim("`pte_active_delta'") != strtrim("`pte_target_delta'") {
				capture qui xtset `panelvar' `timevar', delta(`pte_target_delta')
				if _rc != 0 {
					qui xtset `panelvar' `timevar'
				}
				quietly xtset
				local pte_active_delta "`r(tdelta)'"
				local pte_xtset_sw 1
			}
		}
	}
	
	local xtdesc_ok = 0
	capture qui xtdescribe
	if _rc == 0 {
		local xtdesc_ok = 1
		local n_obs = r(sum)
		local n_groups = r(N)
		local min_periods = r(min)
		local mean_periods = r(mean)
		local max_periods = r(max)
	}
	else {
		// xtdescribe can fail on degenerate panels. The manual fallback keeps
		// setup diagnostics available even when the sample has one time period.
		qui count
		local n_obs = r(N)
		tempvar _nper
		qui bys `panelvar': gen long `_nper' = _N
		qui su `_nper', meanonly
		local n_groups = r(N) / r(mean)
		qui tab `panelvar'
		local n_groups = r(r)
		local min_periods = r(min)
		local max_periods = r(max)
		qui su `_nper'
		local min_periods = r(min)
		local mean_periods = r(mean)
		local max_periods = r(max)
	}
	
	local balanced = (`min_periods' == `max_periods')
	
	// n_patterns is coarse by design: it counts distinct panel lengths, not
	// full calendars. That is enough for setup diagnostics without recreating
	// xtdescribe's full pattern listing in r().
	local n_patterns = 1
	if !`balanced' {
		tempvar _n_periods
		qui bys `panelvar': gen long `_n_periods' = _N
		qui tab `_n_periods'
		local n_patterns = r(r)
	}
	
	if "`verbose'" != "" {
		di as txt ""
		di as txt "{hline 60}"
		di as txt "Panel Structure Summary"
		di as txt "{hline 60}"
		if `xtdesc_ok' {
			xtdescribe, patterns(5)
		}
		else {
			di as txt "[pte] xtdescribe unavailable (single time period?)"
			di as txt _col(5) "N groups:    " as result "`n_groups'"
			di as txt _col(5) "N obs:       " as result "`n_obs'"
			di as txt _col(5) "Min periods: " as result "`min_periods'"
			di as txt _col(5) "Max periods: " as result "`max_periods'"
		}
		di as txt "{hline 60}"
		di as txt ""
	}
	
	// Gap diagnostics expose irregular spacing before downstream code starts
	// using lags and event time as if the panel were evenly spaced.
	tempvar _gap
	qui bys `panelvar' (`timevar'): gen double `_gap' = `timevar' - `timevar'[_n-1] if _n > 1
	
	qui count if !mi(`_gap')
	local n_gaps = r(N)
	
	if `n_gaps' > 0 {
		qui su `_gap', detail
		local gap_mean = r(mean)
		local gap_sd = r(sd)
		local gap_min = r(min)
		local gap_max = r(max)
	}
	else {
		local gap_mean = .
		local gap_sd = 0
		local gap_min = .
		local gap_max = .
	}
	
	// Treat near-zero dispersion as regular spacing to avoid false negatives
	// from floating-point representations of integer time steps.
	if `gap_sd' <= 0.001 {
		local regular = 1
	}
	else {
		local regular = 0
	}
	
	if "`verbose'" != "" {
		di as txt "[pte] Time gap statistics:"
		di as txt _col(5) "Mean gap:  " as result %9.4f `gap_mean'
		di as txt _col(5) "SD gap:    " as result %9.4f `gap_sd'
		di as txt _col(5) "Min gap:   " as result %9.4f `gap_min'
		di as txt _col(5) "Max gap:   " as result %9.4f `gap_max'
		di as txt _col(5) "Regular:   " as result "`regular'"
		di as txt _col(5) "Balanced:  " as result "`balanced'"
	}
	
	// tsset mirrors the active xtset declaration so lag operators work in the
	// rest of the setup pipeline. A failure here is informational when the
	// sample has no usable time variation.
	local pte_tsset_delta_opt ""
	if "`pte_active_delta'" != "" {
		local pte_tsset_delta_opt ", delta(`pte_active_delta')"
	}
	capture qui tsset `panelvar' `timevar'`pte_tsset_delta_opt'
	if _rc != 0 & "`verbose'" != "" {
		di as txt "[pte] Note: tsset could not be applied (single time period?)"
		di as txt "      lag/lead operators (L. F.) will not be available"
	}
	
	return local panelvar "`panelvar'"
	return local timevar "`timevar'"
	return local tdelta "`pte_active_delta'"
	
	return scalar n_obs = `n_obs'
	return scalar n_groups = `n_groups'
	return scalar n_patterns = `n_patterns'
	return scalar min_periods = `min_periods'
	return scalar mean_periods = `mean_periods'
	return scalar max_periods = `max_periods'
	return scalar gap_mean = `gap_mean'
	return scalar gap_sd = `gap_sd'
	return scalar gap_min = `gap_min'
	return scalar gap_max = `gap_max'
	return scalar balanced = `balanced'
	return scalar regular = `regular'
	
	di as txt "[pte] Panel: `panelvar' x `timevar' | " ///
		as result "`n_groups'" as txt " groups, " ///
		as result "`n_obs'" as txt " obs, " ///
		cond(`balanced', "balanced", "unbalanced") ", " ///
		cond(`regular', "regular", "irregular gaps")

	// Restore the caller's original xtset state when this helper had to
	// temporarily reset axes or delta just to compute diagnostics.
	if `pte_xtset_sw' {
		local pte_restore_delta_opt ""
		if "`pte_prev_delta'" != "" {
			local pte_restore_delta_opt "delta(`pte_prev_delta')"
		}
		capture quietly sort `pte_prev_panel' `pte_prev_time'
		capture quietly xtset `pte_prev_panel' `pte_prev_time', `pte_restore_delta_opt'
	}
	
end
