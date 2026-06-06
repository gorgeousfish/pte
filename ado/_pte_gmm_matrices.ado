*! _pte_gmm_matrices.ado
*! Prepares the sample and lagged inputs for the Theorem 3.1
*! GMM step before Mata constructs X, Z, and OMEGA_LAG_POL.
*! Transition periods are excluded, W is based on Z'Z/N, and the translog
*! Z matrix uses the mixed lag l1k_lag = L.lnl * lnk_t rather than the
*! fully lagged interaction.

version 14.0
capture program drop _pte_gmm_matrices
program define _pte_gmm_matrices, rclass
    version 14.0

    // Use name instead of varname so abbreviated state-variable names cannot
    // slip past syntax parsing before exact variable contracts are enforced.
    // NOTE: Option names avoid digits to prevent Stata syntax parser
    //       abbreviation conflicts. L2→LSQ, K2→KSQ, L1K1→LK.
    syntax, PHI(name) LNL(name) LNK(name) ///
        TREATpost(name) MID(name) T(name) ///
        ID(name) TIME(name) ///
        [PRODFUNC(string) OMEGAPOLY(integer 3) ///
         LSQ(name) KSQ(name) LK(name) ///
         GMMSAMPLE(name) DOPOOLEDZ]
    
    // Map syntax locals to internal names
    local treat_post "`treatpost'"
    local l2 "`lsq'"
    local k2 "`ksq'"
    local l1k1 "`lk'"

    // Keep CD as the default public contract.
    if "`prodfunc'" == "" {
        local prodfunc "cd"
    }

    if !inlist("`prodfunc'", "cd", "translog") {
        di as error "{bf:_pte_gmm_matrices}: prodfunc must be 'cd' or 'translog'"
        di as error "  Specified: `prodfunc'"
        exit 198
    }

    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "{bf:_pte_gmm_matrices}: omegapoly must be between 1 and 4"
        di as error "  Specified: `omegapoly'"
        exit 198
    }

    // Note: omegapoly controls the evolution polynomial order, which is
    // INDEPENDENT of the production function type (CD vs translog).
    // The replication code uses CD + omegapoly=3 (3rd order polynomial).
    // Both CD and translog support omegapoly=1~4.

    // Fail early if the caller's first-stage contract is incomplete.
    capture confirm variable `phi', exact
    if _rc {
        di as error "{bf:_pte_gmm_matrices}: variable {bf:`phi'} not found"
        exit 111
    }

    foreach var in `lnl' `lnk' `treat_post' `mid' `t' `id' `time' {
        capture confirm variable `var', exact
        if _rc {
            di as error "{bf:_pte_gmm_matrices}: variable {bf:`var'} not found"
            exit 111
        }
    }

    // GMM inputs must remain numeric all the way into Mata.
    capture confirm numeric variable `phi'
    if _rc {
        di as error "{bf:_pte_gmm_matrices}: variable {bf:`phi'} is not numeric"
        exit 109
    }

    foreach var in `lnl' `lnk' `treat_post' `mid' `t' {
        capture confirm numeric variable `var'
        if _rc {
            di as error "{bf:_pte_gmm_matrices}: variable {bf:`var'} is not numeric"
            exit 109
        }
    }

    // Lag semantics must match xtset, not raw row adjacency.
    capture _xt, trequired
    if _rc {
        di as error "{bf:_pte_gmm_matrices}: data not xtset"
        di as error "Please run: xtset `id' `time'"
        exit 459
    }
    // Respect the declared xtset delta() whenever the active panel declaration
    // already matches id()/time(). The reference DOs use Stata's L. operator,
    // so sparse grids such as 2000, 2004, 2008 under delta(2) must NOT be
    // treated as adjacent periods. For older direct-helper callers that keep
    // a different ambient xtset while passing explicit id()/time(), fall back
    // to the historical id()/time()-based spacing probe.
    quietly xtset
    local _xt_panelvar "`r(panelvar)'"
    local _xt_timevar "`r(timevar)'"
    local _tsdelta = .
    if "`_xt_panelvar'" == "`id'" & "`_xt_timevar'" == "`time'" {
        local _tsdelta = real("`r(tdelta)'")
    }

    tempvar _pte_delta_probe
    qui sort `id' `time'
    qui by `id' (`time'): gen double `_pte_delta_probe' = ///
        `time' - `time'[_n-1] if _n > 1 & !mi(`time', `time'[_n-1])
    if missing(`_tsdelta') | `_tsdelta' <= 0 {
        qui summarize `_pte_delta_probe' if `_pte_delta_probe' > 0, meanonly
        local _tsdelta = r(min)
    }
    if missing(`_tsdelta') | `_tsdelta' <= 0 {
        local _tsdelta = 1
    }
    local _tsdelta_tol = max(1e-10, abs(`_tsdelta') * 1e-10)

    // Validate binary encodings only on the contracted working sample and on
    // rows that can feed a real lag into that sample. Unrelated sample-out
    // panels and gap-separated pseudo-neighbors must not veto the current
    // GMM contract.
    tempvar _pte_mid_guard _pte_treat_guard _pte_true_transition_row _pte_missing_transition_status
    qui sort `id' `time'
    qui by `id' (`time'): gen byte `_pte_true_transition_row' = ///
        (_n > 1 & abs((`time' - `time'[_n-1]) - `_tsdelta') <= `_tsdelta_tol' & ///
        `treat_post' != `treat_post'[_n-1]) if !mi(`treat_post', `treat_post'[_n-1])
    qui by `id' (`time'): gen byte `_pte_missing_transition_status' = ///
        (_n > 1 & abs((`time' - `time'[_n-1]) - `_tsdelta') <= `_tsdelta_tol' & ///
        (mi(`treat_post') | mi(`treat_post'[_n-1])))
    qui count if `_pte_missing_transition_status' == 1
    local N_missing_transition_status = r(N)
    qui replace `_pte_true_transition_row' = 0 if missing(`_pte_true_transition_row')
    if "`gmmsample'" != "" {
        capture confirm variable `gmmsample', exact
        if _rc {
            di as error "{bf:_pte_gmm_matrices}: variable {bf:`gmmsample'} not found"
            exit 111
        }
        capture confirm numeric variable `gmmsample'
        if _rc {
            di as error "{bf:_pte_gmm_matrices}: variable {bf:`gmmsample'} is not numeric"
            exit 109
        }
        tempvar _pte_true_lag_supplier
        qui sort `id' `time'
        qui by `id' (`time'): gen byte `_pte_true_lag_supplier' = ///
            (_n < _N & `gmmsample'[_n+1] != 0 & !missing(`gmmsample'[_n+1]) & ///
            abs((`time'[_n+1] - `time') - `_tsdelta') <= `_tsdelta_tol')
        qui by `id' (`time'): gen byte `_pte_mid_guard' = ///
            (`gmmsample' != 0 & !missing(`gmmsample'))
        qui replace `_pte_mid_guard' = 1 if `_pte_true_lag_supplier'
        qui gen byte `_pte_treat_guard' = (`gmmsample' != 0 & !missing(`gmmsample'))
        qui by `id' (`time'): replace `_pte_treat_guard' = 1 if ///
            `_pte_true_lag_supplier' & `_pte_true_transition_row' == 1
    }
    else {
        qui gen byte `_pte_mid_guard' = 1
        qui gen byte `_pte_treat_guard' = 1
    }

    // Missing values are allowed here because later filters can still remove
    // unusable rows without corrupting the binary encoding contract.
    // Theorem 3.1 requires transition periods to be encoded exactly as mid==1.
    // Treating "two distinct levels" as sufficient would incorrectly admit
    // invalid encodings such as {0,2} into the GMM sample.
    qui count if `_pte_mid_guard' & !missing(`mid') & !inlist(`mid', 0, 1)
    if r(N) > 0 {
        di as error "{bf:_pte_gmm_matrices}: mid must contain only 0/1 values"
        di as error "  Invalid observations: " %10.0fc r(N)
        exit 459
    }

    qui count if `_pte_treat_guard' & !missing(`treat_post') & !inlist(`treat_post', 0, 1)
    if r(N) > 0 {
        di as error "{bf:_pte_gmm_matrices}: treat_post must contain only 0/1 values"
        di as error "  Invalid observations: " %10.0fc r(N)
        exit 459
    }

    // Translog requires the current-period quadratic terms and the fully
    // lagged interaction used in X_lag. The mixed lag is created below.
    local translog_mixed_lag_degenerate = 0
    if "`prodfunc'" == "translog" {
        if "`l2'" == "" | "`k2'" == "" | "`l1k1'" == "" {
            di as error "{bf:_pte_gmm_matrices}: Translog requires lsq(), ksq(), lk() options"
            exit 198
        }
        foreach var in `l2' `k2' `l1k1' {
            capture confirm variable `var', exact
            if _rc {
                di as error "{bf:_pte_gmm_matrices}: variable {bf:`var'} not found"
                exit 111
            }
        }
    }

    // Rebuild the package-owned Mata runtime before calling the matrix
    // constructor. Checking for any same-name accessor is not enough: old DO
    // helpers or a stale package build can leave a compatible-looking Mata
    // namespace with an incompatible _pte_construct_gmm_matrices() signature.
    capture quietly _pte_mata_init, force nolog
    local _mata_init_rc = _rc
    if `_mata_init_rc' != 0 | r(all_loaded) != 1 {
        // Functions not yet compiled; locate the Mata source via adopath.
        local _mata_found 0
        
        // Resolve mata/pte_gmm_matrices.mata from the ado file itself so the
        // loader is robust to caller-side working-directory changes.
        capture quietly findfile _pte_gmm_matrices.ado
        if !_rc {
            local _self_path "`r(fn)'"
            local _ado_dir : subinstr local _self_path "_pte_gmm_matrices.ado" ""
            local _mata_dir : subinstr local _ado_dir "/ado/" "/mata/"
            local _mata_file "`_mata_dir'pte_gmm_matrices.mata"
            capture quietly do "`_mata_file'"
            if !_rc {
                local _mata_found 1
            }
        }
        
        // Fall back to common in-repo paths for direct developer runs.
        if `_mata_found' == 0 {
            capture quietly do "`c(pwd)'/mata/pte_gmm_matrices.mata"
            if !_rc {
                local _mata_found 1
            }
        }
        if `_mata_found' == 0 {
            capture quietly do "mata/pte_gmm_matrices.mata"
            if !_rc {
                local _mata_found 1
            }
        }
        
        if `_mata_found' == 0 {
            di as error "{bf:_pte_gmm_matrices}: Cannot load mata/pte_gmm_matrices.mata"
            di as error "  Ensure the file exists in the mata/ directory"
            di as error "  Current working directory: `c(pwd)'"
            exit 601
        }
    }

    // Report the effective contract that will feed Mata.
    di as text ""
    di as text "{hline 60}"
    di as text "GMM Matrix Construction"
    di as text "{hline 60}"
    di as text _col(3) "Production function:" _col(40) as result "`prodfunc'"
    di as text _col(3) "Omega polynomial order:" _col(40) as result `omegapoly'

    // Work on a preserved copy because this helper materializes temporary lag
    // variables and a filtered GMM sample before handing control to Mata.
    preserve

    // CRITICAL: Reference code uses L. operator which returns missing for
    // panel gaps (non-consecutive years). by-sort [_n-1] does NOT respect
    // panel gaps. We must detect gaps and set lags to missing accordingly.
    // Bug fix: 769 extra observations were included due to this difference.
    sort `id' `time'
    
    // Detect panel gaps using xtset delta(): L.x is non-missing only when
    // the previous row in panel is exactly one declared panel period earlier.
    cap drop _pte_has_gap
    by `id' (`time'): gen byte _pte_has_gap = (abs((`time' - `time'[_n-1]) - `_tsdelta') > `_tsdelta_tol') if _n > 1
    by `id' (`time'): replace _pte_has_gap = 1 if _n == 1
    
    // phi_lag
    cap drop phi_lag
    by `id' (`time'): gen double phi_lag = `phi'[_n-1]
    replace phi_lag = . if _pte_has_gap == 1
    label variable phi_lag "Lagged phi"
    
    // lnl_lag
    cap drop lnl_lag
    by `id' (`time'): gen double lnl_lag = `lnl'[_n-1]
    replace lnl_lag = . if _pte_has_gap == 1
    label variable lnl_lag "Lagged log labor"
    
    // lnk_lag
    cap drop lnk_lag
    by `id' (`time'): gen double lnk_lag = `lnk'[_n-1]
    replace lnk_lag = . if _pte_has_gap == 1
    label variable lnk_lag "Lagged log capital"
    
    // treat_post_lag
    cap drop treat_post_lag
    by `id' (`time'): gen double treat_post_lag = `treat_post'[_n-1]
    replace treat_post_lag = . if _pte_has_gap == 1
    label variable treat_post_lag "Lagged treatment status"
    
    // mid_lag (for reference, not used in matrices)
    cap drop mid_lag
    by `id' (`time'): gen double mid_lag = `mid'[_n-1]
    replace mid_lag = . if _pte_has_gap == 1
    label variable mid_lag "Lagged transition indicator"

    // Build the fully lagged translog regressors used in X_lag.
    if "`prodfunc'" == "translog" {
        cap drop l2_lag
        by `id' (`time'): gen double l2_lag = `l2'[_n-1]
        replace l2_lag = . if _pte_has_gap == 1
        label variable l2_lag "Lagged log labor squared"
        
        cap drop k2_lag
        by `id' (`time'): gen double k2_lag = `k2'[_n-1]
        replace k2_lag = . if _pte_has_gap == 1
        label variable k2_lag "Lagged log capital squared"
        
        // This is the fully lagged interaction that belongs in X_lag.
        cap drop l1k1_lag
        by `id' (`time'): gen double l1k1_lag = `l1k1'[_n-1]
        replace l1k1_lag = . if _pte_has_gap == 1
        label variable l1k1_lag "Lagged labor-capital interaction (full lag)"
    }

    // Match the DO layout, where the constant enters both Z and OMEGA_LAG_POL.
    cap drop const
    gen byte const = 1
    label variable const "Constant"

    // The translog Z matrix uses lagged labor times current capital. Capital
    // is a state variable chosen at t-1, so lnk_t is the paper/DO instrument.
    if "`prodfunc'" == "translog" {
        cap drop l1k_lag
        gen double l1k_lag = lnl_lag * `lnk'
        label variable l1k_lag "Mixed lag: L.lnl × lnk (for Z matrix)"

        // Keep a visible diagnostic because confusing l1k_lag with l1k1_lag
        // changes the identified instrument set while still looking plausible.
        tempvar diff_l1k scale_l1k
        gen double `diff_l1k' = abs(l1k_lag - l1k1_lag) if !mi(l1k_lag) & !mi(l1k1_lag)
        gen double `scale_l1k' = abs(l1k1_lag) if !mi(l1k_lag) & !mi(l1k1_lag)
        qui sum `diff_l1k'
        local mean_diff = r(mean)
        local max_diff = r(max)
        local n_l1k_compare = r(N)
        qui sum `scale_l1k'
        local mean_scale = r(mean)
        local rel_mean_diff = .
        if `n_l1k_compare' > 0 & !missing(`mean_diff') {
            local denom_l1k = max(1e-12, `mean_scale')
            local rel_mean_diff = `mean_diff' / `denom_l1k'
        }
        
        di as text ""
        di as text "l1k_lag Validation:"
        di as text _col(3) "l1k_lag  = L.lnl × lnk   (mixed lag for Z matrix)"
        di as text _col(3) "l1k1_lag = L.lnl × L.lnk (full lag for X_lag matrix)"
        di as text _col(3) "Mean difference:" _col(40) as result %10.6f `mean_diff'
        di as text _col(3) "Max difference:" _col(40) as result %10.6f `max_diff'
        di as text _col(3) "Relative mean difference:" _col(40) as result %10.3e `rel_mean_diff'
        
        if `n_l1k_compare' == 0 | missing(`mean_diff') {
            di as text "{bf:Warning}: cannot validate Translog mixed-lag instrument before sample filtering"
        }
    }

    // Record the full working sample before any external contract is applied.
    // Public return counts may later be contracted to gmmsample() so they
    // stay equivalent to physically keeping the same if/in subset first.
    qui count
    local N_original_full = r(N)
    
    // First observations have no admissible lagged productivity state.
    by `id' (`time'): gen byte _first = (_n == 1)
    qui count if _first == 1
    local N_first_full = r(N)
    
    // Theorem 3.1 moment conditions only use non-transition periods.
    qui count if `mid' == 1
    local N_mid_full = r(N)
    local gmmsample_external = 0
    local gmmsample_prefiltered = 0
    local N_first_gmmsample = 0
    local N_mid_gmmsample = 0
    local N_original = `N_original_full'
    local N_first = `N_first_full'
    local N_mid = `N_mid_full'
    
    // The caller passes the touse()/if/in contract, not the already-filtered
    // current-period GMM sample, so lagged values from rows outside that
    // contract can be blanked before the usual first/mid filtering runs.
    if "`gmmsample'" != "" {
        local gmmsample_external = 1
        qui count if `gmmsample' != 0 & !missing(`gmmsample')
        local N_original = r(N)
        qui count if `gmmsample' != 0 & !missing(`gmmsample') & `mid' == 1
        local N_mid_gmmsample = r(N)
        local N_mid = `N_mid_gmmsample'

        // Distinguish the live touse()/if/in contract from legacy direct
        // callers that still pass an already-filtered current-period GMM
        // sample. The latter only sample out first rows or transition rows.
        qui count if (`gmmsample' == 0 | mi(`gmmsample')) & _first != 1 & `mid' != 1
        if r(N) == 0 {
            local gmmsample_prefiltered = 1
        }
    }

    // Respect the caller's sample contract when constructing lagged inputs.
    // Live callers pass touse()/if/in support, so a previous sample-out row
    // must break the lag chain under the same keep-if semantics used by the
    // reference DO workflow. Legacy direct callers may still pass an already
    // filtered gmmsample = touse & (mid == 0); only in that legacy shape can
    // a sample-out transition predecessor remain a valid lag supplier.
    if `gmmsample_external' {
        local _pte_prev_gmmsample_out "(`gmmsample'[_n-1] == 0 | mi(`gmmsample'[_n-1]))"
        if `gmmsample_prefiltered' {
            replace phi_lag = . if _n > 1 & `_pte_prev_gmmsample_out' & `_pte_true_transition_row'[_n-1] != 1
            replace lnl_lag = . if _n > 1 & `_pte_prev_gmmsample_out' & `_pte_true_transition_row'[_n-1] != 1
            replace lnk_lag = . if _n > 1 & `_pte_prev_gmmsample_out' & `_pte_true_transition_row'[_n-1] != 1
            replace treat_post_lag = . if _n > 1 & `_pte_prev_gmmsample_out' & `_pte_true_transition_row'[_n-1] != 1
            replace mid_lag = . if _n > 1 & `_pte_prev_gmmsample_out' & `_pte_true_transition_row'[_n-1] != 1
            if "`prodfunc'" == "translog" {
                replace l2_lag = . if _n > 1 & `_pte_prev_gmmsample_out' & `_pte_true_transition_row'[_n-1] != 1
                replace k2_lag = . if _n > 1 & `_pte_prev_gmmsample_out' & `_pte_true_transition_row'[_n-1] != 1
                replace l1k1_lag = . if _n > 1 & `_pte_prev_gmmsample_out' & `_pte_true_transition_row'[_n-1] != 1
            }
        }
        else {
            replace phi_lag = . if _n > 1 & `_pte_prev_gmmsample_out'
            replace lnl_lag = . if _n > 1 & `_pte_prev_gmmsample_out'
            replace lnk_lag = . if _n > 1 & `_pte_prev_gmmsample_out'
            replace treat_post_lag = . if _n > 1 & `_pte_prev_gmmsample_out'
            replace mid_lag = . if _n > 1 & `_pte_prev_gmmsample_out'
            if "`prodfunc'" == "translog" {
                replace l2_lag = . if _n > 1 & `_pte_prev_gmmsample_out'
                replace k2_lag = . if _n > 1 & `_pte_prev_gmmsample_out'
                replace l1k1_lag = . if _n > 1 & `_pte_prev_gmmsample_out'
            }
        }

        // Contract the working sample to the caller-provided touse()/if/in
        // support before applying the standard first-period/transition filter.
        drop if `gmmsample' == 0 | missing(`gmmsample')

        // Rebuild first-period markers on the contracted sample so return
        // counts match the equivalent keep-if workflow exactly.
        capture drop _first
        by `id' (`time'): gen byte _first = (_n == 1)
        qui count if _first == 1
        local N_first_gmmsample = r(N)
        local N_first = `N_first_gmmsample'
    }

    // Create the current-period admissibility marker for reporting/debugging.
    gen byte _gmm_sample = (_first == 0 & `mid' != 1)
    
    // Apply the standard Theorem 3.1 filter after the lag contract is settled.
    drop if _first == 1
    drop if `mid' == 1
    
    // Missing phi comes from the first-stage regression; missing lags come
    // from panel gaps or the external sample contract above.
    local key_vars "`phi' phi_lag `lnl' `lnk' lnl_lag lnk_lag `treat_post' treat_post_lag `t'"
    if "`prodfunc'" == "translog" {
        local key_vars "`key_vars' `l2' `k2' `l1k1' l2_lag k2_lag l1k1_lag l1k_lag"
    }
    
    local N_before_miss = _N
    tempvar _pte_key_missing
    egen byte `_pte_key_missing' = rowmiss(`key_vars')
    qui drop if `_pte_key_missing' > 0
    local N_missing = `N_before_miss' - _N
    
    if `N_missing' > 0 {
        di as text _col(3) "Missing values excluded:" _col(40) as result %10.0fc `N_missing'
    }
    if `N_missing_transition_status' > 0 {
        di as text _col(3) "Rows with missing current/lagged treatment status:" _col(40) as result %10.0fc `N_missing_transition_status'
    }
    if "`prodfunc'" == "translog" {
        qui sum `diff_l1k'
        local mean_diff_final = r(mean)
        local max_diff_final = r(max)
        local n_l1k_compare_final = r(N)
        qui sum `scale_l1k'
        local mean_scale_final = r(mean)
        local rel_mean_diff_final = .
        if `n_l1k_compare_final' > 0 & !missing(`mean_diff_final') {
            local denom_l1k_final = max(1e-12, `mean_scale_final')
            local rel_mean_diff_final = `mean_diff_final' / `denom_l1k_final'
        }
        if `n_l1k_compare_final' == 0 | missing(`mean_diff_final') {
            di as error "{bf:_pte_gmm_matrices}: cannot validate Translog mixed-lag instrument"
            di as error "  No final GMM rows have both l1k_lag and l1k1_lag nonmissing"
            restore
            exit 498
        }
        if `max_diff_final' <= 1e-12 | `rel_mean_diff_final' < 1e-8 {
            local translog_mixed_lag_degenerate = 1
            di as text "{bf:Warning}: Translog mixed-lag instrument is numerically indistinguishable from the fully lagged interaction"
            di as text "  l1k_lag  = L.lnl * lnk"
            di as text "  l1k1_lag = L.lnl * L.lnk"
            di as text "  Final-sample relative mean difference: " %10.3e `rel_mean_diff_final'
            di as text "  This can occur with effectively time-invariant capital; continuing because the mixed-lag construction itself is valid."
        }
    }
    
    // Report both the contracted sample and the final usable GMM sample.
    qui count
    local N_gmm = r(N)
    local N_excluded = `N_original' - `N_gmm'
    
    di as text ""
    di as text "Sample Filtering:"
    di as text _col(3) "Original observations:" _col(40) as result %10.0fc `N_original'
    if `gmmsample_external' {
        di as text _col(3) "Reference full sample:" _col(40) as result %10.0fc `N_original_full'
        di as text _col(3) "External GMM sample provided:" _col(40) as result "yes"
        di as text _col(3) "First obs in external sample:" _col(40) as result %10.0fc `N_first_gmmsample'
        di as text _col(3) "Transition obs in external sample:" _col(40) as result %10.0fc `N_mid_gmmsample'
        di as text _col(3) "Reference first-period count:" _col(40) as result %10.0fc `N_first_full'
        di as text _col(3) "Reference transition count:" _col(40) as result %10.0fc `N_mid_full'
    }
    else {
        di as text _col(3) "First period excluded:" _col(40) as result %10.0fc `N_first'
        di as text _col(3) "Transition period excluded:" _col(40) as result %10.0fc `N_mid'
    }
    di as text _col(3) "GMM sample size:" _col(40) as result %10.0fc `N_gmm'
    
    // Mata expects at least one usable row.
    if `N_gmm' == 0 {
        di as error "{bf:_pte_gmm_matrices}: No observations remain after filtering"
        restore
        exit 2001
    }
    local min_gmm_rows = 2 + 2 * `omegapoly'
    if `N_gmm' <= `min_gmm_rows' {
        di as error "{bf:_pte_gmm_matrices}: GMM sample too small for the evolution basis"
        di as error "  Usable rows: `N_gmm'"
        di as error "  Minimum required rows: > `min_gmm_rows'"
        restore
        exit 2001
    }

    // Theorem 3.1 needs support from both stable untreated and stable treated
    // observations because h_bar_0 and h_bar_1 are estimated separately.
    qui count if `treat_post' == 0 & treat_post_lag == 0
    local n_stable_0 = r(N)
    qui count if `treat_post' == 1 & treat_post_lag == 1
    local n_stable_1 = r(N)
    
    di as text ""
    di as text "Assumption 3.3 Check:"
    di as text _col(3) "Stable control (D=D_lag=0):" _col(40) as result %10.0fc `n_stable_0'
    di as text _col(3) "Stable treated (D=D_lag=1):" _col(40) as result %10.0fc `n_stable_1'
    
    if `n_stable_0' == 0 | `n_stable_1' == 0 {
        di as error "{bf:_pte_gmm_matrices}: Assumption 3.3 violated"
        di as error "  Need both stable control and stable treated observations"
        restore
        exit 498
    }
    local min_stable_rows = `omegapoly' + 1
    if `n_stable_0' < `min_stable_rows' | `n_stable_1' < `min_stable_rows' {
        di as text "{bf:Warning}: very few stable observations for the evolution law"
        di as text "  Stable control: `n_stable_0', stable treated: `n_stable_1'"
        di as text "  Nominal rows per stable state for order `omegapoly': `min_stable_rows'"
        di as text "  Continuing because the paper/DO benchmark does not impose this hard cutoff."
    }
    local share_stable_0 = `n_stable_0' / `N_gmm'
    local share_stable_1 = `n_stable_1' / `N_gmm'
    if `share_stable_0' < 0.05 | `share_stable_1' < 0.05 {
        di as text "{bf:Warning}: Assumption 3.3 support is thin"
        di as text "  Stable control share: " %6.3f `share_stable_0'
        di as text "  Stable treated share: " %6.3f `share_stable_1'
        di as text "  Results may be imprecise; the paper/DO benchmark does not impose a 5% hard cutoff."
    }
    
    if `n_stable_0' < 50 | `n_stable_1' < 50 {
        di as text "{bf:Warning}: Small sample in stable groups"
        di as text "  Stable groups below 50 observations can make h_bar estimates unstable"
        di as text "  Results may be imprecise"
    }

    di as text ""
    di as text "Constructing GMM Matrices..."
    
    local _pte_do_pooled_z = ("`dopooledz'" != "")

    // Mata stores the matrices in global Mata state for the optimizer.
    mata: _pte_construct_gmm_matrices("`prodfunc'", `omegapoly', ///
        "`phi'", "`lnl'", "`lnk'", "`t'", "`treat_post'", ///
        "`l2'", "`k2'", "`l1k1'", `_pte_do_pooled_z')
    
    // The Mata helper writes these diagnostics back through st_local().
    
    // Surface matrix dimensions and Z'Z conditioning before optimization.
    di as text ""
    di as text "Matrix Dimensions:"
    di as text _col(3) "X matrix:" _col(40) as result "`N_gmm' × `cols_X'"
    di as text _col(3) "Z matrix:" _col(40) as result "`N_gmm' × `cols_Z'"
    if `_pte_do_pooled_z' {
        di as text _col(3) "Z moment layout:" _col(40) as result "pooled DO benchmark"
    }
    else {
        di as text _col(3) "Z moment layout:" _col(40) as result "state-interacted"
    }
    di as text _col(3) "OMEGA_LAG_POL columns:" _col(40) as result "`cols_OLP'"
    di as text _col(3) "Z'Z condition number:" _col(40) as result %12.4e `cond_ZZ'
    
    if `cond_ZZ' > 1e12 {
        di as text "{bf:Warning}: Z'Z condition number > 1e12"
        di as text "  The instrument matrix is ill-conditioned; continuing with invsym() to match the paper/DO benchmark path."
    }
    if `cond_ZZ' > 1e8 {
        di as text "{bf:Warning}: Z'Z condition number > 1e8"
        di as text "  Results may be numerically unstable"
    }
    
    di as text "{hline 60}"
    di as text ""

    // Return enough counts for callers to reconcile live filtering with the
    // paper/DO sample contract and any external gmmsample() restriction.
    return scalar N = `N_gmm'
    return scalar N_original = `N_original'
    return scalar N_excluded = `N_excluded'
    return scalar N_first = `N_first'
    return scalar N_mid = `N_mid'
    return scalar N_missing_transition_status = `N_missing_transition_status'
    return scalar gmmsample_external = `gmmsample_external'
    return scalar N_first_in_gmmsample = `N_first_gmmsample'
    return scalar N_mid_in_gmmsample = `N_mid_gmmsample'
    return scalar n_stable_0 = `n_stable_0'
    return scalar n_stable_1 = `n_stable_1'
    return scalar do_pooled_z = `_pte_do_pooled_z'
    return scalar cols_X = `cols_X'
    return scalar cols_Z = `cols_Z'
    return scalar cols_OLP = `cols_OLP'
    return scalar cond_ZZ = `cond_ZZ'
    return scalar translog_mixed_lag_degenerate = `translog_mixed_lag_degenerate'
    return scalar omegapoly = `omegapoly'
    return local prodfunc "`prodfunc'"
    if `_pte_do_pooled_z' {
        return local z_moment_layout "pooled_do"
    }
    else {
        return local z_moment_layout "state_interacted"
    }

    // Leave the caller's dataset untouched.
    restore

end
