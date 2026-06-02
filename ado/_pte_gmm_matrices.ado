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
         GMMSAMPLE(name)]
    
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
    tempvar _pte_mid_guard _pte_treat_guard _pte_true_transition_row
    qui sort `id' `time'
    qui by `id' (`time'): gen byte `_pte_true_transition_row' = ///
        (_n > 1 & abs((`time' - `time'[_n-1]) - `_tsdelta') <= `_tsdelta_tol' & ///
        `treat_post' != `treat_post'[_n-1]) if !mi(`treat_post', `treat_post'[_n-1])
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

    // Strategy: try calling an accessor to check if already compiled.
    // If not, derive mata/ path from this ado file's own location
    // (c(pwd) is unreliable — profile.do may change it).
    local _mata_ok 0
    capture mata: st_local("_mata_ok", "1")
    
    // Quick check: try calling a simple accessor
    if "`_mata_ok'" == "1" {
        local _mata_ok 0
        capture mata: st_local("_mata_ok", strofreal(_pte_get_omegapoly() >= 0 | _pte_get_omegapoly() < 0 | _pte_get_omegapoly() == .))
    }
    
    if "`_mata_ok'" != "1" {
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
        tempvar diff_l1k
        gen double `diff_l1k' = abs(l1k_lag - l1k1_lag) if !mi(l1k_lag) & !mi(l1k1_lag)
        qui sum `diff_l1k'
        local mean_diff = r(mean)
        local max_diff = r(max)
        
        di as text ""
        di as text "l1k_lag Validation:"
        di as text _col(3) "l1k_lag  = L.lnl × lnk   (mixed lag for Z matrix)"
        di as text _col(3) "l1k1_lag = L.lnl × L.lnk (full lag for X_lag matrix)"
        di as text _col(3) "Mean difference:" _col(40) as result %10.6f `mean_diff'
        di as text _col(3) "Max difference:" _col(40) as result %10.6f `max_diff'
        
        if `mean_diff' < 1e-10 {
            di as error "{bf:Warning}: l1k_lag and l1k1_lag are nearly identical"
            di as error "  This may indicate incorrect data or constant capital"
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
        qui count if `gmmsample'
        local N_original = r(N)
        qui count if `gmmsample' & `mid' == 1
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
        drop if !`gmmsample'

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
    foreach var of local key_vars {
        capture confirm variable `var'
        if !_rc {
            qui drop if mi(`var')
        }
    }
    local N_missing = `N_before_miss' - _N
    
    if `N_missing' > 0 {
        di as text _col(3) "Missing values excluded:" _col(40) as result %10.0fc `N_missing'
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
    
    if `n_stable_0' < 30 | `n_stable_1' < 30 {
        di as text "{bf:Warning}: Small sample in stable groups"
        di as text "  Results may be imprecise"
    }

    di as text ""
    di as text "Constructing GMM Matrices..."
    
    // Mata stores the matrices in global Mata state for the optimizer.
    mata: _pte_construct_gmm_matrices("`prodfunc'", `omegapoly', ///
        "`phi'", "`lnl'", "`lnk'", "`t'", "`treat_post'", ///
        "`l2'", "`k2'", "`l1k1'")
    
    // The Mata helper writes these diagnostics back through st_local().
    
    // Surface matrix dimensions and Z'Z conditioning before optimization.
    di as text ""
    di as text "Matrix Dimensions:"
    di as text _col(3) "X matrix:" _col(40) as result "`N_gmm' × `cols_X'"
    di as text _col(3) "Z matrix:" _col(40) as result "`N_gmm' × `cols_Z'"
    di as text _col(3) "OMEGA_LAG_POL columns:" _col(40) as result "`cols_OLP'"
    di as text _col(3) "Z'Z condition number:" _col(40) as result %12.4e `cond_ZZ'
    
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
    return scalar gmmsample_external = `gmmsample_external'
    return scalar N_first_in_gmmsample = `N_first_gmmsample'
    return scalar N_mid_in_gmmsample = `N_mid_gmmsample'
    return scalar n_stable_0 = `n_stable_0'
    return scalar n_stable_1 = `n_stable_1'
    return scalar cols_X = `cols_X'
    return scalar cols_Z = `cols_Z'
    return scalar cols_OLP = `cols_OLP'
    return scalar cond_ZZ = `cond_ZZ'
    return scalar omegapoly = `omegapoly'
    return local prodfunc "`prodfunc'"

    // Leave the caller's dataset untouched.
    restore

end
