*! _pte_transition.ado
*! Identifies transition observations for the CLK moment conditions.
*! Theorem 3.1 uses only stable-treatment rows with D_t = D_{t-1}; rows
*! with D_t != D_{t-1} are flagged as transition periods because the
*! switching dynamics depend on unobserved counterfactual productivity.
*! The program also builds the Appendix C.3 switch indicator G, checks
*! Assumption 3.3 support, and reports the sample counts consumed by the
*! downstream GMM workflow.

version 14.0
capture program drop _pte_transition
program define _pte_transition, rclass sortpreserve
	// sortpreserve is required because transition coding sorts on the literal
	// panel axis requested by the caller, then hands control back to programs
	// that may rely on the original row order.
	version 14.0
	
	// ================================================================
	// Match prodest-style abbreviated option names, but keep the caller's
	// exact panel axis and treatment variable. touse() restricts where output
	// variables and summary counts are materialized; it does not redefine the
	// true xtset lag used to compare D_t with D_{t-1}.
	syntax, TREATment(name) ID(name) Time(name) ///
		[MINsample(integer 30) REPLACE noREPORT HELP TOUSE(name)]
	
	// ================================================================
	// Help is fail-open: prefer the sthlp entry, but keep an inline contract so
	// callers can still inspect the generated variables and returned counts.
	// ================================================================
	if "`help'" != "" {
		// Try the sthlp file first; otherwise display the embedded summary.
		capture help _pte_transition
		if _rc {
			di as text ""
			di as text "{bf:_pte_transition} - Transition Period Identification for PTE"
			di as text ""
			di as text "{bf:Syntax}"
			di as text "    {cmd:_pte_transition}, {opt treat:ment(varname)} {opt id(varname)} {opt time(varname)}"
			di as text "        [{opt min:sample(#)} {opt replace} {opt norep:ort} {opt touse(varname)}]"
			di as text ""
			di as text "{bf:Description}"
			di as text "    Identifies transition period observations where treatment"
			di as text "    status changes (D_t != D_{t-1}) and validates Assumption 3.3"
			di as text "    from Chen, Liao & Schurter (2026)."
			di as text "    The primary generated variable is _pte_mid; mid is created"
			di as text "    only as a compatibility alias when that name is available."
			di as text ""
			di as text "{bf:Options}"
			di as text "    {opt treatment(varname)}  exact binary treatment indicator (0/1)"
			di as text "    {opt id(varname)}         exact panel identifier variable"
			di as text "    {opt time(varname)}       exact time variable"
			di as text "    {opt minsample(#)}        minimum sample size for warnings; default 30"
			di as text "    {opt replace}             overwrite existing _pte_mid/mid/G/mid_lag variables;"
			di as text "                              without replace, a user-owned {cmd:mid} is preserved"
			di as text "    {opt noreport}            suppress statistical report output"
			di as text "    {opt touse(varname)}      exact numeric sample indicator; marks rows to"
			di as text "                              store/report. Transition status still compares"
			di as text "                              actual panel neighbors D_t and D_{t-1}, but"
			di as text "                              stable-support counts require lag rows to"
			di as text "                              remain inside the same touse() contract"
			di as text ""
			di as text "{bf:Generated variables}"
			di as text "    _pte_mid         primary transition indicator"
			di as text "    mid              Legacy alias for _pte_mid when available"
			di as text "    G                switch indicator (+1 entry, -1 exit, 0 stable)"
			di as text "    mid_lag          lagged transition indicator L._pte_mid"
			di as text ""
			di as text "{bf:Stored results}"
			di as text "    r(n_trans)       number of transition period observations"
			di as text "    r(n_trans_up)    number of 0->1 transitions"
			di as text "    r(n_trans_down)  number of 1->0 transitions"
			di as text "    r(n_stable_0)    number of stable untreated observations"
			di as text "    r(n_stable_1)    number of stable treated observations"
			di as text "    r(n_total)       total number of active observations within {opt touse()}"
			di as text "    r(pct_excluded)  percent of observations that are transition periods"
			di as text "    r(n_lag_undefined) number of non-first observations whose D_{t-1}"
			di as text "                       is unusable (gap/missing or lag row outside touse())"
			di as text "    r(n_trans_lag)   number of lagged transition observations"
			di as text ""
			di as text "{bf:Reference}"
			di as text "    Chen, X., Liao, Y., & Schurter, K. (2026)."
			di as text "    Identifying Treatment Effects on Productivity."
			di as text ""
		}
		exit
	}
	
	// ================================================================
	// Default touse handling ( Task 6)
	// ================================================================
	// touse controls where outputs/statistics are materialized. It does not
	// redefine the panel history used by Eq.(3): transition status remains
	// D_it != D_i,t-1 on the observed panel, consistent with the paper and DOs.
	// If touse not provided, create default (all observations)
	if "`touse'" != "" {
		capture confirm variable `touse', exact
		if _rc {
			di as error "[pte] touse variable `touse' not found"
			exit 111
		}
		capture confirm numeric variable `touse'
		if _rc {
			di as error "[pte] touse variable `touse' must be numeric"
			exit 111
		}
	}
	if "`touse'" == "" {
		tempvar touse
		gen byte `touse' = 1
	}
	tempvar _pte_active_sample
	qui gen byte `_pte_active_sample' = (`touse' != 0 & !mi(`touse'))

	// Zero active observations is a data-availability failure, not an
	// Assumption 3.3 identification failure. Detect it before the
	// transition-coding and support-count logic below.
	quietly count if `_pte_active_sample'
	if r(N) == 0 {
		di as error "no observations"
		exit 2000
	}
	
	// ================================================================
	// Step 0: input validation
	// Keep prodest-style fail-close behavior: verify panel contract first,
	// then literal variable identity, then data admissibility, then writable
	// output names. Error codes follow standard Stata conventions.
	// ================================================================
	
	// Exact name matching matters because all later lag operators and support
	// counts must be computed on the caller's declared panel axis.
	// transition coding relies on the literal panel axis requested by the
	// caller. Silent abbreviation fallback would redirect L.D and all stable/
	// transition counts to a shadow panel declaration.
	capture confirm variable `id', exact
	if _rc {
		di as error "[pte] variable `id' not found"
		exit 111
	}
	capture confirm variable `time', exact
	if _rc {
		di as error "[pte] variable `time' not found"
		exit 111
	}
	capture confirm numeric variable `time'
	if _rc {
		di as error "[pte] variable `time' must be numeric"
		exit 111
	}

	// The paper's moment conditions are panel objects. Reject any caller whose
	// current xtset does not match id()/time(), rather than silently reinterpreting
	// L.D on a different axis.
	capture _xt, trequired
	if _rc {
		di as error "[pte] panel variable not set"
		di as error "use {bf:xtset} {it:panelvar timevar} before calling _pte_transition"
		exit 459
	}
	quietly xtset
	local _xt_panelvar "`r(panelvar)'"
	local _xt_timevar "`r(timevar)'"
	if "`_xt_panelvar'" != "`id'" | "`_xt_timevar'" != "`time'" {
		di as error "[pte] xtset must match id() and time()"
		di as error "  current xtset: `r(panelvar)' `r(timevar)'"
		di as error "  requested:     `id' `time'"
		di as error "  run {bf:xtset `id' `time'} before calling _pte_transition"
		exit 459
	}
	
	// Treatment is the structural state variable. Exact matching prevents Stata
	// abbreviation fallback from binding to the wrong D* column.
	capture confirm variable `treatment', exact
	if _rc {
		di as error "[pte] variable `treatment' not found"
		exit 111
	}

	capture confirm numeric variable `treatment'
	if _rc {
		di as error "[pte] variable `treatment' must be numeric"
		exit 111
	}
	
	// Binary treatment is required by the identification argument. The guard
	// extends to sampled-out rows that still supply the true L.D for active
	// observations, because touse() does not rewrite panel history.
	tempvar _pte_binary_guard
	qui gen byte `_pte_binary_guard' = `_pte_active_sample'
	qui replace `_pte_binary_guard' = 1 if F.`_pte_active_sample' != 0 & !mi(F.`_pte_active_sample')
	qui count if `_pte_binary_guard' & !inlist(`treatment', 0, 1) & !mi(`treatment')
	if r(N) > 0 {
		di as error "[pte] treatment must be 0/1"
		di as error "  found `=r(N)' non-binary observations in `treatment'"
		exit 450
	}
	
		// Treat missing-value share as a data-quality check on the live caller
		// contract, not on the full dataset.
		// When touse() is provided, the estimation sample is already defined by
		// the caller. Sample-outside missing values must not block a valid
		// Theorem 3.1 sample because they never enter transition coding or
		// Assumption 3.3 counts.
		// Missing share > 10% is treated as a fail-close data issue; smaller
		// shares are reported but allowed to continue.
		qui count if `_pte_active_sample' & mi(`treatment')
		local n_missing = r(N)
		qui count if `_pte_active_sample'
		local n_total_raw = r(N)
		if `n_missing' > 0 {
			local pct_missing = `n_missing' / `n_total_raw' * 100
			if `pct_missing' > 10 {
				di as error "[pte] `treatment' contains `n_missing' missing values (`=string(`pct_missing', "%5.2f")'%)"
				di as error "consider imputation or sample restriction"
				exit 416
			}
			else {
				di as text "[pte] Note: `treatment' has `n_missing' missing values (`=string(`pct_missing', "%5.2f")'%)"
			}
		}
	
	// The canonical outputs are _pte_mid, G, and mid_lag. mid remains only a
	// compatibility alias, so an existing user-owned exact mid is preserved
	// unless replace is explicit.
	local _create_mid_alias 1
	if "`replace'" != "" {
		local _has_existing = 0
		foreach var in _pte_mid mid G mid_lag {
			capture confirm variable `var', exact
			if !_rc local _has_existing = 1
		}
		if `_has_existing' {
			di as txt "(replacing existing _pte_mid/mid/mid_lag/G variables)"
			foreach var in _pte_mid mid G mid_lag {
				capture confirm variable `var', exact
				if !_rc {
					capture drop `var'
				}
			}
		}
	}
	else {
		foreach var in _pte_mid G mid_lag {
			capture confirm new variable `var'
			if _rc {
				di as error "[pte] variable `var' already exists"
				di as error "use {bf:replace} option to overwrite, or {bf:drop `var'} first"
				exit 110
			}
		}
		capture confirm new variable mid
		local _pte_mid_alias_conflict = (_rc != 0)
		if `_pte_mid_alias_conflict' {
			local _create_mid_alias 0
			// Existing exact mid is a permitted user-owned alias. Clear the
			// nonfatal confirm-new-variable rc so successful callers do not
			// inherit rc=110 from this compatibility branch.
			capture assert 1
		}
	}
	
	// minsample(0) intentionally disables the nonfatal small-sample warning.
	if `minsample' < 0 {
		di as error "[pte] minsample() must be non-negative"
		exit 198
	}
	
	// ================================================================
	// Step 1: build _pte_mid
	// Eq. (3) excludes rows with D_t != D_{t-1} because switching dynamics use
	// h^+/h^- objects that depend on unobserved counterfactual productivity.
	// Use the xtset lag operator, not the previous stored row, so panel gaps
	// leave the lag undefined instead of being bridged by accident.
	// ================================================================
	
	sort `id' `time'
	tempvar _pte_transition_defined _pte_first_panel_obs _pte_treat_lag _pte_prev_active_sample
	gen double `_pte_treat_lag' = L.`treatment' if `_pte_active_sample'
	by `id' (`time'): gen byte `_pte_transition_defined' = `_pte_active_sample' & !mi(`treatment', `_pte_treat_lag')
	by `id' (`time'): gen byte `_pte_first_panel_obs' = ///
		(_n == 1) & `_pte_active_sample' & !mi(`treatment')
	by `id' (`time'): gen byte `_pte_prev_active_sample' = ///
		(_n > 1) & `_pte_active_sample' & (`_pte_active_sample'[_n-1] == 1)
	gen byte _pte_mid = (`treatment' != `_pte_treat_lag') if `_pte_transition_defined'
	// Eq. (3): _pte_mid = 1{D_it != D_{it-1}}, only for touse observations.
	// Missing current/lagged treatment values remain undefined, handled below.
	// touse() only contracts the current rows that materialize _pte_mid/G. For
	// each active row, D_{t-1} still comes from the true panel lag L.D rather
	// than from the previous active row inside touse().
	// Sample-out rows stay missing as a visibility contract, not because the
	// underlying panel lag is undefined.
	
	// ================================================================
	// Step 2: treat the true first panel row as non-transition
	// The paper does not define a switching status when no lag exists. The DO
	// workflow effectively treats the first row as non-transition by dropping
	// it before the keep-if-mid!=1 step; pte keeps the row visible but sets
	// _pte_mid = 0 so later code can distinguish "first row" from "switching".
	// ================================================================
	
	// Panel-first observation with observed treatment: set mid = 0
	replace _pte_mid = 0 if `_pte_first_panel_obs'
	// True first panel row: no lagged panel state exists, so set it to 0.
	// Observations with missing current/lagged treatment remain missing
	// Non-touse observations: set mid = missing
	replace _pte_mid = . if !`_pte_active_sample'
	// Observations outside the sample keep undefined transition status.
	label variable _pte_mid "PTE: transition period indicator (1=transition)"
	
	if `_create_mid_alias' {
		gen byte mid = _pte_mid
		label variable mid "Legacy alias for _pte_mid"
	}
	
	// ================================================================
	// Step 2b: build the Appendix C.3 switch indicator
	// G preserves direction (+1 entry, -1 exit, 0 stable). This is useful for
	// non-absorbing designs even though Theorem 3.1 still discards all rows with
	// G != 0 from the production-function moments.
	// ================================================================
	
	gen byte G = sign(`treatment' - `_pte_treat_lag') if `_pte_transition_defined'
	// Eq. (C.3): G_it = sign(D_it - D_{it-1}), only for touse observations.
	replace G = 0 if `_pte_first_panel_obs'
	// True first panel row: G = 0 because no lagged panel state exists.
	// Observations with missing current/lagged treatment remain missing
	replace G = . if !`_pte_active_sample'
	// Non-touse observations remain undefined.
	label variable G "Treatment switch indicator (-1/0/+1)"
	
	// Internal guard: transition coding and switch direction must agree.
	qui count if !mi(_pte_mid, G) & (_pte_mid == 1) != (G != 0) & `_pte_active_sample'
	if r(N) > 0 {
		di as error "[pte] Internal error: mid and G inconsistency detected"
		exit 9
	}
	
	// ================================================================
	// Step 3: verify Assumption 3.3 support
	// Theorem 3.1 needs both stable untreated and stable treated rows, i.e.
	// support for D_t = D_{t-1} = 0 and D_t = D_{t-1} = 1. Exclude the true
	// first panel row from these counts because its _pte_mid = 0 is a coding
	// convention, not evidence of a stable lagged state.
	// ================================================================
	
	// Exclude the true first panel row from stable-support counts.
	// Count stable untreated observations (D = D_{-1} = 0) within the live
	// caller contract. A current active row whose lag supplier was sampled out
	// still materializes _pte_mid from the true panel lag, but it is not usable
	// for the keep-if GMM workflow and must not count as stable support.
	// Used for Eq. (8): E[omega(beta) - h_bar_0(omega_{-1}(beta)) | Z, D=D_{-1}=0] = 0.
	qui count if _pte_mid == 0 & `treatment' == 0 & ///
		`_pte_first_panel_obs' == 0 & `_pte_active_sample' & `_pte_prev_active_sample'
	local n_stable_0 = r(N)
	
	// Count stable treated observations (D = D_{-1} = 1) under the same live
	// caller contract.
	// Used for Eq. (9): E[omega(beta) - h_bar_1(omega_{-1}(beta)) | Z, D=D_{-1}=1] = 0.
	qui count if _pte_mid == 0 & `treatment' == 1 & ///
		`_pte_first_panel_obs' == 0 & `_pte_active_sample' & `_pte_prev_active_sample'
	local n_stable_1 = r(N)
	
	// Fail close when either support set is empty: the downstream GMM problem
	// is not identified on the caller's live sample.
	if `n_stable_0' == 0 {
		di as error "[pte] Assumption 3.3 violated: no stable D=0 observations"
		di as error "  Stable untreated (D=D_{-1}=0): 0"
		di as error "  Theorem 3.1 requires consecutive untreated periods for moment condition (8)"
		di as error "  See Chen, Liao & Schurter (2026) Section 3.2"
		exit 498
	}
	if `n_stable_1' == 0 {
		di as error "[pte] Assumption 3.3 violated: no stable D=1 observations"
		di as error "  Stable treated (D=D_{-1}=1): 0"
		di as error "  Theorem 3.1 requires consecutive treated periods for moment condition (9)"
		di as error "  See Chen, Liao & Schurter (2026) Section 3.2"
		exit 498
	}
	
	// ================================================================
	// Step 4: emit a nonblocking small-sample warning
	// The paper does not impose a threshold; this is a package-level warning
	// that the stable-support cells may be too thin for reliable GMM behavior.
	// ================================================================
	
	if `minsample' > 0 {
		if `n_stable_0' < `minsample' {
			di as txt ""
			di as txt "[pte] Warning: only `n_stable_0' stable D=0 obs (recommended >= `minsample')"
			di as txt "  GMM asymptotic properties may not hold; estimates may be unreliable"
		}
		if `n_stable_1' < `minsample' {
			di as txt ""
			di as txt "[pte] Warning: only `n_stable_1' stable D=1 obs (recommended >= `minsample')"
			di as txt "  GMM asymptotic properties may not hold; estimates may be unreliable"
		}
	}
	
	// ================================================================
	// Step 5: compute transition diagnostics used by reporting and r()
	// ================================================================
	
	// These are the rows the DO workflow later removes with keep/drop if mid!=1.
	qui count if _pte_mid == 1 & `_pte_active_sample'
	local n_trans = r(N)
	
	// 0->1 entries are the positive-switch rows associated with h_plus.
	qui count if G == 1 & `_pte_active_sample'
	local n_trans_up = r(N)
	
	// 1->0 exits only appear in non-absorbing designs and correspond to h_minus.
	qui count if G == -1 & `_pte_active_sample'
	local n_trans_down = r(N)
	
	// Seeing any exit implies a non-absorbing treatment path in the live data.
	if `n_trans_down' > 0 & "`report'" == "" {
		di as txt ""
		di as txt "[pte] Note: Non-absorbing treatment detected (`n_trans_down' obs with D: 1->0)"
		di as txt "      See paper Appendix C.3 for theoretical justification"
	}
	
	// Total active rows in the caller contract.
	qui count if `_pte_active_sample'
	local n_total = r(N)
	
	// Non-first observations whose lagged treatment is unusable under the live
	// caller contract. This includes true xtset gaps/missing lags as well as
	// rows whose lag supplier was sampled out by touse()/if/in.
	tempvar _pte_not_first
	by `id' (`time'): gen byte `_pte_not_first' = (_n > 1)
	qui count if `_pte_not_first' & `_pte_active_sample' & !mi(`treatment') & ///
		(mi(`_pte_treat_lag') | `_pte_prev_active_sample' != 1)
	local n_lag_undefined = r(N)
	
	// Transition-period share. Lag-undefined observations are
	// reported separately via n_lag_undefined to preserve pct_excluded's
	// historical meaning as the share of transition periods.
	local pct_excluded = `n_trans' / `n_total' * 100
	
	// ================================================================
	// Step 6: build mid_lag
	// The current DO code mainly uses mid itself, but a lagged transition flag
	// is useful for debugging, for future exclusion rules, and for checking how
	// close stable-support rows sit to a switching period.
	// ================================================================
	
	gen byte mid_lag = L._pte_mid if `_pte_active_sample'
	// mid_lag_it = _pte_mid_{i,t-1}, only for touse observations.
	by `id' (`time'): replace mid_lag = 0 if ///
		`_pte_first_panel_obs' == 1 & `_pte_active_sample' & !mi(_pte_mid)
	// True first panel row: set to 0; lag-undefined followers stay missing.
	replace mid_lag = . if !`_pte_active_sample'
	// Non-touse observations remain undefined.
	label variable mid_lag "Lagged transition period indicator"
	
	// Count lagged-transition rows for the diagnostic report.
	qui count if mid_lag == 1 & `_pte_active_sample'
	local n_trans_lag = r(N)
	
	// ================================================================
	// Step 7: formatted report
	// Report only the quantities that define the downstream GMM sample and the
	// main sources of support loss: switching rows, missing/unusable lags, and
	// the stable D=0 / D=1 cells required by Assumption 3.3.
	// ================================================================
	
	if "`report'" == "" {
		di as txt ""
		di as txt "{hline 60}"
		di as txt "Transition Period Identification"
		di as txt "{hline 60}"
		di as txt _col(3) "Total observations:" _col(40) as result %10.0fc `n_total'
		di as txt _col(3) "Transition period observations:" _col(40) as result %10.0fc `n_trans' as txt " (excluded)"
		// Show the switch-direction split only when exits are present.
		if `n_trans_down' > 0 {
			di as txt _col(5) "0->1 transitions (G=+1):" _col(40) as result %10.0fc `n_trans_up'
			di as txt _col(5) "1->0 transitions (G=-1):" _col(40) as result %10.0fc `n_trans_down'
		}
		di as txt _col(3) "Stable untreated (D=D_{-1}=0):" _col(40) as result %10.0fc `n_stable_0'
		// Eq. (8) support count.
		di as txt _col(3) "Stable treated (D=D_{-1}=1):" _col(40) as result %10.0fc `n_stable_1'
		// Eq. (9) support count.
		di as txt _col(3) "Transition-period share:" _col(40) as result %9.2f `pct_excluded' as txt "%"
		di as txt _col(3) "Lag-unusable observations:" _col(40) as result %10.0fc `n_lag_undefined'
		di as txt "{hline 60}"
		di as txt _col(3) "Lagged transition observations:" _col(40) as result %10.0fc `n_trans_lag'
		di as txt "{hline 60}"
		di as txt ""
	}
	
	// ================================================================
	// Step 8: store r() results
	// These counts are consumed by downstream production-function orchestration
	// and by diagnostic surfaces that need the exact same live-sample contract.
	// ================================================================
	
	return scalar n_trans = `n_trans'           // transition rows
	return scalar n_trans_up = `n_trans_up'     // 0->1 switches
	return scalar n_trans_down = `n_trans_down' // 1->0 switches
	return scalar n_stable_0 = `n_stable_0'     // Eq. (8) support
	return scalar n_stable_1 = `n_stable_1'     // Eq. (9) support
	return scalar n_total = `n_total'           // active rows
	return scalar pct_excluded = `pct_excluded' // transition-period share (%)
	return scalar n_lag_undefined = `n_lag_undefined' // non-first obs with unusable D_{t-1}
	return scalar n_trans_lag = `n_trans_lag'   // rows with lagged transition

	// Callers such as _pte_prodfunc branch immediately on _rc after invoking
	// _pte_transition. Force a clean success code here so internal compatibility
	// probes cannot leak a stale captured return code into the calling program.
	exit 0
	
end
