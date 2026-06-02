*! _pte_bootstrap_parallel.ado
*! Parallel Bootstrap Execution
*! Integrates SSC parallel package for bootstrap acceleration
*!
*! Strategy: parallel do with nodata + file-based result passing
*!   1. Save data to temp file for workers to load
*!   2. Write a worker do-file that:
*!      - Computes its iteration range from $pll_instance
*!      - Loops over assigned iterations calling _pte_bootstrap_single
*!      - Saves results to a worker-specific temp file
*!   3. Execute via parallel do (nodata, programs, mata)
*!   4. Collect results from worker temp files into full matrices
*!
*! Note: parallel package does NOT preserve matrices/scalars across
*! workers (see parallel help "Caveats"), so file-based passing is
*! required for collecting ATT results.
*!
*! Two-layer seed management:
*!   - Outer seed: set seed seed()+b-1 per iteration (same as serial)
*!   - Inner seed: fixed, passed as parameter to _pte_bootstrap_single

version 14.0
capture program drop _pte_bootstrap_parallel
program define _pte_bootstrap_parallel, rclass
    version 14.0
    local _pte_cmdline `"`0'"'
    foreach _pte_input_opt in treatment depvar free state proxy id time {
        local _pte_`_pte_input_opt'_literal ""
        if regexm(lower(`"`_pte_cmdline'"'), ///
            "(^|[ ,])`_pte_input_opt'[(]([^)]*)[)]") {
            local _pte_`_pte_input_opt'_literal `"`=regexs(2)'"'
            local _pte_`_pte_input_opt'_literal = ///
                lower(strtrim(`"`_pte_`_pte_input_opt'_literal'"'))
        }
    }
    local _pte_control_literal ""
    if regexm(lower(`"`_pte_cmdline'"'), ///
        "(^|[ ,])(control|contro|contr|cont)[ ]*[(]([^)]*)[)]") {
        local _pte_control_literal `"`=regexs(3)'"'
        local _pte_control_literal = ///
            lower(strtrim(`"`_pte_control_literal'"'))
    }
    syntax, nboot(integer) nproc(integer) ///
        treatment(varname) ///
        depvar(varname) free(varname) state(varname) proxy(varname) ///
        id(varname) time(varname) ///
        [omegapoly(integer 3) ///
         attperiods(integer 4) ///
         nsim(integer -1) ///
         eps0window(integer 0) ///
         seed(integer 1) ///
         inner_seed(integer 123456) ///
         prodfunc(string) ///
         poly(integer -1) ///
         touse(name) ///
         control(varlist) ///
         REPlicate ///
         NOTRIMeps ///
         NOLOg]

    local _pte_treatment_resolved = lower(`"`treatment'"')
    local _pte_depvar_resolved = lower(`"`depvar'"')
    local _pte_free_resolved = lower(`"`free'"')
    local _pte_state_resolved = lower(`"`state'"')
    local _pte_proxy_resolved = lower(`"`proxy'"')
    local _pte_id_resolved = lower(`"`id'"')
    local _pte_time_resolved = lower(`"`time'"')
    foreach _pte_input_opt in treatment depvar free state proxy id time {
        if `"`_pte_`_pte_input_opt'_literal'"' != "" & ///
            `"`_pte_`_pte_input_opt'_literal'"' != `"`_pte_`_pte_input_opt'_resolved'"' {
            di as error "[pte] Error: variable '`_pte_`_pte_input_opt'_literal'' not found"
            exit 111
        }
    }
    if `"`_pte_control_literal'"' != "" & "`control'" != "" {
        local _pte_control_literal = lower(itrim(strtrim(`"`_pte_control_literal'"')))
        local _pte_control_resolved = lower(itrim(strtrim(`"`control'"')))
        if `"`_pte_control_literal'"' != `"`_pte_control_resolved'"' {
            di as error "[pte] Error: control() variables must be specified with exact existing variable names"
            exit 111
        }
    }
    
    if "`prodfunc'" == "" {
        local prodfunc "cd"
    }
    local _pte_has_poly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])poly[(]")
    local _pte_has_omegapoly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])omegapoly[(]")
    if `_pte_has_poly' {
        if `_pte_has_omegapoly' & `poly' != `omegapoly' {
            di as error "[pte] Error: cannot specify both poly(`poly') and omegapoly(`omegapoly')"
            exit 198
        }
        local omegapoly = `poly'
    }
    local poly = `omegapoly'

    // Keep omitted nsim() consistent with the serial bootstrap contract
    // before forwarding it to each single-iteration worker.
    if `nsim' == -1 {
        if `omegapoly' == 1 {
            local nsim = 1
        }
        else {
            local nsim = 100
        }
    }
    if `nsim' < 1 {
        di as error "[pte] Error: nsim must be >= 1"
        exit 198
    }
    if `nboot' < 2 {
        di as error "[pte] Error: nboot must be >= 2"
        exit 198
    }
    if `nproc' < 1 {
        di as error "[pte] Error: nproc must be >= 1"
        exit 198
    }
    if `seed' < 1 {
        di as error "[pte] Error: seed must be >= 1"
        exit 198
    }
    if `seed' > 2147483647 {
        di as error "[pte] Error: seed exceeds maximum value (2147483647)"
        exit 198
    }
    if `seed' > 2147483647 - `nboot' + 1 {
        di as error "[pte] Error: seed() is too large for nboot(`nboot')"
        exit 198
    }
    local _pte_inner_seed_validate = `inner_seed'
    if "`replicate'" != "" & "`prodfunc'" == "translog" & `omegapoly' == 1 {
        local _pte_inner_seed_validate = 10000
    }
    if `_pte_inner_seed_validate' < 1 {
        di as error "[pte] Error: inner_seed must be >= 1"
        exit 198
    }
    if `_pte_inner_seed_validate' > 2147483647 {
        di as error "[pte] Error: inner_seed exceeds maximum value (2147483647)"
        exit 198
    }
    local inner_seed = `_pte_inner_seed_validate'

    capture _xt, trequired
    if _rc != 0 {
        di as error "[pte] Error: data must be xtset as panel"
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)
    if "`panelvar'" != "`id'" | "`timevar'" != "`time'" {
        di as error "[pte] xtset must match id() and time()"
        di as error "  current xtset: `panelvar' `timevar'"
        di as error "  requested:     `id' `time'"
        di as error "  run {bf:xtset `id' `time'} before calling _pte_bootstrap_parallel"
        exit 459
    }
    if "`touse'" != "" {
        capture confirm variable `touse', exact
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' not found"
            exit 111
        }
        capture confirm numeric variable `touse'
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' must be numeric"
            exit 111
        }
    }

    // Worker launch must be quiet-safe because the official bootstrap DOs wrap
    // large chunks of the resampling loop in quietly blocks. SSC parallel's
    // programs() export path can report success yet skip worker side effects
    // when the caller suppresses output, so quiet callers fall back to
    // worker-side disk loading of the canonical helper ado files.
    capture findfile _pte_bootstrap_single.ado
    if _rc != 0 {
        di as error "[pte] Error: worker helper _pte_bootstrap_single.ado not found on adopath"
        exit 111
    }
    local _pte_file_bootsingle `"`r(fn)'"'
    local _pte_worker_ado_dir = subinstr(`"`_pte_file_bootsingle'"', ///
        "/_pte_bootstrap_single.ado", "", .)

    capture findfile _pte_prodfunc.ado
    if _rc != 0 {
        di as error "[pte] Error: worker helper _pte_prodfunc.ado not found on adopath"
        exit 111
    }
    local _pte_file_prodfunc `"`r(fn)'"'

    capture findfile _pte_omega.ado
    if _rc != 0 {
        di as error "[pte] Error: worker helper _pte_omega.ado not found on adopath"
        exit 111
    }
    local _pte_file_omega `"`r(fn)'"'

    capture findfile _pte_att.ado
    if _rc != 0 {
        di as error "[pte] Error: worker helper _pte_att.ado not found on adopath"
        exit 111
    }
    local _pte_file_att `"`r(fn)'"'
    local _pte_worker_programs "_pte_bootstrap_single _pte_prodfunc _pte_omega _pte_att"
    local _pte_use_program_export = c(noisily)
    
    local nperiods = `attperiods' + 1
    local ncols = 1 + `nperiods'
    local do_trim = ("`notrimeps'" == "")
    local bs_pf_cols = cond("`prodfunc'" == "cd", 2, 5)
    local nbeta_cols = cond("`prodfunc'" == "cd", 3, 6)
    local bs_beta_colnames = cond("`prodfunc'" == "cd", ///
        "beta_l beta_k beta_t", ///
        "beta_l beta_k beta_ll beta_kk beta_lk beta_t")
    local n_control : word count `control'
    if `n_control' > 1 {
        local nbeta_cols = `bs_pf_cols' + `n_control'
        local bs_beta_colnames = cond("`prodfunc'" == "cd", ///
            "beta_l beta_k `control'", ///
            "beta_l beta_k beta_ll beta_kk beta_lk `control'")
    }
    
    // ================================================================
    // Task 14: Initialize parallel environment
    // ================================================================
    
    // Cap effective workers at nboot (no idle workers)
    local nproc_eff = min(`nproc', `nboot')
    
    // Set number of clusters for parallel package. On macOS app-bundle
    // installs, parallel's automatic path probe can resolve to the
    // non-existent legacy stub /Applications/Stata/stata-mp. Prefer the
    // real bundle executable when it exists so worker launch matches the
    // current Stata installation.
    local _pte_parallel_statapath ""
    capture confirm file "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp"
    if _rc == 0 {
        local _pte_parallel_statapath "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp"
    }
    else {
        capture confirm file "/Applications/Stata/StataMP.app/Contents/MacOS/StataMP"
        if _rc == 0 {
            local _pte_parallel_statapath "/Applications/Stata/StataMP.app/Contents/MacOS/StataMP"
        }
    }
    if "`_pte_parallel_statapath'" != "" {
        parallel setclusters `nproc_eff', force statapath(`_pte_parallel_statapath')
    }
    else {
        parallel setclusters `nproc_eff', force
    }
    
    // Save current data for workers to load
    tempfile _pte_par_data
    quietly save `_pte_par_data', replace
    
    // Compute task allocation per worker (ceiling division)
    local batch_size = ceil(`nboot' / `nproc_eff')
    
    // Generate a run-unique prefix for worker result files so the collector
    // cannot ingest stale artifacts from a previous aborted bootstrap run.
    tempfile _pte_result_prefix
    local result_prefix "`_pte_result_prefix'"
    local result_runid "`result_prefix'"
    
    if "`nolog'" == "" {
        di as text ""
        di as text "[pte] Parallel bootstrap: `nproc_eff' workers, " ///
            "`nboot' iterations (batch_size=`batch_size')"
    }
    
    // ================================================================
    // Task 15: Generate worker do-file for parallel execution
    // ================================================================
    //
    // The worker do-file is executed by each parallel instance.
    // Each worker gets $pll_instance (1..nproc_eff) to determine
    // its assigned iteration range.
    //
    // Worker flow:
    //   1. Load saved data
    //   2. Compute iteration range [start_b, end_b]
    //   3. Loop: call _pte_bootstrap_single for each b
    //   4. Save result matrices to worker-specific .dta file
    
    // Build option string for _pte_bootstrap_single
    local _bs_opts "treatment(`treatment') depvar(`depvar') free(`free')"
    local _bs_opts "`_bs_opts' state(`state') proxy(`proxy')"
    local _bs_opts "`_bs_opts' id(`id') time(`time')"
    local _bs_opts "`_bs_opts' omegapoly(`omegapoly') attperiods(`attperiods')"
    local _bs_opts "`_bs_opts' nsim(`nsim') eps0window(`eps0window')"
    local _bs_opts "`_bs_opts' seed(`seed') inner_seed(`inner_seed')"
    local _bs_opts "`_bs_opts' prodfunc(`prodfunc') poly(`poly')"
    if "`touse'" != "" {
        local _bs_opts "`_bs_opts' touse(`touse')"
    }
    if "`control'" != "" {
        local _bs_opts "`_bs_opts' control(`control')"
    }
    if "`replicate'" != "" {
        local _bs_opts "`_bs_opts' replicate"
    }
    if "`notrimeps'" != "" {
        local _bs_opts "`_bs_opts' notrimeps"
    }
    local _bs_opts "`_bs_opts' nodiagnose"
    
    // Write the worker do-file to a temp location
    tempfile _pte_worker_dofile
    tempname fh
    file open `fh' using `_pte_worker_dofile', write replace
    
    // --- Worker preamble: compute iteration range ---
    file write `fh' "// PTE Bootstrap Worker Do-File" _n
    file write `fh' "// Auto-generated by _pte_bootstrap_parallel" _n
    file write `fh' "" _n
    file write `fh' `"adopath + "`_pte_worker_ado_dir'""' _n
    file write `fh' `"quietly do "`_pte_file_bootsingle'""' _n
    file write `fh' `"quietly do "`_pte_file_prodfunc'""' _n
    file write `fh' `"quietly do "`_pte_file_omega'""' _n
    file write `fh' `"quietly do "`_pte_file_att'""' _n
    file write `fh' "" _n
    file write `fh' `"local worker_id = \$pll_instance"' _n
    file write `fh' `"local batch_size = `batch_size'"' _n
    file write `fh' `"local nboot = `nboot'"' _n
    file write `fh' `"local ncols = `ncols'"' _n
    file write `fh' `"local do_trim = `do_trim'"' _n
    file write `fh' `"local result_runid "`result_runid'""' _n
    file write `fh' "" _n
    file write `fh' `"local start_b = (\`worker_id' - 1) * \`batch_size' + 1"' _n
    file write `fh' `"local end_b = min(\`worker_id' * \`batch_size', \`nboot')"' _n
    file write `fh' `"local n_iter = \`end_b' - \`start_b' + 1"' _n
    file write `fh' "" _n
    
    // --- Worker: skip if no iterations assigned ---
    file write `fh' `"if \`n_iter' <= 0 {"' _n
    file write `fh' `"    exit"' _n
    file write `fh' `"}"' _n
    file write `fh' "" _n
    
    // --- Worker: initialize result matrices ---
    file write `fh' `"matrix _W_RAW = J(\`n_iter', \`ncols', .)"' _n
    file write `fh' `"matrix _W_BETAS = J(\`n_iter', `nbeta_cols', .)"' _n
    file write `fh' `"matrix _W_OK = J(\`n_iter', 1, 0)"' _n
    file write `fh' `"if \`do_trim' {"' _n
    file write `fh' `"    matrix _W_TRIM = J(\`n_iter', \`ncols', .)"' _n
    file write `fh' `"}"' _n
    file write `fh' `"local n_success = 0"' _n
    file write `fh' `"local n_fail = 0"' _n
    file write `fh' "" _n
    
    // --- Worker: bootstrap iteration loop ---
    file write `fh' `"local row = 0"' _n
    file write `fh' `"forvalues b = \`start_b'/\`end_b' {"' _n
    file write `fh' `"    local ++row"' _n
    file write `fh' "" _n
    
    // Load fresh data for each iteration
    file write `fh' `"    quietly use "`_pte_par_data'", clear"' _n
    file write `fh' "" _n
    
    // Call _pte_bootstrap_single with error handling
    file write `fh' `"    capture {"' _n
    file write `fh' `"        _pte_bootstrap_single, b(\`b') `_bs_opts'"' _n
    file write `fh' `"    }"' _n
    file write `fh' `"    if _rc == 0 {"' _n
    file write `fh' `"        matrix _R_RAW = r(att_raw)"' _n
    file write `fh' `"        matrix _R_BETAS = r(betas)"' _n
    file write `fh' `"        forvalues j = 1/\`ncols' {"' _n
    file write `fh' `"            matrix _W_RAW[\`row', \`j'] = _R_RAW[1, \`j']"' _n
    file write `fh' `"        }"' _n
    file write `fh' `"        forvalues j = 1/`nbeta_cols' {"' _n
    file write `fh' `"            matrix _W_BETAS[\`row', \`j'] = _R_BETAS[1, \`j']"' _n
    file write `fh' `"        }"' _n
    file write `fh' `"        matrix _W_OK[\`row', 1] = 1"' _n
    file write `fh' `"        if \`do_trim' {"' _n
    file write `fh' `"            matrix _R_TRIM = r(att_trim)"' _n
    file write `fh' `"            forvalues j = 1/\`ncols' {"' _n
    file write `fh' `"                matrix _W_TRIM[\`row', \`j'] = _R_TRIM[1, \`j']"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"        }"' _n
    file write `fh' `"        local ++n_success"' _n
    file write `fh' `"    }"' _n
    file write `fh' `"    else {"' _n
    file write `fh' `"        local ++n_fail"' _n
    file write `fh' `"    }"' _n
    file write `fh' `"}"' _n
    file write `fh' "" _n
    
    // --- Worker: save results to worker-specific file ---
    // Since parallel does not preserve matrices across workers,
    // we convert matrices to a dataset and save to a temp file.
    local _pte_raw_cols ""
    forvalues j = 1/`ncols' {
        local _pte_raw_cols "`_pte_raw_cols' _pte_raw_`j'"
    }
    local _pte_beta_cols ""
    forvalues j = 1/`nbeta_cols' {
        local _pte_beta_cols "`_pte_beta_cols' _pte_beta_`j'"
    }
    local _pte_trim_cols ""
    if `do_trim' {
        forvalues j = 1/`ncols' {
            local _pte_trim_cols "`_pte_trim_cols' _pte_trim_`j'"
        }
    }
    file write `fh' `"matrix colnames _W_RAW = `_pte_raw_cols'"' _n
    file write `fh' `"matrix colnames _W_BETAS = `_pte_beta_cols'"' _n
    file write `fh' `"matrix colnames _W_OK = _pte_ok"' _n
    if `do_trim' {
        file write `fh' `"matrix colnames _W_TRIM = `_pte_trim_cols'"' _n
    }
    file write `fh' `"clear"' _n
    file write `fh' `"quietly svmat double _W_RAW, names(col)"' _n
    file write `fh' `"quietly svmat double _W_BETAS, names(col)"' _n
    file write `fh' `"quietly svmat double _W_OK, names(col)"' _n
    if `do_trim' {
        file write `fh' `"quietly svmat double _W_TRIM, names(col)"' _n
    }
    file write `fh' `"quietly recast byte _pte_ok"' _n
    file write `fh' `"quietly gen long _pte_b = ."' _n
    file write `fh' `"quietly gen int _pte_worker = \`worker_id'"' _n
    file write `fh' `"quietly gen str244 _pte_result_runid = "\`result_runid'""' _n
    file write `fh' `"local row = 0"' _n
    file write `fh' `"forvalues b = \`start_b'/\`end_b' {"' _n
    file write `fh' `"    local ++row"' _n
    file write `fh' `"    quietly replace _pte_b = \`b' in \`row'"' _n
    file write `fh' `"}"' _n
    file write `fh' "" _n
    
    // Save worker results to file
    file write `fh' `"quietly save "`result_prefix'_\`worker_id'.dta", replace"' _n
    file write `fh' "" _n
    
    file close `fh'
    
    // ================================================================
    // Task 16: Execute parallel do and merge results
    // ================================================================
    
    // --- Step 16a: Execute parallel do ---
    //
    // Key options:
    //   nodata    - Workers do not receive split data; they load
    //               the full dataset from _pte_par_data themselves
    //   programs  - Pass all _pte_* programs to worker instances
    //   mata      - Pass mata objects (GMM functions etc.)
    //   noglobal  - Do not pass globals (workers set their own)
    //
    // Each worker gets $pll_instance (1..nproc_eff) automatically.
    
    if "`nolog'" == "" {
        di as text "[pte] Launching parallel do with `nproc_eff' workers..."
    }

    // Match the serial bootstrap contract: worker-side set seed calls must
    // not leak into the caller RNG stream after the helper returns.
    local _pte_orig_rngstate = c(rngstate)
    
    // Set bootstrap flag for downstream modules
    scalar _pte_in_bootstrap = 1
    
    if `_pte_use_program_export' {
        // When the caller is noisy, preserve the classic programs() contract
        // for fresh-session helper export tests and worker bootstrap setup.
        foreach prog of local _pte_worker_programs {
            capture program list `prog'
            if _rc == 0 {
                continue
            }
            capture findfile `prog'.ado
            if _rc != 0 {
                di as error "[pte] Error: worker helper `prog'.ado not found on adopath"
                capture scalar drop _pte_in_bootstrap
                capture parallel clean, force
                capture set rngstate `_pte_orig_rngstate'
                quietly use `_pte_par_data', clear
                return clear
                exit 111
            }
            local _pte_progfile `"`r(fn)'"'
            quietly do `"`_pte_progfile'"'
            capture program list `prog'
            if _rc != 0 {
                di as error "[pte] Error: failed to preload worker helper `prog'"
                capture scalar drop _pte_in_bootstrap
                capture parallel clean, force
                capture set rngstate `_pte_orig_rngstate'
                quietly use `_pte_par_data', clear
                return clear
                exit 111
            }
        }
    }

    capture noisily {
        if `_pte_use_program_export' {
            parallel do `_pte_worker_dofile', ///
                nodata ///
                programs(`_pte_worker_programs') ///
                mata ///
                noglobal
        }
        else {
            parallel do `_pte_worker_dofile', ///
                nodata ///
                mata ///
                noglobal
        }
    }
    local pll_rc = _rc
    
    // Clear bootstrap flag
    capture scalar drop _pte_in_bootstrap
    
    if `pll_rc' != 0 {
        di as error "[pte] parallel do failed with rc=`pll_rc'"
        di as error "[pte] Checking worker logs for details..."
        capture parallel seelog
    }
    
    // --- Step 16b: Collect results from worker files ---
    //
    // Each worker saved a .dta file with columns:
    //   _pte_b       : iteration number
    //   _pte_worker  : worker ID
    //   _pte_ok      : 1 if iteration succeeded
    //   _pte_raw_1..ncols : raw track ATT values
    //   _pte_trim_1..ncols : trim track ATT values (if do_trim)
    //   _pte_beta_1..nbeta_cols : production-function beta draws
    //
    // We append all worker files, then reconstruct the full matrices.
    
    if "`nolog'" == "" {
        di as text "[pte] Collecting results from `nproc_eff' workers..."
    }
    
    // Append worker result files
    local first_loaded = 0
    local found_workers = 0
    forvalues w = 1/`nproc_eff' {
        local wfile "`result_prefix'_`w'.dta"
        capture confirm file "`wfile'"
        if _rc == 0 {
            local ++found_workers
            if `first_loaded' == 0 {
                quietly use "`wfile'", clear
                local first_loaded = 1
            }
            else {
                quietly append using "`wfile'"
            }
            // Clean up worker file
            capture erase "`wfile'"
        }
        else {
            if "`nolog'" == "" {
                di as text "[pte] Warning: worker `w' result file not found"
            }
        }
    }

    if `first_loaded' == 1 & `pll_rc' != 0 & `found_workers' == `nproc_eff' {
        if "`nolog'" == "" {
            di as text "[pte] Recovered complete worker result files despite parallel rc=`pll_rc'; validating payload contract"
        }
    }
    else if `pll_rc' != 0 {
        di as text "[pte] Warning: bootstrap parallel helper could not recover a complete current-run worker file set after rc=`pll_rc'"
        capture parallel clean, force
        capture set rngstate `_pte_orig_rngstate'
        quietly use `_pte_par_data', clear
        return clear
        exit `pll_rc'
    }
    
    if `first_loaded' == 0 {
        di as error "[pte] Error: no worker result files found"
        capture parallel clean, force
        quietly use `_pte_par_data', clear
        capture set rngstate `_pte_orig_rngstate'
        return clear
        exit 2000
    }

    capture confirm string variable _pte_result_runid
    if _rc != 0 {
        di as error "[pte] Error: worker results missing current-run provenance metadata"
        capture parallel clean, force
        capture set rngstate `_pte_orig_rngstate'
        quietly use `_pte_par_data', clear
        return clear
        exit 2000
    }
    tempvar _pte_bad_runid
    quietly gen byte `_pte_bad_runid' = missing(_pte_result_runid) | ///
        _pte_result_runid != "`result_runid'"
    quietly count if `_pte_bad_runid'
    if r(N) > 0 {
        di as error "[pte] Error: worker results do not belong to the current bootstrap run"
        capture parallel clean, force
        capture set rngstate `_pte_orig_rngstate'
        quietly use `_pte_par_data', clear
        return clear
        exit 2000
    }
    if `pll_rc' != 0 {
        quietly count
        if r(N) != `nboot' {
            di as error "[pte] Error: launcher rc left an incomplete current-run worker payload"
            capture parallel clean, force
            capture set rngstate `_pte_orig_rngstate'
            quietly use `_pte_par_data', clear
            return clear
            exit `pll_rc'
        }
    }
    
    // --- Step 16c: Reconstruct full result matrices ---
    //
    // Sort by _pte_b to ensure iteration order is preserved,
    // then fill matrices row by row.
    
    sort _pte_b

    // Fail closed when worker files cannot be mapped one-to-one onto the
    // bootstrap iteration index. Bootstrap inference is defined over the
    // nboot scheduled resamples; duplicate or out-of-range identities can
    // falsely inflate the success count and corrupt the draw-to-iteration map.
    tempvar _pte_invalid_b _pte_dup_b
    quietly gen byte `_pte_invalid_b' = missing(_pte_b) | _pte_b < 1 | _pte_b > `nboot'
    quietly count if `_pte_invalid_b'
    if r(N) > 0 {
        di as error "[pte] Error: worker results contain out-of-range bootstrap iteration ids"
        capture parallel clean, force
        capture set rngstate `_pte_orig_rngstate'
        quietly use `_pte_par_data', clear
        return clear
        exit 2000
    }
    quietly bysort _pte_b: gen byte `_pte_dup_b' = (_N > 1)
    quietly count if `_pte_dup_b'
    if r(N) > 0 {
        di as error "[pte] Error: worker results contain duplicate bootstrap iteration ids"
        capture parallel clean, force
        capture set rngstate `_pte_orig_rngstate'
        quietly use `_pte_par_data', clear
        return clear
        exit 2000
    }
    
    // A worker row marked successful must carry the schema expected by the
    // collector, but it does not need horizon-complete ATT payloads. The live
    // ATT/bootstrap-single contract allows later horizons to be missing when a
    // draw lacks support there, while still requiring the pooled ATT and the
    // nt=0 effect that anchors the ATT recursion. Parallel replay must reject
    // malformed success rows, not legal late-horizon support loss.
    local _pte_required_schema "_pte_ok _pte_b"
    forvalues j = 1/`ncols' {
        local _pte_required_schema "`_pte_required_schema' _pte_raw_`j'"
    }
    forvalues j = 1/`nbeta_cols' {
        local _pte_required_schema "`_pte_required_schema' _pte_beta_`j'"
    }
    if `do_trim' {
        forvalues j = 1/`ncols' {
            local _pte_required_schema "`_pte_required_schema' _pte_trim_`j'"
        }
    }
    foreach _pte_schema_var of local _pte_required_schema {
        capture confirm numeric variable `_pte_schema_var'
        if _rc != 0 {
            di as error "[pte] Error: worker results missing required bootstrap payload columns"
            capture parallel clean, force
            capture set rngstate `_pte_orig_rngstate'
            quietly use `_pte_par_data', clear
            return clear
            exit 2000
        }
    }
    tempvar _pte_invalid_status
    quietly gen byte `_pte_invalid_status' = missing(_pte_ok) | !inlist(_pte_ok, 0, 1)
    quietly count if `_pte_invalid_status'
    if r(N) > 0 {
        di as error "[pte] Error: worker results contain invalid bootstrap status markers"
        capture parallel clean, force
        capture set rngstate `_pte_orig_rngstate'
        quietly use `_pte_par_data', clear
        return clear
        exit 2000
    }
    tempvar _pte_missing_payload
    local _pte_missing_expr "missing(_pte_raw_1) | missing(_pte_raw_2)"
    forvalues j = 1/`nbeta_cols' {
        local _pte_missing_expr "`_pte_missing_expr' | missing(_pte_beta_`j')"
    }
    if `do_trim' {
        local _pte_missing_expr "`_pte_missing_expr' | missing(_pte_trim_1) | missing(_pte_trim_2)"
    }
    quietly gen byte `_pte_missing_payload' = (_pte_ok == 1) & (`_pte_missing_expr')
    quietly count if `_pte_missing_payload'
    if r(N) > 0 {
        di as error "[pte] Error: worker results mark success without required pooled bootstrap payloads"
        capture parallel clean, force
        capture set rngstate `_pte_orig_rngstate'
        quietly use `_pte_par_data', clear
        return clear
        exit 2000
    }

    // Count successes and failures
    quietly count if _pte_ok == 1
    local n_success = r(N)
    quietly count if _pte_ok == 0
    local n_fail = r(N)
    
    // Check for missing iterations (workers that produced no output)
    quietly count
    local n_total_rows = r(N)
    local n_missing = `nboot' - `n_total_rows'
    if `n_missing' > 0 {
        local n_fail = `n_fail' + `n_missing'
    }

    // Match the serial bootstrap inference law: bootstrap SE / percentile CI
    // are undefined unless at least two draws completed successfully.
    if `n_success' < 2 {
        di as error "[pte] Error: fewer than 2 successful bootstrap iterations"
        di as error "[pte] Cannot compute standard errors"
        capture parallel clean, force
        capture set rngstate `_pte_orig_rngstate'
        quietly use `_pte_par_data', clear
        return clear
        exit 2000
    }

    // Initialize full result matrices
    tempname bs_raw bs_trim bs_betas
    matrix `bs_raw' = J(`nboot', `ncols', .)
    if `do_trim' {
        matrix `bs_trim' = J(`nboot', `ncols', .)
    }
    matrix `bs_betas' = J(`nboot', `nbeta_cols', .)
    matrix colnames `bs_betas' = `bs_beta_colnames'
    
    // Fill matrices from the appended dataset
    // Each row in the dataset corresponds to one bootstrap iteration
    local nobs = _N
    forvalues i = 1/`nobs' {
        local b_val = _pte_b[`i']
        local ok_val = _pte_ok[`i']
        
        // Validate iteration number is in range
        if `b_val' < 1 | `b_val' > `nboot' {
            continue
        }
        
        if `ok_val' == 1 {
            // Fill raw track
            forvalues j = 1/`ncols' {
                capture {
                    if !missing(_pte_raw_`j'[`i']) {
                        matrix `bs_raw'[`b_val', `j'] = _pte_raw_`j'[`i']
                    }
                }
            }

            // Fill beta draws
            forvalues j = 1/`nbeta_cols' {
                capture {
                    if !missing(_pte_beta_`j'[`i']) {
                        matrix `bs_betas'[`b_val', `j'] = _pte_beta_`j'[`i']
                    }
                }
            }
            
            // Fill trim track
            if `do_trim' {
                forvalues j = 1/`ncols' {
                    capture {
                        if !missing(_pte_trim_`j'[`i']) {
                            matrix `bs_trim'[`b_val', `j'] = _pte_trim_`j'[`i']
                        }
                    }
                }
            }
        }
    }
    
    // ================================================================
    // Cleanup and restore
    // ================================================================
    
    // Clean up parallel auxiliary files
    capture parallel clean, force
    capture set rngstate `_pte_orig_rngstate'
    
    // Restore original data
    quietly use `_pte_par_data', clear
    
    // Display summary
    if "`nolog'" == "" {
        di as text ""
        di as text "[pte] Parallel bootstrap completed:"
        di as text "  Workers used:     " as result `nproc_eff'
        di as text "  Successful:       " as result `n_success' as text "/" as result `nboot'
        if `n_fail' > 0 {
            di as text "  Failed:           " as result `n_fail'
        }
    }
    
    // ================================================================
    // Return results
    // ================================================================
    return matrix bs_raw = `bs_raw'
    if `do_trim' {
        return matrix bs_trim = `bs_trim'
    }
    return matrix bs_betas = `bs_betas'
    return scalar n_success = `n_success'
    return scalar n_fail = `n_fail'
    return scalar nproc_eff = `nproc_eff'
    return scalar nboot = `nboot'
    return scalar batch_size = `batch_size'
end
