*! _pte_bootstrap_bygroup.ado
*! Bygroup Bootstrap Inference
*!
*! Implements industry-level bootstrap inference for ATT estimation:
*!   Outer loop: j = 1..G (groups/industries)
*!     Set seed once per group (NOT per iteration)
*!     Inner loop: b = 1..B (bootstrap iterations)
*!       Stratified cluster resampling -> re-run full pipeline
*!       Save per-group per-iteration TT data
*!   Aggregation: append all groups per iteration -> pooled ATT
*!   SE = sd(ATT_boot_all) across B iterations
*!
*! Seed management:
*!   - Group seed: set once at start of each group's bootstrap loop
*!     replicate(trlg) -> 20000, replicate(cd) -> 10000
*!     user seed() overrides replicate default
*!   - NO per-iteration outer seed reset (unlike basic bootstrap)
*!   - Inner seed for ATT simulation: caller may override via inner_seed();
*!     otherwise the worker preserves the live grouped RNG stream

version 14.0
capture program drop _pte_bootstrap_bygroup
program define _pte_bootstrap_bygroup, eclass
    version 14.0
    local _pte_cmdline `"`0'"'
    local _pte_control_literal ""
    if regexm(lower(`"`_pte_cmdline'"'), ///
        "(^|[ ,])(control|contro|contr|cont)[ ]*[(]([^)]*)[)]") {
        local _pte_control_literal `"`=regexs(3)'"'
        local _pte_control_literal = ///
            lower(strtrim(`"`_pte_control_literal'"'))
    }

    // =========================================================================
    // Stage 1: Syntax parsing and parameter validation (T1.1, T1.2)
    // =========================================================================
    syntax varlist(min=1 max=1) [if] [in], ///
        BY(varname)                         /// grouping variable (e.g. industry)
        Treatment(varname)                  /// treatment indicator
        Free(varname)                       /// free input variable
        State(varname)                      /// state variable
        Proxy(varname)                      /// proxy variable
        [                                   ///
        CONTrol(varlist)                    /// control variables
        PFunc(string)                       /// production function type (cd/translog)
        POLY(integer -1)                    /// legacy alias for omegapoly()
        OMEGApoly(integer 3)                /// evolution polynomial order
        eps0window(integer 0)               /// eps0 window passed to _pte_omega
        NSIM(integer -1)                    /// counterfactual simulation paths
        ATTperiods(integer 4)               /// max ATT periods (0..attperiods)
        BOOTstrap(integer 100)              /// bootstrap replications
        SEED(integer -1)                    /// group seed (-1 = use default)
        INNER_seed(integer -1)              /// explicit inner ATT seed (-1 = preserve live grouped RNG stream)
        Level(cilevel)                     /// confidence level
        SAVing(string)                      /// optional save target for pooled bootstrap draws
        REPlicate(string)                   /// replication mode (trlg/cd)
        NOTRIMeps                           /// disable eps0 winsorize
        NOLOg                               /// suppress progress display
        NODIAGnose                          /// skip non-required diagnostics
        NOPARallel                          /// force serial execution
        PROCessors(integer -1)              /// number of parallel processors
        ]
    
    local depvar `varlist'
    marksample touse

    // Default production function
    if "`pfunc'" == "" local pfunc "translog"
    local _pte_has_poly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])poly[(]")
    local _pte_has_omegapoly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])omegapoly[(]")
    if `_pte_has_poly' {
        if `_pte_has_omegapoly' & `poly' != `omegapoly' {
            di as error "[pte] _pte_bootstrap_bygroup: cannot specify both poly(`poly') and omegapoly(`omegapoly')"
            exit 198
        }
        local omegapoly = `poly'
    }
    local poly = `omegapoly'

    // Validate pfunc
    if "`pfunc'" != "cd" & "`pfunc'" != "translog" {
        di as error "[pte] _pte_bootstrap_bygroup: pfunc must be cd or translog"
        exit 198
    }
    
    // Validate bootstrap reps
    local nboot = `bootstrap'
    if `nboot' < 2 {
        di as error "[pte] _pte_bootstrap_bygroup: bootstrap must be >= 2"
        exit 198
    }
    
    // Validate level
    if `level' < 10 | `level' > 99 {
        di as error "[pte] _pte_bootstrap_bygroup: level must be between 10 and 99"
        exit 198
    }
    
    // Validate omegapoly
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "[pte] _pte_bootstrap_bygroup: omegapoly must be 1, 2, 3, or 4"
        exit 198
    }
    
    // Validate attperiods
    if `attperiods' < 0 {
        di as error "[pte] _pte_bootstrap_bygroup: attperiods must be non-negative"
        exit 198
    }

    // Match the serial/bootstrap public omission contract: order 1 uses one
    // path, while higher-order evolution laws default to 100 paths.
    if `nsim' == -1 {
        if `omegapoly' == 1 {
            local nsim = 1
        }
        else {
            local nsim = 100
        }
    }
    if `nsim' < 1 {
        di as error "[pte] _pte_bootstrap_bygroup: nsim must be >= 1"
        exit 198
    }
    
    // Validate by variable
    capture confirm variable `by'
    if _rc != 0 {
        di as error "[pte] _pte_bootstrap_bygroup: variable `by' not found"
        exit 111
    }
    local _pte_byvar_type ""
    capture confirm numeric variable `by'
    if _rc == 0 {
        local _pte_byvar_type "numeric"
    }
    else {
        capture confirm string variable `by'
        if _rc == 0 {
            local _pte_byvar_type "string"
        }
        else {
            di as error "[pte] _pte_bootstrap_bygroup: `by' is neither numeric nor string"
            exit 111
        }
    }
    
    local _pte_n_controls : word count `control'
    if `"`_pte_control_literal'"' != "" & "`control'" != "" {
        local _pte_control_literal = lower(itrim(strtrim(`"`_pte_control_literal'"')))
        local _pte_control_resolved = lower(itrim(strtrim(`"`control'"')))
        if `"`_pte_control_literal'"' != `"`_pte_control_resolved'"' {
            di as error "[pte] _pte_bootstrap_bygroup: control() variables must be specified with exact existing variable names"
            exit 111
        }
    }
    // Validate panel structure
    capture _xt, trequired
    if _rc != 0 {
        di as error "[pte] _pte_bootstrap_bygroup: data must be xtset as panel"
        exit 459
    }
    local idvar = r(ivar)
    local timevar = r(tvar)
    quietly xtset
    local _pte_boot_delta "`r(tdelta)'"
    local _pte_boot_delta_opt ""
    if "`_pte_boot_delta'" != "" {
        local _pte_boot_delta_opt ", delta(`_pte_boot_delta')"
    }
    
    // Validate replicate option
    if "`replicate'" != "" & "`replicate'" != "trlg" & "`replicate'" != "cd" {
        di as error "[pte] _pte_bootstrap_bygroup: replicate must be trlg or cd"
        exit 198
    }
    
    // Determine group seed (T3.1)
    // Priority: user seed() > replicate() default > pfunc-based default
    local group_seed = `seed'
    if `group_seed' == -1 {
        if "`replicate'" == "trlg" {
            local group_seed = 20000
        }
        else if "`replicate'" == "cd" {
            local group_seed = 10000
        }
        else if "`pfunc'" == "translog" {
            local group_seed = 20000
        }
        else {
            local group_seed = 10000
        }
    }
    if `group_seed' < 1 {
        di as error "[pte] _pte_bootstrap_bygroup: seed() must be a positive integer"
        exit 198
    }
    if `group_seed' > 2147483647 {
        di as error "[pte] _pte_bootstrap_bygroup: seed() exceeds maximum value (2147483647)"
        exit 198
    }
    
    // Determine inner seed behavior
    // -1 means preserve the live grouped RNG stream inside _pte_att.
    // Any other value means reset the inner ATT seed explicitly.
    local use_inner_seed = (`inner_seed' != -1)
    if `use_inner_seed' {
        if `inner_seed' < 1 {
            di as error "[pte] _pte_bootstrap_bygroup: inner_seed must be >= 1 when specified"
            exit 198
        }
        if `inner_seed' > 2147483647 {
            di as error "[pte] _pte_bootstrap_bygroup: inner_seed exceeds maximum value (2147483647)"
            exit 198
        }
        local inner_seed_val = `inner_seed'
    }

    // When the parallel helper cannot deliver a complete grouped bootstrap
    // payload, fall back to the serial DO-style path rather than surfacing a
    // spurious grouped-bootstrap failure from an execution-mode difference.
    local _pte_serial_retry_opts "by(`by') treatment(`treatment')"
    local _pte_serial_retry_opts "`_pte_serial_retry_opts' free(`free') state(`state') proxy(`proxy')"
    local _pte_serial_retry_opts "`_pte_serial_retry_opts' pfunc(`pfunc') poly(`poly')"
    local _pte_serial_retry_opts "`_pte_serial_retry_opts' omegapoly(`omegapoly')"
    local _pte_serial_retry_opts "`_pte_serial_retry_opts' eps0window(`eps0window')"
    local _pte_serial_retry_opts "`_pte_serial_retry_opts' nsim(`nsim') attperiods(`attperiods')"
    local _pte_serial_retry_opts "`_pte_serial_retry_opts' bootstrap(`bootstrap') seed(`seed')"
    local _pte_serial_retry_opts "`_pte_serial_retry_opts' level(`level') noparallel"
    if `use_inner_seed' {
        local _pte_serial_retry_opts "`_pte_serial_retry_opts' inner_seed(`inner_seed_val')"
    }
    if "`control'" != "" {
        local _pte_serial_retry_opts "`_pte_serial_retry_opts' control(`control')"
    }
    if "`saving'" != "" {
        local _pte_serial_retry_opts "`_pte_serial_retry_opts' saving(`saving')"
    }
    if "`replicate'" != "" {
        local _pte_serial_retry_opts "`_pte_serial_retry_opts' replicate(`replicate')"
    }
    if "`notrimeps'" != "" {
        local _pte_serial_retry_opts "`_pte_serial_retry_opts' notrimeps"
    }
    if "`nolog'" != "" {
        local _pte_serial_retry_opts "`_pte_serial_retry_opts' nolog"
    }
    if "`nodiagnose'" != "" {
        local _pte_serial_retry_opts "`_pte_serial_retry_opts' nodiagnose"
    }
    
    // Trim track flag
    local do_trim = ("`notrimeps'" == "")
    local _diag_opt ""
    if "`nodiagnose'" != "" {
        local _diag_opt "nodiagnose"
    }
    
    // Column dimensions: [att_0, ..., att_T, att_overall]
    local nperiods = `attperiods' + 1
    local ncols = 1 + `nperiods'
    local att_colnames ""
    forvalues s = 0/`attperiods' {
        local att_colnames "`att_colnames' ATT`s'"
    }
    local att_colnames "`att_colnames' ATT"
    local beta_ncols = cond("`pfunc'" == "cd", 3, 6)
    local beta_colnames "beta_l beta_k beta_t"
    if "`pfunc'" != "cd" {
        local beta_colnames "beta_l beta_k beta_l2 beta_k2 beta_lk beta_t"
    }
    if `_pte_n_controls' > 1 {
        local beta_ncols = cond("`pfunc'" == "cd", 2, 5) + `_pte_n_controls'
        local beta_colnames "beta_l beta_k"
        if "`pfunc'" != "cd" {
            local beta_colnames "beta_l beta_k beta_l2 beta_k2 beta_lk"
        }
        local beta_colnames "`beta_colnames' `control'"
    }

    // =========================================================================
    // Stage 2: Group identification and traversal (T2.1)
    // =========================================================================
    
    // Get group levels
    quietly levelsof `by' if `touse', local(groups)
    local ngroups = r(r)
    
    if `ngroups' < 1 {
        di as error "[pte] _pte_bootstrap_bygroup: no groups found in `by'"
        exit 2000
    }
    
    // Save original data
    tempfile orig_data
    quietly save `orig_data', replace

    // Late pooled-gate failures happen after nested/002/003 calls
    // have overwritten e(). Save the caller estimate so rc=2000 can roll back
    // to the pre-entry state instead of leaking the last worker context.
    tempname _pte_prev_est
    local _pte_has_prev_est = 0
    capture local _pte_prev_cmd `"`e(cmd)'"'
    if _rc == 0 {
        capture estimates store `_pte_prev_est', copy
        if _rc == 0 {
            local _pte_has_prev_est = 1
        }
    }
    
    // Save RNG state
    local orig_rngstate = c(rngstate)
    
    // =========================================================================
    // Display header
    // =========================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "PTE Bygroup Bootstrap Inference"
        di as text "{hline 70}"
        di as text "  Production function:  " as result "`pfunc'"
        di as text "  Omega polynomial:     " as result "`omegapoly'"
        di as text "  ATT periods:          " as result "0 to `attperiods'"
        di as text "  Bootstrap reps:       " as result "`nboot'"
        di as text "  Groups (`by'):        " as result "`ngroups'"
        di as text "  Group seed:           " as result "`group_seed'"
        if `use_inner_seed' {
            di as text "  Inner seed:           " as result "`inner_seed_val'"
        }
        else {
            di as text "  Inner seed:           " as result ///
                "live grouped RNG stream"
        }
        di as text "  nsim:                 " as result "`nsim'"
        di as text "  Trim eps0:            " as result cond(`do_trim', "Yes (1%-99%)", "No")
        di as text "  Confidence level:     " as result "`level'%"
        if "`replicate'" != "" {
            di as text "  Replicate mode:       " as result "`replicate'"
        }
        di as text "{hline 70}"
    }

    // =========================================================================
    // Stage 6: Parallel strategy selection (T6.1)
    // =========================================================================
    local parallel_method "serial"
    local parallel_nproc = 1
    local parallel_requested_method "serial"
    local parallel_requested_nproc = 1
    local parallel_fallback = 0
    local parallel_fallback_reason ""
    local parallel_helper_rc = .
    
    if "`noparallel'" == "" {
        // T6.1.1: Call _pte_check_parallel to detect environment
        capture {
            _pte_check_parallel, quiet
            local parallel_method = r(parallel_method)
            local parallel_nproc = r(recommended_nproc)
        }
        if _rc != 0 {
            local parallel_method "serial"
            local parallel_nproc = 1
        }
        
        // T6.1.2: User-specified processor count overrides
        if `processors' > 0 {
            local parallel_nproc = `processors'
        }
        
        // T6.1.3: Cap nproc at ngroups (no point having more workers than groups)
        if `parallel_nproc' > `ngroups' {
            local parallel_nproc = `ngroups'
        }
        
        // T6.1.4: Single group -> serial
        if `ngroups' == 1 {
            local parallel_method "serial"
            local parallel_nproc = 1
        }
        
        // T6.1.5: If parallel_pkg selected but parallel not available, degrade
        if "`parallel_method'" == "parallel_pkg" {
            capture which parallel
            if _rc != 0 {
                local parallel_method "serial"
                local parallel_nproc = 1
                if "`nolog'" == "" {
                    di as text "[pte] Warning: parallel package not found, falling back to serial"
                }
            }
        }
        
        // native_mp doesn't help for bygroup bootstrap (groups are sequential)
        // Only parallel_pkg provides true parallelism across groups
        if "`parallel_method'" == "native_mp" {
            local parallel_method "serial"
            local parallel_nproc = 1
        }
    }
    
    if "`nolog'" == "" & "`parallel_method'" != "serial" {
        di as text "  Parallel method:      " as result "`parallel_method'"
        di as text "  Parallel processors:  " as result "`parallel_nproc'"
    }
    local parallel_requested_method "`parallel_method'"
    local parallel_requested_nproc = `parallel_nproc'

    // =========================================================================
    // Stage 3-4: Per-group bootstrap loop (T2.2, T3.1-T3.3, T4.1-T4.3)
    // =========================================================================
    
    // Initialize per-group result matrices
    // ATT_boot_grp`g': nboot x ncols for each group
    // BETA_boot_grp`g': nboot x k for each group
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        tempname att_boot_g`g_idx' att_trim_boot_g`g_idx' beta_boot_g`g_idx'
        matrix `att_boot_g`g_idx'' = J(`nboot', `ncols', .)
        matrix colnames `att_boot_g`g_idx'' = `att_colnames'
        if `do_trim' {
            matrix `att_trim_boot_g`g_idx'' = J(`nboot', `ncols', .)
            matrix colnames `att_trim_boot_g`g_idx'' = `att_colnames'
        }
        // Beta dimensions follow the grouped point contract: single-control
        // paths keep beta_t, while multi-control paths append exact names.
        matrix `beta_boot_g`g_idx'' = J(`nboot', `beta_ncols', .)
        matrix colnames `beta_boot_g`g_idx'' = `beta_colnames'
    }
    
    // Track per-group success/failure
    local total_success = 0
    local total_fail = 0
    
    // Create temp directory for TT data files
    local tmpdir = c(tmpdir)
    tempname _pte_tt_token
    local tt_runid "`_pte_tt_token'"
    local tt_prefix "pte_tt_`tt_runid'_g"
    // Fresh-run contract: grouped bootstrap TT files must come only from the
    // current invocation. Reusing fixed filenames without a pre-clean step
    // lets failed or aborted prior runs fabricate complete pooled draws.
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        forvalues b = 1/`nboot' {
            capture erase "`tmpdir'/`tt_prefix'`g_idx'_b`b'.dta"
        }
    }
    
    // Set bootstrap flag for downstream modules
    scalar _pte_in_bootstrap = 1
    
    // =========================================================================
    // T6.3: Parallel execution path (if parallel_pkg selected)
    // =========================================================================
    local _did_parallel = 0
    
    if "`parallel_method'" == "parallel_pkg" {
        if "`nolog'" == "" {
            di as text ""
            di as text "[pte] Using parallel package with `parallel_nproc' workers"
        }
        
        local _par_opts "nboot(`nboot') nproc(`parallel_nproc') ngroups(`ngroups')"
        local _par_opts "`_par_opts' groups(`groups') by(`by')"
        local _par_opts "`_par_opts' treatment(`treatment')"
        local _par_opts "`_par_opts' depvar(`depvar') free(`free') state(`state') proxy(`proxy')"
        local _par_opts "`_par_opts' id(`idvar') time(`timevar')"
        local _par_opts "`_par_opts' group_seed(`group_seed')"
        local _par_opts "`_par_opts' tousevar(`touse')"
        local _par_opts "`_par_opts' ttprefix(`tt_prefix') runid(`tt_runid')"
        local _par_opts "`_par_opts' omegapoly(`omegapoly') attperiods(`attperiods')"
        local _par_opts "`_par_opts' nsim(`nsim') eps0window(`eps0window')"
        local _par_opts "`_par_opts' prodfunc(`pfunc') poly(`poly')"
        if "`control'" != "" {
            local _par_opts "`_par_opts' control(`control')"
        }
        if `use_inner_seed' {
            local _par_opts "`_par_opts' inner_seed(`inner_seed_val')"
        }
        if "`notrimeps'" != "" {
            local _par_opts "`_par_opts' notrimeps"
        }
        if "`nodiagnose'" != "" {
            local _par_opts "`_par_opts' nodiagnose"
        }
        if "`nolog'" != "" {
            local _par_opts "`_par_opts' nolog"
        }
        
        capture noisily {
            _pte_bygroup_parallel, `_par_opts'
        }
        
        if _rc == 0 {
            local _did_parallel = 1
            local total_success = r(n_success)
            local total_fail = r(n_fail)
            // Grouped bootstrap beta payloads must match the active grouped
            // point contract, including multi-control control-name columns.
            local _pte_beta_required_cols = `beta_ncols'
            
            // Copy per-group matrices from r() to local tempnames
            local g_idx = 0
            foreach grp of local groups {
                local ++g_idx
                matrix `att_boot_g`g_idx'' = r(att_g`g_idx')
                if `do_trim' {
                    capture matrix `att_trim_boot_g`g_idx'' = r(att_trim_g`g_idx')
                }
                matrix `beta_boot_g`g_idx'' = r(beta_g`g_idx')
            }

            local _pte_complete_draws = 0
            local g_idx = 0
            foreach grp of local groups {
                local ++g_idx
                forvalues b = 1/`nboot' {
                    local _pte_row_complete = 1
                    if missing(`att_boot_g`g_idx''[`b', 1]) | ///
                        missing(`att_boot_g`g_idx''[`b', `ncols']) {
                        local _pte_row_complete = 0
                    }
                    if `do_trim' {
                        if missing(`att_trim_boot_g`g_idx''[`b', 1]) | ///
                            missing(`att_trim_boot_g`g_idx''[`b', `ncols']) {
                            local _pte_row_complete = 0
                        }
                    }
                    forvalues j = 1/`_pte_beta_required_cols' {
                        if missing(`beta_boot_g`g_idx''[`b', `j']) {
                            local _pte_row_complete = 0
                        }
                    }
                    if `_pte_row_complete' == 1 {
                        local ++_pte_complete_draws
                    }
                }
            }
            if `total_success' == 0 | `_pte_complete_draws' != `total_success' {
                if "`nolog'" == "" {
                    if `total_success' == 0 {
                        di as text "[pte] Parallel helper returned no complete grouped draws, falling back to serial"
                    }
                    else {
                        di as text "[pte] Parallel helper payload mismatch (`_pte_complete_draws' complete rows vs `total_success' reported successes), falling back to serial"
                    }
                }
                local _did_parallel = 0
                local parallel_fallback = 1
                if `total_success' == 0 {
                    local parallel_fallback_reason "helper_empty"
                }
                else {
                    local parallel_fallback_reason "payload_mismatch"
                }
                local parallel_method "serial"
                local parallel_nproc = 1
                local g_idx = 0
                foreach grp of local groups {
                    local ++g_idx
                    matrix `att_boot_g`g_idx'' = J(`nboot', `ncols', .)
                    matrix colnames `att_boot_g`g_idx'' = `att_colnames'
                    if `do_trim' {
                        matrix `att_trim_boot_g`g_idx'' = J(`nboot', `ncols', .)
                        matrix colnames `att_trim_boot_g`g_idx'' = `att_colnames'
                    }
                    matrix `beta_boot_g`g_idx'' = J(`nboot', `beta_ncols', .)
                    matrix colnames `beta_boot_g`g_idx'' = `beta_colnames'
                }
                local total_success = 0
                local total_fail = 0
                quietly use `orig_data', clear
                quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
                quietly save `orig_data', replace
                scalar _pte_in_bootstrap = 1
            }
            
            // Restore data (parallel may have changed it)
            if `_did_parallel' == 1 {
                quietly use `orig_data', clear
                quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
            }
        }
        else {
            // Parallel failed, fall back to serial
            local parallel_fallback = 1
            local parallel_fallback_reason "helper_rc"
            local parallel_helper_rc = _rc
            if "`nolog'" == "" {
                di as text "[pte] Parallel execution failed (rc=" _rc "), falling back to serial"
            }
            local parallel_method "serial"
            local parallel_nproc = 1
            // Restore data for serial path
            quietly use `orig_data', clear
            quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
            // Re-save for serial loop
            quietly save `orig_data', replace
            scalar _pte_in_bootstrap = 1
        }
    }
    
    // =========================================================================
    // Main loop: for each group g, run B bootstrap iterations
    // (skipped if parallel path succeeded)
    // =========================================================================
    if `_did_parallel' == 0 {
    // BEGIN SERIAL PATH
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        local grp_success = 0
        local grp_fail = 0
        
        if "`nolog'" == "" {
            di as text ""
            di as text "Bootstrapping group `by' = " as result "`grp'" ///
                as text " (`g_idx'/`ngroups')"
        }
        
        // T3.1-T3.2: Set group seed ONCE at start of each group
        //   set seed 20000
        set seed `group_seed'
        
        if "`nolog'" == "" {
            di as text "  Seed set to `group_seed'"
            di as text "  Resampling: " _continue
        }
        
        // T2.2: Bootstrap inner loop
        forvalues b = 1/`nboot' {
            
            // Progress display
            if "`nolog'" == "" {
                if mod(`b', 50) == 0 {
                    di as text "`b'" _continue
                }
                else {
                    di as text "." _continue
                }
            }
            
            // T4.1: Load original data and filter to this group
            quietly use `orig_data', clear
            if "`_pte_byvar_type'" == "numeric" {
                quietly keep if `by' == `grp' & `touse'
            }
            else {
                quietly keep if `by' == "`grp'" & `touse'
            }
            
            // Validate group has enough data
            quietly count
            if r(N) < 10 {
                local ++grp_fail
                continue
            }
            
            // T4.1.1: Generate firm-level treatment indicator
            capture drop _pte_treat_firm
            quietly bysort `idvar': egen _pte_treat_firm = max(`treatment')
            
            // T4.1.2: Stratified cluster bootstrap resampling
            capture drop _pte_firm_bs
            capture {
                quietly bsample, strata(_pte_treat_firm) ///
                    cluster(`idvar') idcluster(_pte_firm_bs)
            }
            if _rc != 0 {
                local ++grp_fail
                continue
            }
            
            // T4.1.3: Re-set panel structure
            quietly xtset _pte_firm_bs `timevar'`_pte_boot_delta_opt'
            
            // T4.2: Complete two-step estimation
            local bs_ok = 1
            
            // T4.2.1: Production function estimation
            capture {
                local _pf_opts "treatment(`treatment') id(_pte_firm_bs) time(`timevar')"
                local _pf_opts "`_pf_opts' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
                local _pf_opts "`_pf_opts' pfunc(`pfunc') poly(`poly') omegapoly(`omegapoly')"
                if "`control'" != "" {
                    local _pf_opts "`_pf_opts' control(`control')"
                }
                local _pf_opts "`_pf_opts' noreport"
                if "`_diag_opt'" != "" {
                    local _pf_opts "`_pf_opts' `_diag_opt'"
                }
                _pte_prodfunc, `_pf_opts'
            }
            if _rc != 0 {
                local bs_ok = 0
            }
            
            if `bs_ok' == 1 {
                // Store bootstrap betas (T9.1.2)
                local bs_beta_l = _b[`free']
                local bs_beta_k = _b[`state']
                local _pte_beta_payload_ok = 1
                if missing(`bs_beta_l') | missing(`bs_beta_k') {
                    local _pte_beta_payload_ok = 0
                }
                local bs_beta_t = .
                local _pte_beta_payload_ctrl_ready = 1
                capture matrix _pte_beta_ctrl = e(beta_controls)
                if _rc == 0 {
                    local _pte_beta_ctrl_names : colnames _pte_beta_ctrl
                    if `_pte_n_controls' > 1 {
                        foreach _ctrl of local control {
                            local _ctrl_pos : list posof "`_ctrl'" in _pte_beta_ctrl_names
                            if `_ctrl_pos' < 1 {
                                local _pte_beta_payload_ctrl_ready = 0
                            }
                        }
                    }
                    else if "`control'" != "" {
                        local _only_ctrl : word 1 of `control'
                        local _ctrl_pos : list posof "`_only_ctrl'" in _pte_beta_ctrl_names
                        if `_ctrl_pos' < 1 {
                            local _pte_beta_payload_ctrl_ready = 0
                        }
                        else {
                            local bs_beta_t = _pte_beta_ctrl[1, `_ctrl_pos']
                        }
                    }
                    else if colsof(_pte_beta_ctrl) >= 1 {
                        local bs_beta_t = _pte_beta_ctrl[1, 1]
                    }
                }
                else {
                    capture local bs_beta_t = _b[t]
                    if `_pte_n_controls' > 1 {
                        local _pte_beta_payload_ctrl_ready = 0
                    }
                }
                if "`pfunc'" == "cd" {
                    if `_pte_n_controls' > 1 {
                        if `_pte_beta_payload_ctrl_ready' == 0 {
                            local _pte_beta_payload_ok = 0
                        }
                    }
                    else if missing(`bs_beta_t') {
                        local _pte_beta_payload_ok = 0
                    }
                }
                else {
                    local bs_beta_ll = _b[l2]
                    local bs_beta_kk = _b[k2]
                    local bs_beta_lk = _b[l1k1]
                    if missing(`bs_beta_ll') | missing(`bs_beta_kk') | ///
                        missing(`bs_beta_lk') {
                        local _pte_beta_payload_ok = 0
                    }
                    if `_pte_n_controls' > 1 {
                        if `_pte_beta_payload_ctrl_ready' == 0 {
                            local _pte_beta_payload_ok = 0
                        }
                    }
                    else if missing(`bs_beta_t') {
                        local _pte_beta_payload_ok = 0
                    }
                }
                if `_pte_beta_payload_ok' == 0 {
                    local bs_ok = 0
                }
                
                // T4.2.2: Productivity recovery and evolution
                if `bs_ok' == 1 {
                    capture {
                        local _om_opts "treatment(`treatment') omegapoly(`omegapoly')"
                        local _om_opts "`_om_opts' beta_l(`bs_beta_l') beta_k(`bs_beta_k')"
                        local _om_opts "`_om_opts' eps0window(`eps0window')"
                        if "`pfunc'" == "translog" {
                            local _om_opts "`_om_opts' beta_ll(`bs_beta_ll') beta_kk(`bs_beta_kk') beta_lk(`bs_beta_lk')"
                            local _om_opts "`_om_opts' prodfunc(translog)"
                        }
                        if "`notrimeps'" != "" {
                            local _om_opts "`_om_opts' notrimeps"
                        }
                        if "`_diag_opt'" != "" {
                            local _om_opts "`_om_opts' `_diag_opt'"
                        }
                        _pte_omega, `_om_opts'
                    }
                    if _rc != 0 {
                        local bs_ok = 0
                    }
                }
            }
            
            if `bs_ok' == 1 {
                // T4.2.3: ATT estimation
                // When inner_seed() is omitted, preserve the live grouped RNG
                // stream so grouped bootstrap matches the official DO law.
                capture {
                    local _att_opts "treatment(`treatment') omegapoly(`omegapoly')"
                    local _att_opts "`_att_opts' attperiods(`attperiods') nsim(`nsim')"
                    if `use_inner_seed' {
                        local _att_opts "`_att_opts' seed(`inner_seed_val')"
                    }
                    else {
                        local _att_opts "`_att_opts' preserverng"
                    }
                    if "`_diag_opt'" != "" {
                        local _att_opts "`_att_opts' `_diag_opt'"
                    }
                    local _att_opts "`_att_opts' nostabilitycheck"
                    if "`notrimeps'" != "" {
                        local _att_opts "`_att_opts' notrimeps"
                    }
                    _pte_att, `_att_opts'
                }
                if _rc != 0 {
                    local bs_ok = 0
                }
            }
            
            // T4.2.5 + T4.3: Store results
            if `bs_ok' == 1 {
                // T4.3: Save TT data for cross-group aggregation
                // Persist only complete grouped draws. Missing raw/trim TT
                // variables or TT-save failures must fail closed instead of
                // letting per-group ATT sidecars disagree with the pooled
                // grouped-bootstrap success law.
                local _pte_tt_payload_ok = 1
                foreach _pte_tt_req in _pte_nt _pte_tt_raw _pte_tt {
                    capture confirm variable `_pte_tt_req'
                    if _rc != 0 {
                        local _pte_tt_payload_ok = 0
                    }
                }
                if `do_trim' {
                    capture confirm variable _pte_tt_trim
                    if _rc != 0 {
                        local _pte_tt_payload_ok = 0
                    }
                }
                if `_pte_tt_payload_ok' {
                    quietly count if !missing(_pte_nt) & !missing(_pte_tt_raw)
                    if r(N) == 0 {
                        local _pte_tt_payload_ok = 0
                    }
                }
                if `_pte_tt_payload_ok' & `do_trim' {
                    quietly count if !missing(_pte_nt) & !missing(_pte_tt_trim)
                    if r(N) == 0 {
                        local _pte_tt_payload_ok = 0
                    }
                }
                if `_pte_tt_payload_ok' {
                    capture {
                        local _pte_tt_keep "_pte_firm_bs `timevar' _pte_nt _pte_tt_raw _pte_tt"
                        if `do_trim' {
                            local _pte_tt_keep "`_pte_tt_keep' _pte_tt_trim"
                        }
                        quietly keep `_pte_tt_keep'
                        capture drop _pte_tt_runid
                        quietly gen str244 _pte_tt_runid = "`tt_runid'"
                    }
                    capture {
                        quietly save "`tmpdir'/`tt_prefix'`g_idx'_b`b'.dta", replace
                    }
                }
                
                if `_pte_tt_payload_ok' & _rc == 0 {
                    // Publish per-group ATT and beta draws only after the
                    // complete grouped-draw contract holds. This keeps the
                    // per-group sidecars aligned with grouped success counts,
                    // pooled aggregation, and the parallel helper payload law.
                    forvalues s = 0/`attperiods' {
                        local col = `s' + 1
                        capture local _tmp = e(att_raw_`s')
                        if _rc == 0 & !missing(`_tmp') {
                            matrix `att_boot_g`g_idx''[`b', `col'] = `_tmp'
                        }
                    }
                    matrix `att_boot_g`g_idx''[`b', `ncols'] = e(ATT_avg_raw)
                    if `do_trim' {
                        forvalues s = 0/`attperiods' {
                            local col = `s' + 1
                            capture local _tmp_t = e(att_trim_`s')
                            if _rc == 0 & !missing(`_tmp_t') {
                                matrix `att_trim_boot_g`g_idx''[`b', `col'] = `_tmp_t'
                            }
                        }
                        matrix `att_trim_boot_g`g_idx''[`b', `ncols'] = e(ATT_avg_trim)
                    }
                    matrix `beta_boot_g`g_idx''[`b', 1] = `bs_beta_l'
                    matrix `beta_boot_g`g_idx''[`b', 2] = `bs_beta_k'
                    if "`pfunc'" == "cd" {
                        if `_pte_n_controls' > 1 {
                            foreach _ctrl of local control {
                                local _ctrl_j = `: list posof "`_ctrl'" in control'
                                local _ctrl_pos : list posof "`_ctrl'" in _pte_beta_ctrl_names
                                matrix `beta_boot_g`g_idx''[`b', 2 + `_ctrl_j'] = ///
                                    _pte_beta_ctrl[1, `_ctrl_pos']
                            }
                        }
                        else {
                            matrix `beta_boot_g`g_idx''[`b', 3] = `bs_beta_t'
                        }
                    }
                    else {
                        matrix `beta_boot_g`g_idx''[`b', 3] = `bs_beta_ll'
                        matrix `beta_boot_g`g_idx''[`b', 4] = `bs_beta_kk'
                        matrix `beta_boot_g`g_idx''[`b', 5] = `bs_beta_lk'
                        if `_pte_n_controls' > 1 {
                            foreach _ctrl of local control {
                                local _ctrl_j = `: list posof "`_ctrl'" in control'
                                local _ctrl_pos : list posof "`_ctrl'" in _pte_beta_ctrl_names
                                matrix `beta_boot_g`g_idx''[`b', 5 + `_ctrl_j'] = ///
                                    _pte_beta_ctrl[1, `_ctrl_pos']
                            }
                        }
                        else {
                            matrix `beta_boot_g`g_idx''[`b', 6] = `bs_beta_t'
                        }
                    }
                    local ++grp_success
                }
                else {
                    local ++grp_fail
                }
            }
            else {
                // T4.2.4: Record failure
                local ++grp_fail
            }
        }
        
        // Per-group summary
        local total_success = `total_success' + `grp_success'
        local total_fail = `total_fail' + `grp_fail'
        
        if "`nolog'" == "" {
            di ""
            di as text "  Group `grp': " as result `grp_success' ///
                as text "/" as result `nboot' as text " successful"
            if `grp_fail' > 0 {
                di as text "  Failed: " as result `grp_fail'
            }
        }
    }
    
    } // END SERIAL PATH (if _did_parallel == 0)

    // =========================================================================
    // Stage 5: Cross-group aggregation (T5.1, T5.2, T5.3)
    //
    // For each bootstrap iteration b:
    //   1. Append TT data from all groups
    //   2. Compute pooled ATT = mean(TT) by nt
    //   3. Store in ATT_boot_all[b, .]
    //
    // This is the "sample-weighted average" approach from the replication code.
    // =========================================================================
    
    if "`nolog'" == "" {
        di as text ""
        di as text "Aggregating across groups..."
    }
    
    // Initialize pooled bootstrap matrices
    tempname att_boot_all att_boot_trim
    matrix `att_boot_all' = J(`nboot', `ncols', .)
    matrix colnames `att_boot_all' = `att_colnames'
    if `do_trim' {
        matrix `att_boot_trim' = J(`nboot', `ncols', .)
        matrix colnames `att_boot_trim' = `att_colnames'
    }
    local pooled_success = 0
    local _pte_agg_rc = 0

    capture quietly _pte_bygroup_aggregate, ///
        ngroups(`ngroups') ///
        nboot(`nboot') ///
        attperiods(`attperiods') ///
        tmpdir("`tmpdir'") ///
        ttprefix("`tt_prefix'") ///
        runid("`tt_runid'") ///
        `notrimeps'
    local _pte_agg_rc = _rc
    
    // Clean up temp TT files
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        forvalues b = 1/`nboot' {
            capture erase "`tmpdir'/`tt_prefix'`g_idx'_b`b'.dta"
        }
    }

    if `_pte_agg_rc' != 0 {
        if `_did_parallel' == 1 {
            quietly use `orig_data', clear
            quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
            capture set rngstate `orig_rngstate'
            capture scalar drop _pte_in_bootstrap
            capture noisily _pte_bootstrap_bygroup `depvar' if `touse', ///
                `_pte_serial_retry_opts'
            local _pte_retry_rc = _rc
            if `_pte_retry_rc' != 0 {
                if `_pte_has_prev_est' {
                    capture estimates restore `_pte_prev_est'
                    capture estimates drop `_pte_prev_est'
                }
                else {
                    capture ereturn clear
                }
                exit `_pte_retry_rc'
            }
            if `_pte_has_prev_est' {
                capture estimates drop `_pte_prev_est'
            }
            capture ereturn scalar parallel_requested_nproc = `parallel_requested_nproc'
            capture ereturn scalar parallel_fallback = 1
            capture ereturn scalar parallel_nproc = 1
            ereturn local parallel_requested_method "`parallel_requested_method'"
            ereturn local parallel_fallback_reason "payload_mismatch"
            ereturn local parallel_method "serial"
            exit 0
        }
        quietly use `orig_data', clear
        quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
        capture set rngstate `orig_rngstate'
        capture scalar drop _pte_in_bootstrap
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
        exit `_pte_agg_rc'
    }

    matrix `att_boot_all' = r(att_pool)
    if `do_trim' {
        matrix `att_boot_trim' = r(att_pool_trim)
    }
    // The grouped public replay/saving contract should not expose execution-
    // mode jitter that is far below any econometric tolerance but can arise
    // from raw-only floating-point accumulation. Canonicalize pooled draws at
    // a sub-test-tolerance grid before publishing them to e() and saving().
    mata: st_matrix("`att_boot_all'", round(st_matrix("`att_boot_all'"), 1e-9))
    if `do_trim' {
        mata: st_matrix("`att_boot_trim'", round(st_matrix("`att_boot_trim'"), 1e-9))
    }
    forvalues b = 1/`nboot' {
        if !missing(`att_boot_all'[`b', 1]) {
            local ++pooled_success
        }
    }

    // =========================================================================
    // Stage 5.3: SE and CI computation (T5.3)
    //   svmat ATT_boot_all, n(col)
    //   tabstat ATT*, stat(sd) save
    //   matrix ATT_est_all[3, 1] = r(StatTotal)
    // =========================================================================
    
    local pooled_fail = `nboot' - `pooled_success'
    
    if `pooled_success' < 2 {
        if `_did_parallel' == 1 {
            quietly use `orig_data', clear
            quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
            capture set rngstate `orig_rngstate'
            capture scalar drop _pte_in_bootstrap
            capture noisily _pte_bootstrap_bygroup `depvar' if `touse', ///
                `_pte_serial_retry_opts'
            local _pte_retry_rc = _rc
            if `_pte_retry_rc' != 0 {
                if `_pte_has_prev_est' {
                    capture estimates restore `_pte_prev_est'
                    capture estimates drop `_pte_prev_est'
                }
                else {
                    capture ereturn clear
                }
                exit `_pte_retry_rc'
            }
            if `_pte_has_prev_est' {
                capture estimates drop `_pte_prev_est'
            }
            capture ereturn scalar parallel_requested_nproc = `parallel_requested_nproc'
            capture ereturn scalar parallel_fallback = 1
            capture ereturn scalar parallel_nproc = 1
            ereturn local parallel_requested_method "`parallel_requested_method'"
            ereturn local parallel_fallback_reason "payload_mismatch"
            ereturn local parallel_method "serial"
            exit 0
        }
        di as error "[pte] Error: fewer than 2 complete pooled bootstrap iterations"
        quietly use `orig_data', clear
        quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
        capture set rngstate `orig_rngstate'
        capture scalar drop _pte_in_bootstrap
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
        exit 2000
    }
    
    local alpha = (100 - `level') / 200
    
    // Compute SE, CI for pooled raw track
    tempname se_pool ci_lo_pool ci_hi_pool mean_pool
    matrix `se_pool' = J(1, `ncols', .)
    matrix `ci_lo_pool' = J(1, `ncols', .)
    matrix `ci_hi_pool' = J(1, `ncols', .)
    matrix `mean_pool' = J(1, `ncols', .)
    matrix colnames `se_pool' = `att_colnames'
    matrix colnames `ci_lo_pool' = `att_colnames'
    matrix colnames `ci_hi_pool' = `att_colnames'
    matrix colnames `mean_pool' = `att_colnames'
    
    // Trim track vectors
    if `do_trim' {
        tempname se_pool_trim ci_lo_trim ci_hi_trim mean_pool_trim
        matrix `se_pool_trim' = J(1, `ncols', .)
        matrix `ci_lo_trim' = J(1, `ncols', .)
        matrix `ci_hi_trim' = J(1, `ncols', .)
        matrix `mean_pool_trim' = J(1, `ncols', .)
        matrix colnames `se_pool_trim' = `att_colnames'
        matrix colnames `ci_lo_trim' = `att_colnames'
        matrix colnames `ci_hi_trim' = `att_colnames'
        matrix colnames `mean_pool_trim' = `att_colnames'
    }
    
    // Per-group SE matrices
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        tempname se_g`g_idx'
        matrix `se_g`g_idx'' = J(1, `ncols', .)
        matrix colnames `se_g`g_idx'' = `att_colnames'
    }
    
    // Use temporary dataset to compute column statistics
    preserve
    clear
    quietly set obs `nboot'
    
    // Load pooled raw track
    forvalues j = 1/`ncols' {
        quietly gen double _raw`j' = .
        forvalues bb = 1/`nboot' {
            local val = `att_boot_all'[`bb', `j']
            if !missing(`val') {
                quietly replace _raw`j' = `val' in `bb'
            }
        }
    }
    
    // Load pooled trim track
    if `do_trim' {
        forvalues j = 1/`ncols' {
            quietly gen double _trim`j' = .
            forvalues bb = 1/`nboot' {
                local val = `att_boot_trim'[`bb', `j']
                if !missing(`val') {
                    quietly replace _trim`j' = `val' in `bb'
                }
            }
        }
    }
    
    // Compute statistics for each column
    forvalues j = 1/`ncols' {
        // Raw track
        quietly summarize _raw`j'
        if r(N) >= 2 {
            matrix `mean_pool'[1, `j'] = r(mean)
            matrix `se_pool'[1, `j'] = r(sd)
            // Percentile CI
            sort _raw`j'
            quietly count if !missing(_raw`j')
            local nv = r(N)
            local lo_idx = max(1, ceil(`nv' * `alpha'))
            local hi_idx = min(`nv', floor(`nv' * (1 - `alpha')) + 1)
            matrix `ci_lo_pool'[1, `j'] = _raw`j'[`lo_idx']
            matrix `ci_hi_pool'[1, `j'] = _raw`j'[`hi_idx']
        }
        
        // Trim track
        if `do_trim' {
            quietly summarize _trim`j'
            if r(N) >= 2 {
                matrix `mean_pool_trim'[1, `j'] = r(mean)
                matrix `se_pool_trim'[1, `j'] = r(sd)
                sort _trim`j'
                quietly count if !missing(_trim`j')
                local nv = r(N)
                local lo_idx = max(1, ceil(`nv' * `alpha'))
                local hi_idx = min(`nv', floor(`nv' * (1 - `alpha')) + 1)
                matrix `ci_lo_trim'[1, `j'] = _trim`j'[`lo_idx']
                matrix `ci_hi_trim'[1, `j'] = _trim`j'[`hi_idx']
            }
        }
    }
    restore
    
    // Compute per-group SE (T9.1.3)
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        preserve
        clear
        quietly set obs `nboot'
        forvalues j = 1/`ncols' {
            quietly gen double _g`j' = .
            forvalues bb = 1/`nboot' {
                local val = `att_boot_g`g_idx''[`bb', `j']
                if !missing(`val') {
                    quietly replace _g`j' = `val' in `bb'
                }
            }
            quietly summarize _g`j'
            if r(N) >= 2 {
                matrix `se_g`g_idx''[1, `j'] = r(sd)
            }
        }
        restore
    }
    
    // Compute per-group BETA SE (T9.1.3)
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        tempname beta_se_g`g_idx'
        matrix `beta_se_g`g_idx'' = J(1, `beta_ncols', .)
        matrix colnames `beta_se_g`g_idx'' = `beta_colnames'
        preserve
        clear
        quietly set obs `nboot'
        forvalues j = 1/`beta_ncols' {
            quietly gen double _beta`j' = .
            forvalues bb = 1/`nboot' {
                local val = `beta_boot_g`g_idx''[`bb', `j']
                if !missing(`val') {
                    quietly replace _beta`j' = `val' in `bb'
                }
            }
            quietly summarize _beta`j'
            if r(N) >= 2 {
                matrix `beta_se_g`g_idx''[1, `j'] = r(sd)
            }
        }
        restore
    }

    // =========================================================================
    // Stage 7: Output display (T7.2)
    // =========================================================================
    
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "Bygroup Bootstrap ATT Results (`level'% CI, `ngroups' groups)"
        di as text "{hline 70}"
        di as text "  Total group draws:      " as result `=`ngroups' * `nboot''
        di as text "  Successful group draws: " as result `total_success'
        if `total_fail' > 0 {
            di as text "  Failed group draws:     " as result `total_fail'
        }
        di as text "  Complete pooled draws:  " as result `pooled_success' ///
            as text "/" as result `nboot'
        if `pooled_fail' > 0 {
            di as text "  Incomplete pooled draws:" as result `pooled_fail'
        }
        
        // Pooled raw track table
        di as text ""
        di as text "  Pooled ATT (Raw Track):"
        di as text "  " _col(5) "nt" _col(15) "ATT" _col(27) "BS_SE" ///
            _col(39) "[`level'% CI]"
        di as text "  {hline 62}"
        
        forvalues s = 0/`attperiods' {
            local col = `s' + 1
            local bse = `se_pool'[1, `col']
            local cil = `ci_lo_pool'[1, `col']
            local cih = `ci_hi_pool'[1, `col']
            local bsm = `mean_pool'[1, `col']
            if !missing(`bse') {
                di as text "  " _col(5) %3.0f `s' ///
                    _col(12) as result %10.4f `bsm' ///
                    _col(24) as result %10.4f `bse' ///
                    _col(36) as text "[" as result %8.4f `cil' ///
                    as text ", " as result %8.4f `cih' as text "]"
            }
        }
        
        // Overall row
        local bse_all = `se_pool'[1, `ncols']
        local cil_all = `ci_lo_pool'[1, `ncols']
        local cih_all = `ci_hi_pool'[1, `ncols']
        local bsm_all = `mean_pool'[1, `ncols']
        di as text "  {hline 62}"
        if !missing(`bse_all') {
            di as text "  " _col(5) "All" ///
                _col(12) as result %10.4f `bsm_all' ///
                _col(24) as result %10.4f `bse_all' ///
                _col(36) as text "[" as result %8.4f `cil_all' ///
                as text ", " as result %8.4f `cih_all' as text "]"
        }
        
        // Pooled trim track table (conditional)
        if `do_trim' {
            di as text ""
            di as text "  Pooled ATT (Trim Track, winsorized 1-99%):"
            di as text "  " _col(5) "nt" _col(15) "ATT_trim" _col(27) "BS_SE" ///
                _col(39) "[`level'% CI]"
            di as text "  {hline 62}"
            
            forvalues s = 0/`attperiods' {
                local col = `s' + 1
                local bse_t = `se_pool_trim'[1, `col']
                local cil_t = `ci_lo_trim'[1, `col']
                local cih_t = `ci_hi_trim'[1, `col']
                local bsm_t = `mean_pool_trim'[1, `col']
                if !missing(`bse_t') {
                    di as text "  " _col(5) %3.0f `s' ///
                        _col(12) as result %10.4f `bsm_t' ///
                        _col(24) as result %10.4f `bse_t' ///
                        _col(36) as text "[" as result %8.4f `cil_t' ///
                        as text ", " as result %8.4f `cih_t' as text "]"
                }
            }
            
            local bse_all_t = `se_pool_trim'[1, `ncols']
            local cil_all_t = `ci_lo_trim'[1, `ncols']
            local cih_all_t = `ci_hi_trim'[1, `ncols']
            local bsm_all_t = `mean_pool_trim'[1, `ncols']
            di as text "  {hline 62}"
            if !missing(`bse_all_t') {
                di as text "  " _col(5) "All" ///
                    _col(12) as result %10.4f `bsm_all_t' ///
                    _col(24) as result %10.4f `bse_all_t' ///
                    _col(36) as text "[" as result %8.4f `cil_all_t' ///
                    as text ", " as result %8.4f `cih_all_t' as text "]"
            }
        }
        
        // Per-group summary
        di as text ""
        di as text "  Per-group Bootstrap SE (raw, overall ATT):"
        local g_idx = 0
        foreach grp of local groups {
            local ++g_idx
            local gse = `se_g`g_idx''[1, `ncols']
            if !missing(`gse') {
                di as text "    `by' = " as result "`grp'" ///
                    as text ": SE = " as result %10.4f `gse'
            }
        }
        
        di as text "{hline 70}"
    }

    // Save the pooled bootstrap draws in the same wide format exposed by the
    // serial bootstrap worker so public saving() behaves consistently.
    if "`saving'" != "" {
        local _pte_save_rc = 0
        preserve
        capture noisily {
            quietly clear
            quietly set obs `nboot'
            quietly gen long boot_id = _n
            quietly gen double att_raw = .
            if `do_trim' {
                quietly gen double att_trim = .
            }
            forvalues s = 0/`attperiods' {
                quietly gen double att_raw_`s' = .
                if `do_trim' {
                    quietly gen double att_trim_`s' = .
                }
            }
            forvalues bb = 1/`nboot' {
                quietly replace att_raw = `att_boot_all'[`bb', `ncols'] in `bb'
                forvalues s = 0/`attperiods' {
                    local col = `s' + 1
                    quietly replace att_raw_`s' = `att_boot_all'[`bb', `col'] in `bb'
                }
                if `do_trim' {
                    quietly replace att_trim = `att_boot_trim'[`bb', `ncols'] in `bb'
                    forvalues s = 0/`attperiods' {
                        local col = `s' + 1
                        quietly replace att_trim_`s' = `att_boot_trim'[`bb', `col'] in `bb'
                    }
                }
            }
            quietly save "`saving'", replace
            di as text ""
            di as text "Bootstrap results saved to: " as result "`saving'"
        }
        local _pte_save_rc = _rc
        restore
        if `_pte_save_rc' != 0 {
            quietly use `orig_data', clear
            quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
            capture set rngstate `orig_rngstate'
            capture scalar drop _pte_in_bootstrap
            if `_pte_has_prev_est' {
                capture estimates restore `_pte_prev_est'
                capture estimates drop `_pte_prev_est'
            }
            else {
                capture ereturn clear
            }
            exit `_pte_save_rc'
        }
    }

    // =========================================================================
    // Stage 7.1: ereturn result storage (T7.1)
    // =========================================================================
    
    // Restore original data
    quietly use `orig_data', clear
    quietly xtset `idvar' `timevar'`_pte_boot_delta_opt'
    
    // Restore RNG state
    capture set rngstate `orig_rngstate'
    capture scalar drop _pte_in_bootstrap
    if `_pte_has_prev_est' {
        capture estimates drop `_pte_prev_est'
    }

    // Store results
    ereturn clear
    
    // --- Pooled ATT bootstrap distribution ---
    ereturn matrix att_boot_all = `att_boot_all'
    if `do_trim' {
        ereturn matrix att_boot_trim = `att_boot_trim'
    }
    
    // --- Pooled SE ---
    ereturn matrix att_se_pool = `se_pool'
    if `do_trim' {
        ereturn matrix att_se_pool_trim = `se_pool_trim'
    }
    
    // --- Pooled CI ---
    ereturn matrix att_ci_lower_pool = `ci_lo_pool'
    ereturn matrix att_ci_upper_pool = `ci_hi_pool'
    if `do_trim' {
        ereturn matrix att_ci_lower_trim = `ci_lo_trim'
        ereturn matrix att_ci_upper_trim = `ci_hi_trim'
    }
    
    // --- Pooled mean ---
    ereturn matrix att_mean_pool = `mean_pool'
    if `do_trim' {
        ereturn matrix att_mean_pool_trim = `mean_pool_trim'
    }
    
    // --- Per-group ATT bootstrap distributions ---
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        ereturn matrix att_boot_g`g_idx' = `att_boot_g`g_idx''
        if `do_trim' {
            ereturn matrix att_trim_boot_g`g_idx' = `att_trim_boot_g`g_idx''
        }
        ereturn matrix att_se_g`g_idx' = `se_g`g_idx''
        ereturn matrix beta_boot_g`g_idx' = `beta_boot_g`g_idx''
        ereturn matrix beta_se_g`g_idx' = `beta_se_g`g_idx''
    }
    
    local inner_seed_meta = .
    local inner_seed_source "inherited"
    if `use_inner_seed' {
        local inner_seed_meta = `inner_seed_val'
        if "`replicate'" == "trlg" & "`pfunc'" == "translog" & ///
            `omegapoly' == 1 & `inner_seed_meta' == 10000 {
            local inner_seed_source "replicate"
        }
        else {
            local inner_seed_source "user"
        }
    }

    // --- Scalar returns ---
    ereturn scalar nboot = `nboot'
    ereturn scalar ngroups = `ngroups'
    ereturn scalar n_success = `pooled_success'
    ereturn scalar n_fail = `pooled_fail'
    ereturn scalar n_success_group = `total_success'
    ereturn scalar n_fail_group = `total_fail'
    ereturn scalar industry_seed = `group_seed'
    if `use_inner_seed' {
        ereturn scalar inner_seed = `inner_seed_meta'
        ereturn scalar seed_inner = `inner_seed_meta'
    }
    ereturn scalar level = `level'
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar attperiods = `attperiods'
    ereturn scalar attperiods_max = `attperiods'
    ereturn scalar nsim = `nsim'
    ereturn scalar poly = `poly'
    ereturn scalar eps0window = `eps0window'
    ereturn scalar parallel_requested_nproc = `parallel_requested_nproc'
    ereturn scalar parallel_fallback = `parallel_fallback'
    if !missing(`parallel_helper_rc') {
        ereturn scalar parallel_helper_rc = `parallel_helper_rc'
    }
    
    // --- Local returns ---
    ereturn local groups "`groups'"
    ereturn local by "`by'"
    ereturn local treatment "`treatment'"
    ereturn local prodfunc "`pfunc'"
    ereturn local depvar "`depvar'"
    ereturn local free "`free'"
    ereturn local state "`state'"
    ereturn local proxy "`proxy'"
    if "`control'" != "" {
        ereturn local control "`control'"
    }
    if "`replicate'" != "" {
        ereturn local replicate "`replicate'"
    }
    ereturn local inner_seed_source "`inner_seed_source'"
    ereturn local parallel_requested_method "`parallel_requested_method'"
    ereturn local parallel_fallback_reason "`parallel_fallback_reason'"
    ereturn local parallel_method "`parallel_method'"
    ereturn scalar parallel_nproc = `parallel_nproc'
    ereturn local cmd_bootstrap "_pte_bootstrap_bygroup"
    ereturn local cmd "_pte_bootstrap_bygroup"
    ereturn local title "PTE Bygroup Bootstrap Inference"
    
end
