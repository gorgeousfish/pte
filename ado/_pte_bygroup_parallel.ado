*! _pte_bygroup_parallel.ado
*! Distributes industry-level bootstrap across parallel workers.
*! Each worker processes a subset of industries, running the full
*! B bootstrap iterations for each assigned industry.
*! Strategy: parallel do with nodata + file-based result passing
*! 1. Save data to temp file
*! 2. Write worker do-file that:
*! - Determines assigned industries from $pll_instance
*! - For each assigned industry: set seed, run B iterations
*! - Save per-industry per-iteration TT data + ATT/BETA matrices
*! 3. Execute via parallel do
*! 4. Collect results from worker files
*! T6.3 Consistency guarantee:
*! - Each worker uses the SAME group_seed for its assigned industries
*! - Workers load independent copies of the full dataset
*! - Results are identical to serial execution because:
*! (a) Same seed per industry
*! (b) Same bootstrap iteration sequence
*! (c) Same estimation pipeline

version 14.0
capture program drop _pte_bygroup_parallel
program define _pte_bygroup_parallel, rclass
    version 14.0
    local _pte_cmdline `"`0'"'
    syntax, nboot(integer) nproc(integer) ngroups(integer) ///
        groups(string) by(varname) ///
        treatment(varname) ///
        depvar(varname) free(varname) state(varname) proxy(varname) ///
        id(varname) time(varname) ///
        group_seed(integer) tousevar(name) ///
        [omegapoly(integer 3) ///
         attperiods(integer 4) ///
         nsim(integer 100) ///
         eps0window(integer 0) ///
         inner_seed(integer -1) ///
         ttprefix(string) ///
         runid(string) ///
         prodfunc(string) ///
         poly(integer -1) ///
         control(varlist) ///
         NOTRIMeps ///
         NOLOg ///
         NODIAGnose]
    
    if "`prodfunc'" == "" local prodfunc "translog"
    if `"`ttprefix'"' == "" local ttprefix "pte_tt_g"
    local _pte_has_poly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])poly[(]")
    local _pte_has_omegapoly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])omegapoly[(]")
    if `_pte_has_poly' {
        if `poly' < 1 | `poly' > 4 {
            di as error "[pte] _pte_bygroup_parallel: poly() must be between 1 and 4"
            exit 198
        }
        if `_pte_has_omegapoly' & `poly' != `omegapoly' {
            di as error "[pte] _pte_bygroup_parallel: cannot specify both poly(`poly') and omegapoly(`omegapoly')"
            exit 198
        }
        local omegapoly = `poly'
    }
    local poly = `omegapoly'
    
    local nperiods = `attperiods' + 1
    local ncols = 1 + `nperiods'
    local do_trim = ("`notrimeps'" == "")
    local use_inner_seed = (`inner_seed' != -1)
    local _pte_n_controls : word count `control'

    // parallel package child sessions load exported globals from disk. Clear
    // any stale PTE_PAR_* state first so this helper never dispatches the
    // legacy _pte_group_worker chain from another module.
    if `group_seed' < 1 {
        di as error "[pte] _pte_bygroup_parallel: group_seed() must be a positive integer"
        exit 198
    }
    if `group_seed' > 2147483647 {
        di as error "[pte] _pte_bygroup_parallel: group_seed() exceeds maximum value (2147483647)"
        exit 198
    }
    capture noisily _pte_parallel_groups_cleanup
    if `nproc' < 1 {
        di as error "[pte] _pte_bygroup_parallel: nproc must be >= 1"
        exit 198
    }
    if `use_inner_seed' {
        if `inner_seed' < 1 {
            di as error "[pte] _pte_bygroup_parallel: inner_seed must be >= 1 when specified"
            exit 198
        }
        if `inner_seed' > 2147483647 {
            di as error "[pte] _pte_bygroup_parallel: inner_seed exceeds maximum value (2147483647)"
            exit 198
        }
    }
    local _diag_opt ""
    if "`nodiagnose'" != "" {
        local _diag_opt "nodiagnose"
    }
    local _pte_boot_delta ""
    local _pte_boot_delta_opt ""
    capture quietly xtset
    if _rc == 0 {
        local _pte_boot_delta "`r(tdelta)'"
        if "`_pte_boot_delta'" != "" {
            local _pte_boot_delta_opt ", delta(`_pte_boot_delta')"
        }
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
            di as error "[pte] _pte_bygroup_parallel: `by' is neither numeric nor string"
            exit 111
        }
    }

    // Recompute the live group list from the caller dataset so quoted string
    // labels with embedded spaces survive the worker handoff.
    capture confirm variable `tousevar', exact
    if _rc != 0 {
        di as error "[pte] _pte_bygroup_parallel: tousevar(`tousevar') not found"
        exit 111
    }
    capture confirm numeric variable `tousevar'
    if _rc != 0 {
        di as error "[pte] _pte_bygroup_parallel: tousevar(`tousevar') must be numeric"
        exit 111
    }
    quietly levelsof `by' if `tousevar', local(groups)
    local ngroups = r(r)
    if `ngroups' < 1 {
        di as error "[pte] _pte_bygroup_parallel: no groups found in `by'"
        exit 2000
    }
    
    // Beta dimensions
    local beta_ncols = cond("`prodfunc'" == "cd", 3, 6)
    local beta_colnames "beta_l beta_k beta_t"
    if "`prodfunc'" != "cd" {
        local beta_colnames "beta_l beta_k beta_l2 beta_k2 beta_lk beta_t"
    }
    if `_pte_n_controls' > 1 {
        local beta_ncols = cond("`prodfunc'" == "cd", 2, 5) + `_pte_n_controls'
        local beta_colnames "beta_l beta_k"
        if "`prodfunc'" != "cd" {
            local beta_colnames "beta_l beta_k beta_l2 beta_k2 beta_lk"
        }
        local beta_colnames "`beta_colnames' `control'"
    }
    // Helper payload validation must require the full public grouped width.
    local beta_required_cols = `beta_ncols'
    
    // Cap workers at ngroups
    local nproc_eff = min(`nproc', `ngroups')
    
    // Keep grouped parallel launch aligned with the other bootstrap helper on
    // macOS app-bundle installs, where parallel's legacy auto-probe can miss
    // the actual StataMP executable path.
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

    // Set parallel clusters
    if "`_pte_parallel_statapath'" != "" {
        parallel setclusters `nproc_eff', force statapath(`_pte_parallel_statapath')
    }
    else {
        parallel setclusters `nproc_eff', force
    }
    
    // Allocate industries to workers (round-robin)
    // Worker w gets industries: w, w+nproc, w+2*nproc, ...
    // Save a stable worker snapshot. The wrapper passes a marksample tempvar,
    // which is not a safe cross-process contract for child Stata sessions.
    // Materialize an explicit bridge variable inside the snapshot only, while
    // leaving the caller dataset unchanged.
    tempfile _pte_master_data_stub
    local _pte_par_data "`_pte_master_data_stub'_master.dta"
    local _pte_master_touse "_pte_bg_touse_bridge"
    local _pte_snapshot_vars "`by' `treatment' `depvar' `free' `state' `proxy' `id' `time' `control' `_pte_master_touse'"
    local _pte_snapshot_vars : list uniq _pte_snapshot_vars
    preserve
        capture drop `_pte_master_touse'
        quietly gen byte `_pte_master_touse' = (`tousevar' != 0 & !missing(`tousevar'))
        if "`tousevar'" != "`_pte_master_touse'" {
            capture drop `tousevar'
        }
        // Worker snapshots must carry only the public grouped-bootstrap input
        // contract. Leaked tempvars from prior helper calls can collide with
        // egen/xtset scratch names in fresh child Stata sessions and abort the
        // bootstrap before any payload is produced.
        quietly keep `_pte_snapshot_vars'
        quietly xtset `id' `time'`_pte_boot_delta_opt'
        quietly save "`_pte_par_data'", replace
    restore

    local _pte_repo_root ""
    capture findfile _pte_bygroup_parallel.ado
    if _rc == 0 {
        local _pte_repo_root `"`r(fn)'"'
        local _pte_repo_root : subinstr local _pte_repo_root ///
            "/ado/_pte_bygroup_parallel.ado" "", all
    }
    
    // Allocate industries to workers (round-robin)
    // Worker w gets industries: w, w+nproc, w+2*nproc, ...
    local tmpdir = c(tmpdir)
    tempfile _pte_result_prefix_stub
    capture confirm number ${PTE_PAR_RUNSEQ}
    if _rc != 0 {
        global PTE_PAR_RUNSEQ 0
    }
    global PTE_PAR_RUNSEQ = ${PTE_PAR_RUNSEQ} + 1
    local result_prefix "`_pte_result_prefix_stub'_run${PTE_PAR_RUNSEQ}_"
    global PTE_PAR_MASTER_DATA "`_pte_par_data'"
    global PTE_PAR_RESULTBASE "`result_prefix'"
    global PTE_PAR_TOUSEVAR "`_pte_master_touse'"
    global PTE_PAR_PANELVAR "`id'"
    global PTE_PAR_TIMEVAR "`time'"
    global PTE_PAR_XTDELTA "`_pte_boot_delta'"
    global PTE_PAR_RUNSEQ "${PTE_PAR_RUNSEQ}"
    // Fresh-run contract: collector inputs must be produced by the current
    // parallel invocation, not inherited from an earlier aborted run.
    forvalues w = 1/`nproc_eff' {
        capture erase "`result_prefix'`w'.dta"
    }
    
    if "`nolog'" == "" {
        di as text "[pte] Parallel bygroup bootstrap: `nproc_eff' workers, " ///
            "`ngroups' groups, `nboot' iterations each"
    }
    
    // ================================================================
    // Generate worker do-file
    // ================================================================
    
    // Build option string for _pte_prodfunc, _pte_omega, _pte_att
    local _pf_base "treatment(`treatment') id(_BSFIRM_) time(`time')"
    local _pf_base "`_pf_base' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
    local _pf_base "`_pf_base' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
    if "`control'" != "" {
        local _pf_base "`_pf_base' control(`control')"
    }
    local _pf_base "`_pf_base' noreport"
    if "`_diag_opt'" != "" {
        local _pf_base "`_pf_base' `_diag_opt'"
    }
    
    local _om_base "treatment(`treatment') omegapoly(`omegapoly')"
    local _om_base "`_om_base' eps0window(`eps0window')"
    if "`prodfunc'" == "translog" {
        local _om_base "`_om_base' prodfunc(translog)"
    }
    if "`notrimeps'" != "" {
        local _om_base "`_om_base' notrimeps"
    }
    if "`_diag_opt'" != "" {
        local _om_base "`_om_base' `_diag_opt'"
    }
    
    local _att_base "treatment(`treatment') omegapoly(`omegapoly')"
    local _att_base "`_att_base' attperiods(`attperiods') nsim(`nsim')"
    if "`_diag_opt'" != "" {
        local _att_base "`_att_base' `_diag_opt'"
    }
    local _att_base "`_att_base' nostabilitycheck"
    if "`notrimeps'" != "" {
        local _att_base "`_att_base' notrimeps"
    }
    
    tempfile _pte_worker_dofile_stub
    local _pte_worker_dofile "`_pte_worker_dofile_stub'_worker.do"
    tempname fh
    file open `fh' using "`_pte_worker_dofile'", write replace
    global PTE_PAR_WORKER_DOFILE "`_pte_worker_dofile'"
    
    // Worker preamble
    file write `fh' "// PTE Bygroup Bootstrap Worker" _n
    file write `fh' "// Auto-generated by _pte_bygroup_parallel" _n
    file write `fh' "" _n
    if `"`_pte_repo_root'"' != "" {
        file write `fh' `"adopath + "`_pte_repo_root'/ado""' _n
        file write `fh' `"adopath + "`_pte_repo_root'""' _n
        file write `fh' "" _n
    }
    file write `fh' `"local worker_id = \$pll_instance"' _n
    file write `fh' `"local nproc_eff = `nproc_eff'"' _n
    file write `fh' `"local ngroups = `ngroups'"' _n
    file write `fh' `"local nboot = `nboot'"' _n
    file write `fh' `"local ncols = `ncols'"' _n
    file write `fh' `"local do_trim = `do_trim'"' _n
    file write `fh' `"local beta_ncols = `beta_ncols'"' _n
    file write `fh' `"local group_seed = `group_seed'"' _n
    file write `fh' `"local tousevar "`_pte_master_touse'""' _n
    file write `fh' `"local _pte_byvar_type "`_pte_byvar_type'""' _n
    file write `fh' `"local _pte_groups `"`groups'"'"' _n
    file write `fh' `"local ttprefix "`ttprefix'""' _n
    file write `fh' `"local tt_runid "`runid'""' _n
    file write `fh' `"local use_inner_seed = `=`use_inner_seed''"' _n
    if `use_inner_seed' {
        file write `fh' `"local inner_seed_val = `inner_seed'"' _n
    }
    file write `fh' "" _n
    
    // Worker: determine assigned groups (round-robin)
    file write `fh' `"// Determine assigned groups for this worker"' _n
    file write `fh' `"local my_gidx """' _n
    file write `fh' `"local g_idx = 0"' _n
    
    // Store assigned group indices; the worker recovers the exact group label
    // from the quoted _pte_groups list to avoid splitting string values with
    // embedded spaces.
    foreach grp of local groups {
        file write `fh' `"local ++g_idx"' _n
        file write `fh' `"if mod(\`g_idx' - 1, \`nproc_eff') + 1 == \`worker_id' {"' _n
        file write `fh' `"    local my_gidx "\`my_gidx' \`g_idx'""' _n
        file write `fh' `"}"' _n
    }
    file write `fh' "" _n
    
    // Worker: set bootstrap flag
    file write `fh' `"scalar _pte_in_bootstrap = 1"' _n
    file write `fh' "" _n
    
    // Worker: main loop over assigned groups
    file write `fh' `"foreach g_idx of local my_gidx {"' _n
    file write `fh' `"    local grp : word \`g_idx' of \`_pte_groups'"' _n
    file write `fh' "" _n
    
    // Initialize per-group matrices
    file write `fh' `"    matrix _ATT_G\`g_idx' = J(\`nboot', \`ncols', .)"' _n
    file write `fh' `"    if \`do_trim' {"' _n
    file write `fh' `"        matrix _ATT_TRIM_G\`g_idx' = J(\`nboot', \`ncols', .)"' _n
    file write `fh' `"    }"' _n
    file write `fh' `"    matrix _BETA_G\`g_idx' = J(\`nboot', \`beta_ncols', .)"' _n
    file write `fh' `"    local grp_success = 0"' _n
    file write `fh' `"    local grp_fail = 0"' _n
    file write `fh' "" _n
    
    // Set group seed ONCE
    file write `fh' `"    set seed \`group_seed'"' _n
    file write `fh' "" _n
    
    // Bootstrap inner loop
    file write `fh' `"    forvalues b = 1/\`nboot' {"' _n
    file write `fh' "" _n
    file write `fh' `"        quietly use "`_pte_par_data'", clear"' _n
    file write `fh' `"        if "\`_pte_byvar_type'" == "numeric" {"' _n
    file write `fh' `"            quietly keep if `by' == \`grp' & \`tousevar'"' _n
    file write `fh' `"        }"' _n
    file write `fh' `"        else {"' _n
    file write `fh' `"            quietly keep if `by' == "\`grp'" & \`tousevar'"' _n
    file write `fh' `"        }"' _n
    file write `fh' "" _n
    file write `fh' `"        quietly count"' _n
    file write `fh' `"        if r(N) < 10 {"' _n
    file write `fh' `"            local ++grp_fail"' _n
    file write `fh' `"            continue"' _n
    file write `fh' `"        }"' _n
    file write `fh' "" _n
    
    // Stratified cluster resampling
    file write `fh' `"        capture drop _pte_treat_firm"' _n
    file write `fh' `"        quietly bysort `id': egen _pte_treat_firm = max(`treatment')"' _n
    file write `fh' `"        capture drop _BSFIRM_"' _n
    file write `fh' `"        capture {"' _n
    file write `fh' `"            quietly bsample, strata(_pte_treat_firm) cluster(`id') idcluster(_BSFIRM_)"' _n
    file write `fh' `"        }"' _n
    file write `fh' `"        if _rc != 0 {"' _n
    file write `fh' `"            local ++grp_fail"' _n
    file write `fh' `"            continue"' _n
    file write `fh' `"        }"' _n
    file write `fh' `"        quietly xtset _BSFIRM_ `time'`_pte_boot_delta_opt'"' _n
    file write `fh' "" _n
    
    // Production function estimation
    file write `fh' `"        local bs_ok = 1"' _n
    file write `fh' `"        capture {"' _n
    file write `fh' `"            _pte_prodfunc, `_pf_base'"' _n
    file write `fh' `"        }"' _n
    file write `fh' `"        if _rc != 0 {"' _n
    file write `fh' `"            local bs_ok = 0"' _n
    file write `fh' `"        }"' _n
    file write `fh' "" _n
    
    // Store betas and run omega + att
    file write `fh' `"        if \`bs_ok' == 1 {"' _n
    file write `fh' `"            local bs_beta_l = _b[`free']"' _n
    file write `fh' `"            local bs_beta_k = _b[`state']"' _n
    file write `fh' `"            local bs_beta_t = ."' _n
    file write `fh' `"            local _pte_beta_payload_ctrl_ready = 1"' _n
    file write `fh' `"            capture matrix _pte_beta_ctrl = e(beta_controls)"' _n
    file write `fh' `"            if _rc == 0 {"' _n
    file write `fh' `"                local _pte_beta_ctrl_names : colnames _pte_beta_ctrl"' _n
    if `_pte_n_controls' > 1 {
        foreach _ctrl of local control {
            file write `fh' `"                local _ctrl_pos : list posof "`_ctrl'" in _pte_beta_ctrl_names"' _n
            file write `fh' `"                if \`_ctrl_pos' < 1 {"' _n
            file write `fh' `"                    local _pte_beta_payload_ctrl_ready = 0"' _n
            file write `fh' `"                }"' _n
        }
    }
    else if "`control'" != "" {
        local _only_ctrl : word 1 of `control'
        file write `fh' `"                local _ctrl_pos : list posof "`_only_ctrl'" in _pte_beta_ctrl_names"' _n
        file write `fh' `"                if \`_ctrl_pos' < 1 {"' _n
        file write `fh' `"                    local _pte_beta_payload_ctrl_ready = 0"' _n
        file write `fh' `"                }"' _n
        file write `fh' `"                else {"' _n
        file write `fh' `"                    local bs_beta_t = _pte_beta_ctrl[1, \`_ctrl_pos']"' _n
        file write `fh' `"                }"' _n
    }
    else {
        file write `fh' `"                if colsof(_pte_beta_ctrl) >= 1 {"' _n
        file write `fh' `"                    local bs_beta_t = _pte_beta_ctrl[1, 1]"' _n
        file write `fh' `"                }"' _n
    }
    file write `fh' `"            }"' _n
    file write `fh' `"            else {"' _n
    file write `fh' `"                capture local bs_beta_t = _b[t]"' _n
    if `_pte_n_controls' > 1 {
        file write `fh' `"                local _pte_beta_payload_ctrl_ready = 0"' _n
    }
    file write `fh' `"            }"' _n
    file write `fh' `"            matrix _BETA_G\`g_idx'[\`b', 1] = \`bs_beta_l'"' _n
    file write `fh' `"            matrix _BETA_G\`g_idx'[\`b', 2] = \`bs_beta_k'"' _n
    if `_pte_n_controls' > 1 {
        file write `fh' `"            if \`_pte_beta_payload_ctrl_ready' == 0 {"' _n
        file write `fh' `"                local bs_ok = 0"' _n
        file write `fh' `"            }"' _n
    }
    else {
        file write `fh' `"            if missing(\`bs_beta_t') {"' _n
        file write `fh' `"                local bs_ok = 0"' _n
        file write `fh' `"            }"' _n
    }

    if "`prodfunc'" == "cd" {
        if `_pte_n_controls' > 1 {
            foreach _ctrl of local control {
                local _ctrl_j = `: list posof "`_ctrl'" in control'
                file write `fh' `"            local _ctrl_pos : list posof "`_ctrl'" in _pte_beta_ctrl_names"' _n
                file write `fh' `"            matrix _BETA_G\`g_idx'[\`b', `=2 + `_ctrl_j''] = _pte_beta_ctrl[1, \`_ctrl_pos']"' _n
            }
        }
        else {
            file write `fh' `"            if !missing(\`bs_beta_t') {"' _n
            file write `fh' `"                matrix _BETA_G\`g_idx'[\`b', 3] = \`bs_beta_t'"' _n
            file write `fh' `"            }"' _n
        }
    }
    else {
        file write `fh' `"            local bs_beta_ll = _b[l2]"' _n
        file write `fh' `"            local bs_beta_kk = _b[k2]"' _n
        file write `fh' `"            local bs_beta_lk = _b[l1k1]"' _n
        file write `fh' `"            matrix _BETA_G\`g_idx'[\`b', 3] = \`bs_beta_ll'"' _n
        file write `fh' `"            matrix _BETA_G\`g_idx'[\`b', 4] = \`bs_beta_kk'"' _n
        file write `fh' `"            matrix _BETA_G\`g_idx'[\`b', 5] = \`bs_beta_lk'"' _n
        if `_pte_n_controls' > 1 {
            foreach _ctrl of local control {
                local _ctrl_j = `: list posof "`_ctrl'" in control'
                file write `fh' `"            local _ctrl_pos : list posof "`_ctrl'" in _pte_beta_ctrl_names"' _n
                file write `fh' `"            matrix _BETA_G\`g_idx'[\`b', `=5 + `_ctrl_j''] = _pte_beta_ctrl[1, \`_ctrl_pos']"' _n
            }
        }
        else {
            file write `fh' `"            if !missing(\`bs_beta_t') {"' _n
            file write `fh' `"                matrix _BETA_G\`g_idx'[\`b', 6] = \`bs_beta_t'"' _n
            file write `fh' `"            }"' _n
        }
    }
    file write `fh' "" _n
    
    // Omega estimation
    file write `fh' `"            local _om_opts "`_om_base'""' _n
    file write `fh' `"            local _om_opts "\`_om_opts' beta_l(\`bs_beta_l') beta_k(\`bs_beta_k')""' _n
    if "`prodfunc'" == "translog" {
        file write `fh' `"            local _om_opts "\`_om_opts' beta_ll(\`bs_beta_ll') beta_kk(\`bs_beta_kk') beta_lk(\`bs_beta_lk')""' _n
    }
    file write `fh' `"            capture {"' _n
    file write `fh' `"                _pte_omega, \`_om_opts'"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"            if _rc != 0 {"' _n
    file write `fh' `"                local bs_ok = 0"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"        }"' _n
    file write `fh' "" _n
    
    // ATT estimation
    file write `fh' `"        if \`bs_ok' == 1 {"' _n
    file write `fh' `"            local _att_opts "`_att_base'""' _n
    if `use_inner_seed' {
        file write `fh' `"            local _att_opts "\`_att_opts' seed(`inner_seed')""' _n
    }
    else {
        file write `fh' `"            local _att_opts "\`_att_opts' preserverng""' _n
    }
    file write `fh' `"            capture {"' _n
    file write `fh' `"                _pte_att, \`_att_opts'"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"            if _rc != 0 {"' _n
    file write `fh' `"                local bs_ok = 0"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"        }"' _n
    file write `fh' "" _n
    
    // Store results
    file write `fh' `"        if \`bs_ok' == 1 {"' _n
    // Raw track follows the official industry DO order:
    // ATT0 ATT1 ... ATT, with overall ATT in the final column.
    file write `fh' `"            forvalues s = 0/`attperiods' {"' _n
    file write `fh' `"                local col = \`s' + 1"' _n
    file write `fh' `"                capture local _tmp = e(att_raw_\`s')"' _n
    file write `fh' `"                if _rc == 0 & !missing(\`_tmp') {"' _n
    file write `fh' `"                    matrix _ATT_G\`g_idx'[\`b', \`col'] = \`_tmp'"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"            matrix _ATT_G\`g_idx'[\`b', \`ncols'] = e(ATT_avg_raw)"' _n
    // Trim track ATT
    file write `fh' `"            if \`do_trim' {"' _n
    file write `fh' `"                forvalues s = 0/`attperiods' {"' _n
    file write `fh' `"                    local col = \`s' + 1"' _n
    file write `fh' `"                    capture local _tmp_t = e(att_trim_\`s')"' _n
    file write `fh' `"                    if _rc == 0 & !missing(\`_tmp_t') {"' _n
    file write `fh' `"                        matrix _ATT_TRIM_G\`g_idx'[\`b', \`col'] = \`_tmp_t'"' _n
    file write `fh' `"                    }"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"                capture local _tmp_t = e(ATT_avg_trim)"' _n
    file write `fh' `"                if _rc == 0 & !missing(\`_tmp_t') {"' _n
    file write `fh' `"                    matrix _ATT_TRIM_G\`g_idx'[\`b', \`ncols'] = \`_tmp_t'"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"            }"' _n
    // Save TT data for cross-group aggregation only when the full public
    // payload contract is complete. Otherwise fail closed and leave no
    // sidecar artifact that could contaminate pooled ATT aggregation.
    file write `fh' `"            local _pte_payload_ok = 1"' _n
    file write `fh' `"            if missing(_ATT_G\`g_idx'[\`b', 1]) | missing(_ATT_G\`g_idx'[\`b', \`ncols']) {"' _n
    file write `fh' `"                local _pte_payload_ok = 0"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"            if \`do_trim' {"' _n
    file write `fh' `"                if missing(_ATT_TRIM_G\`g_idx'[\`b', 1]) | missing(_ATT_TRIM_G\`g_idx'[\`b', \`ncols']) {"' _n
    file write `fh' `"                    local _pte_payload_ok = 0"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"            forvalues j = 1/\`beta_ncols' {"' _n
    file write `fh' `"                local _pte_beta_req = _BETA_G\`g_idx'[\`b', \`j']"' _n
    file write `fh' `"                if missing(\`_pte_beta_req') {"' _n
    file write `fh' `"                    local _pte_payload_ok = 0"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"            if \`_pte_payload_ok' {"' _n
    file write `fh' `"                capture {"' _n
    file write `fh' `"                    capture drop _pte_firm_bs"' _n
    file write `fh' `"                    quietly gen long _pte_firm_bs = _BSFIRM_"' _n
    file write `fh' `"                    local _pte_tt_keep "_pte_firm_bs `time' _pte_nt _pte_tt_raw _pte_tt""' _n
    file write `fh' `"                    capture confirm variable _pte_tt_trim"' _n
    file write `fh' `"                    if _rc == 0 {"' _n
    file write `fh' `"                        local _pte_tt_keep "\`_pte_tt_keep' _pte_tt_trim""' _n
    file write `fh' `"                    }"' _n
    file write `fh' `"                    quietly keep \`_pte_tt_keep'"' _n
    file write `fh' `"                    capture drop _pte_tt_runid"' _n
    file write `fh' `"                    quietly gen str244 _pte_tt_runid = "\`tt_runid'""' _n
    file write `fh' `"                    quietly save "`tmpdir'/\`ttprefix'\`g_idx'_b\`b'.dta", replace"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"                if _rc == 0 {"' _n
    file write `fh' `"                    local ++grp_success"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"                else {"' _n
    file write `fh' `"                    local ++grp_fail"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"            else {"' _n
    file write `fh' `"                local ++grp_fail"' _n
    file write `fh' `"            }"' _n
    file write `fh' `"        }"' _n
    file write `fh' `"        else {"' _n
    file write `fh' `"            local ++grp_fail"' _n
    file write `fh' `"        }"' _n
    
    // End bootstrap inner loop
    file write `fh' `"    }"' _n
    file write `fh' "" _n

    // End group loop
    file write `fh' `"}"' _n
    file write `fh' "" _n
    
    // ================================================================
    // Worker: save results to worker-specific file
    // Convert per-group matrices to a dataset for file-based passing
    // ================================================================
    file write `fh' `"// Save results to worker-specific file"' _n
    file write `fh' `"clear"' _n
    file write `fh' "" _n
    
    // Count total rows needed: ngroups_assigned * nboot
    file write `fh' `"local n_assigned : word count \`my_gidx'"' _n
    file write `fh' `"local total_rows = \`n_assigned' * \`nboot'"' _n
    file write `fh' `"if \`total_rows' > 0 {"' _n
    file write `fh' `"    quietly set obs \`total_rows'"' _n
    file write `fh' "" _n
    
    // Generate structure variables
    file write `fh' `"    quietly gen int _pte_g_idx = ."' _n
    file write `fh' `"    quietly gen int _pte_b = ."' _n
    file write `fh' `"    quietly gen int _pte_worker = \`worker_id'"' _n
    file write `fh' `"    quietly gen str244 _pte_result_runid = "\`tt_runid'""' _n
    file write `fh' "" _n
    
    // Generate ATT columns (raw track)
    file write `fh' `"    forvalues j = 1/\`ncols' {"' _n
    file write `fh' `"        quietly gen double _pte_att_\`j' = ."' _n
    file write `fh' `"    }"' _n
    
    // Generate ATT columns (trim track)
    file write `fh' `"    if \`do_trim' {"' _n
    file write `fh' `"        forvalues j = 1/\`ncols' {"' _n
    file write `fh' `"            quietly gen double _pte_att_trim_\`j' = ."' _n
    file write `fh' `"        }"' _n
    file write `fh' `"    }"' _n
    
    // Generate BETA columns
    file write `fh' `"    forvalues j = 1/\`beta_ncols' {"' _n
    file write `fh' `"        quietly gen double _pte_beta_\`j' = ."' _n
    file write `fh' `"    }"' _n
    file write `fh' "" _n
    
    // Fill dataset from per-group matrices
    file write `fh' `"    local row = 0"' _n
    file write `fh' `"    local gi2 = 0"' _n
    file write `fh' `"    foreach g_idx2 of local my_gidx {"' _n
    file write `fh' `"        local ++gi2"' _n
    file write `fh' `"        forvalues b = 1/\`nboot' {"' _n
    file write `fh' `"            local ++row"' _n
    file write `fh' `"            quietly replace _pte_g_idx = \`g_idx2' in \`row'"' _n
    file write `fh' `"            quietly replace _pte_b = \`b' in \`row'"' _n
    file write `fh' "" _n
    
    // Fill ATT raw columns
    file write `fh' `"            forvalues j = 1/\`ncols' {"' _n
    file write `fh' `"                local val = _ATT_G\`g_idx2'[\`b', \`j']"' _n
    file write `fh' `"                if !missing(\`val') {"' _n
    file write `fh' `"                    quietly replace _pte_att_\`j' = \`val' in \`row'"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"            }"' _n
    
    // Fill ATT trim columns
    file write `fh' `"            if \`do_trim' {"' _n
    file write `fh' `"                forvalues j = 1/\`ncols' {"' _n
    file write `fh' `"                    capture local val = _ATT_TRIM_G\`g_idx2'[\`b', \`j']"' _n
    file write `fh' `"                    if _rc == 0 & !missing(\`val') {"' _n
    file write `fh' `"                        quietly replace _pte_att_trim_\`j' = \`val' in \`row'"' _n
    file write `fh' `"                    }"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"            }"' _n
    
    // Fill BETA columns
    file write `fh' `"            forvalues j = 1/\`beta_ncols' {"' _n
    file write `fh' `"                local val = _BETA_G\`g_idx2'[\`b', \`j']"' _n
    file write `fh' `"                if !missing(\`val') {"' _n
    file write `fh' `"                    quietly replace _pte_beta_\`j' = \`val' in \`row'"' _n
    file write `fh' `"                }"' _n
    file write `fh' `"            }"' _n
    
    file write `fh' `"        }"' _n
    file write `fh' `"    }"' _n
    file write `fh' "" _n
    
    // Save worker result file
    file write `fh' `"    quietly save "`result_prefix'\`worker_id'.dta", replace"' _n
    file write `fh' `"}"' _n
    file write `fh' "" _n
    
    // Clean up bootstrap flag
    file write `fh' `"capture scalar drop _pte_in_bootstrap"' _n
    
    file close `fh'
    
    // ================================================================
    // Execute parallel do
    // ================================================================
    
    if "`nolog'" == "" {
        di as text "[pte] Launching parallel do with `nproc_eff' workers..."
    }
    
    // parallel exports loaded program definitions, not bare ado names that
    // only exist on disk. Fresh sessions therefore need an explicit preload
    // step so grouped workers can reproduce the serial/002/003 chain.
    local _pte_worker_programs "_pte_prodfunc _pte_omega _pte_att"
    foreach prog of local _pte_worker_programs {
        capture program list `prog'
        if _rc == 0 {
            continue
        }
        capture findfile `prog'.ado
        if _rc != 0 {
            di as error "[pte] Error: worker helper `prog'.ado not found on adopath"
            exit 111
        }
        local _pte_progfile `"`r(fn)'"'
        quietly do `"`_pte_progfile'"'
        capture program list `prog'
        if _rc != 0 {
            di as error "[pte] Error: failed to preload worker helper `prog'"
            exit 111
        }
    }

    // Set bootstrap flag
    scalar _pte_in_bootstrap = 1
    
    capture noisily {
        parallel do "`_pte_worker_dofile'", ///
            nodata ///
            programs(`_pte_worker_programs') ///
            mata ///
            noglobal
    }
    local pll_rc = _rc
    local _pte_parallel_do_rc = `pll_rc'
    
    // Clear bootstrap flag
    capture scalar drop _pte_in_bootstrap
    
    if `pll_rc' != 0 {
        di as text "[pte] Warning: parallel do returned rc=`pll_rc'; checking current-run worker payload before falling back"
        capture parallel seelog
    }
    
    // ================================================================
    // Collect results from worker files
    // ================================================================
    
    if "`nolog'" == "" {
        di as text "[pte] Collecting results from `nproc_eff' workers..."
    }
    
    // Append all worker result files
    local first_loaded = 0
    local found_workers = 0
    forvalues w = 1/`nproc_eff' {
        local wfile "`result_prefix'`w'.dta"
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
            capture erase "`wfile'"
        }
        else {
            if "`nolog'" == "" {
                di as text "[pte] Warning: worker `w' result file not found"
            }
        }
    }

    if `first_loaded' == 1 & `_pte_parallel_do_rc' != 0 & `found_workers' == `nproc_eff' {
        if "`nolog'" == "" {
            di as text "[pte] Recovered complete worker result files despite parallel rc=`_pte_parallel_do_rc'; validating payload contract"
        }
    }
    else if `_pte_parallel_do_rc' != 0 {
        di as text "[pte] Warning: grouped parallel helper could not recover a complete current-run worker file set after rc=`_pte_parallel_do_rc'"
        capture parallel clean, force
        forvalues w = 1/`nproc_eff' {
            capture erase "`result_prefix'`w'.dta"
        }
        quietly use "`_pte_par_data'", clear
        capture noisily _pte_parallel_groups_cleanup
        return scalar n_success = 0
        return scalar n_fail = `=`ngroups' * `nboot''
        return scalar nproc_eff = `nproc_eff'
        exit `_pte_parallel_do_rc'
    }
    
    if `first_loaded' == 0 {
        di as text "[pte] Warning: no worker result files found; grouped bootstrap will fall back to serial"
        capture parallel clean, force
        forvalues w = 1/`nproc_eff' {
            capture erase "`result_prefix'`w'.dta"
        }
        quietly use "`_pte_par_data'", clear
        capture noisily _pte_parallel_groups_cleanup
        return scalar n_success = 0
        return scalar n_fail = `=`ngroups' * `nboot''
        return scalar nproc_eff = `nproc_eff'
        exit 2000
    }

    // A grouped bootstrap draw is identified by the Cartesian pair
    // (group index, bootstrap iteration). Corrupted worker payloads with
    // out-of-range indices or duplicate identities must fail closed; letting
    // them count as successes silently breaks the draw-to-matrix contract.
    foreach _pte_idx_var in _pte_g_idx _pte_b {
        capture confirm numeric variable `_pte_idx_var'
        if _rc != 0 {
            di as error "[pte] Error: worker results missing required identity columns"
            capture parallel clean, force
            forvalues w = 1/`nproc_eff' {
                capture erase "`result_prefix'`w'.dta"
            }
            quietly use "`_pte_par_data'", clear
            capture noisily _pte_parallel_groups_cleanup
            return clear
            exit 2000
        }
    }
    capture confirm string variable _pte_result_runid
    if _rc != 0 {
        di as error "[pte] Error: worker results missing current-run provenance metadata"
        capture parallel clean, force
        forvalues w = 1/`nproc_eff' {
            capture erase "`result_prefix'`w'.dta"
        }
        quietly use "`_pte_par_data'", clear
        capture noisily _pte_parallel_groups_cleanup
        return clear
        exit 2000
    }
    quietly count if _pte_result_runid != "`runid'"
    if r(N) > 0 {
        di as error "[pte] Error: worker results belong to a different grouped-bootstrap run"
        capture parallel clean, force
        forvalues w = 1/`nproc_eff' {
            capture erase "`result_prefix'`w'.dta"
        }
        quietly use "`_pte_par_data'", clear
        capture noisily _pte_parallel_groups_cleanup
        return clear
        exit 2000
    }

    tempvar _pte_invalid_g _pte_invalid_b _pte_dup_pair
    quietly gen byte `_pte_invalid_g' = missing(_pte_g_idx) | _pte_g_idx < 1 | _pte_g_idx > `ngroups'
    quietly count if `_pte_invalid_g'
    if r(N) > 0 {
        di as error "[pte] Error: worker results contain out-of-range group identities"
        capture parallel clean, force
        forvalues w = 1/`nproc_eff' {
            capture erase "`result_prefix'`w'.dta"
        }
        quietly use "`_pte_par_data'", clear
        capture noisily _pte_parallel_groups_cleanup
        return clear
        exit 2000
    }

    quietly gen byte `_pte_invalid_b' = missing(_pte_b) | _pte_b < 1 | _pte_b > `nboot'
    quietly count if `_pte_invalid_b'
    if r(N) > 0 {
        di as error "[pte] Error: worker results contain out-of-range bootstrap iteration ids"
        capture parallel clean, force
        forvalues w = 1/`nproc_eff' {
            capture erase "`result_prefix'`w'.dta"
        }
        quietly use "`_pte_par_data'", clear
        capture noisily _pte_parallel_groups_cleanup
        return clear
        exit 2000
    }

    quietly bysort _pte_g_idx _pte_b: gen byte `_pte_dup_pair' = (_N > 1)
    quietly count if `_pte_dup_pair'
    if r(N) > 0 {
        di as error "[pte] Error: worker results contain duplicate (group, bootstrap) identities"
        capture parallel clean, force
        forvalues w = 1/`nproc_eff' {
            capture erase "`result_prefix'`w'.dta"
        }
        quietly use "`_pte_par_data'", clear
        capture noisily _pte_parallel_groups_cleanup
        return clear
        exit 2000
    }

    local _pte_required_schema ""
    forvalues j = 1/`ncols' {
        local _pte_required_schema "`_pte_required_schema' _pte_att_`j'"
    }
    forvalues j = 1/`beta_ncols' {
        local _pte_required_schema "`_pte_required_schema' _pte_beta_`j'"
    }
    if `do_trim' {
        forvalues j = 1/`ncols' {
            local _pte_required_schema "`_pte_required_schema' _pte_att_trim_`j'"
        }
    }
    foreach _pte_schema_var of local _pte_required_schema {
        capture confirm numeric variable `_pte_schema_var'
        if _rc != 0 {
            di as error "[pte] Error: worker results missing required grouped bootstrap payload columns"
            capture parallel clean, force
            forvalues w = 1/`nproc_eff' {
                capture erase "`result_prefix'`w'.dta"
            }
            quietly use "`_pte_par_data'", clear
            capture noisily _pte_parallel_groups_cleanup
            return clear
            exit 2000
        }
    }
    
    // ================================================================
    // Reconstruct per-group matrices from collected dataset
    // ================================================================
    
    // Initialize return matrices for each group
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        tempname att_g`g_idx' att_trim_g`g_idx' beta_g`g_idx'
        matrix `att_g`g_idx'' = J(`nboot', `ncols', .)
        if `do_trim' {
            matrix `att_trim_g`g_idx'' = J(`nboot', `ncols', .)
        }
        matrix `beta_g`g_idx'' = J(`nboot', `beta_ncols', .)
        matrix colnames `beta_g`g_idx'' = `beta_colnames'
    }
    
    // Fill matrices from the appended dataset
    local nobs = _N
    local total_success = 0
    local total_fail = 0
    
    forvalues i = 1/`nobs' {
        local g_val = _pte_g_idx[`i']
        local b_val = _pte_b[`i']
        
        // Validate indices
        if `b_val' < 1 | `b_val' > `nboot' {
            continue
        }
        
        // A successful grouped bootstrap draw must carry the public payload
        // anchors that downstream consumers rely on: contemporaneous + pooled
        // ATT, and the core production-function coefficient draw.
        local has_raw_payload = 1
        capture local _pte_att0 = _pte_att_1[`i']
        if _rc != 0 | missing(`_pte_att0') {
            local has_raw_payload = 0
        }
        capture local _pte_attall = _pte_att_`ncols'[`i']
        if _rc != 0 | missing(`_pte_attall') {
            local has_raw_payload = 0
        }

        local has_trim_payload = 1
        if `do_trim' {
            capture local _pte_trim0 = _pte_att_trim_1[`i']
            if _rc != 0 | missing(`_pte_trim0') {
                local has_trim_payload = 0
            }
            capture local _pte_trimall = _pte_att_trim_`ncols'[`i']
            if _rc != 0 | missing(`_pte_trimall') {
                local has_trim_payload = 0
            }
        }

        local has_beta_payload = 1
        forvalues j = 1/`beta_required_cols' {
            capture local _pte_beta_req = _pte_beta_`j'[`i']
            if _rc != 0 | missing(`_pte_beta_req') {
                local has_beta_payload = 0
            }
        }
        
        if `has_raw_payload' == 1 & `has_trim_payload' == 1 & `has_beta_payload' == 1 {
            local ++total_success
            
            // Fill ATT raw
            forvalues j = 1/`ncols' {
                capture {
                    local val = _pte_att_`j'[`i']
                    if !missing(`val') {
                        matrix `att_g`g_val''[`b_val', `j'] = `val'
                    }
                }
            }
            
            // Fill ATT trim
            if `do_trim' {
                forvalues j = 1/`ncols' {
                    capture {
                        local val = _pte_att_trim_`j'[`i']
                        if !missing(`val') {
                            matrix `att_trim_g`g_val''[`b_val', `j'] = `val'
                        }
                    }
                }
            }
            
            // Fill BETA
            forvalues j = 1/`beta_ncols' {
                capture {
                    local val = _pte_beta_`j'[`i']
                    if !missing(`val') {
                        matrix `beta_g`g_val''[`b_val', `j'] = `val'
                    }
                }
            }
        }
        else {
            local ++total_fail
        }
    }
    
    // ================================================================
    // Cleanup and return
    // ================================================================
    
    capture parallel clean, force
    quietly use "`_pte_par_data'", clear
    capture noisily _pte_parallel_groups_cleanup
    
    if "`nolog'" == "" {
        di as text ""
        di as text "[pte] Parallel bygroup bootstrap completed:"
        di as text "  Workers used:     " as result `nproc_eff'
        di as text "  Successful:       " as result `total_success'
        if `total_fail' > 0 {
            di as text "  Failed:           " as result `total_fail'
        }
    }
    
    // Return per-group matrices
    local g_idx = 0
    foreach grp of local groups {
        local ++g_idx
        return matrix att_g`g_idx' = `att_g`g_idx''
        if `do_trim' {
            return matrix att_trim_g`g_idx' = `att_trim_g`g_idx''
        }
        return matrix beta_g`g_idx' = `beta_g`g_idx''
    }
    
    // Return scalars
    return scalar n_success = `total_success'
    return scalar n_fail = `total_fail'
    return scalar nproc_eff = `nproc_eff'
    return scalar nboot = `nboot'
    return scalar ngroups = `ngroups'
    
    // Return TT file location info for aggregation
    // TT files are saved by workers at: tmpdir/{ttprefix}{idx}_b{b}.dta
    return local tt_tmpdir "`tmpdir'"
    return local tt_prefix "`ttprefix'"
    return local tt_runid "`runid'"
    
end
