*! _pte_bygroup_aggregate.ado
*! Aggregates per-group TT data across all groups for a single
*! bootstrap iteration. Computes pooled ATT = mean(TT) by nt.
*! This is a standalone helper that can be called independently
*! for testing or by the parallel worker.
*! forv b = 1/$boot {
*! use tt_..._industry1_boot`b', clear
*! forv j = 2/6 { append using tt_..._industry`j'_boot`b', force }
*! tabstat omg_tt if nt>=0, by(nt) stat(mean) save
*! mat ATT_boot_all[`b', 1] = (r(Stat1),...,r(StatTotal))
*! }

version 14.0
capture program drop _pte_bygroup_aggregate
program define _pte_bygroup_aggregate, rclass
    version 14.0
    syntax, ngroups(integer) nboot(integer) ///
        attperiods(integer) ///
        tmpdir(string) ///
        [TTPREFIX(string) RUNID(string) NOTRIMeps]

    if `"`ttprefix'"' == "" {
        local ttprefix "pte_tt_g"
    }
    
    local nperiods = `attperiods' + 1
    local ncols = 1 + `nperiods'
    local do_trim = ("`notrimeps'" == "")
    local att_colnames ""
    forvalues s = 0/`attperiods' {
        local att_colnames "`att_colnames' ATT`s'"
    }
    local att_colnames "`att_colnames' ATT"
    
    // Initialize pooled bootstrap matrices
    tempname att_pool att_pool_trim
    matrix `att_pool' = J(`nboot', `ncols', .)
    matrix colnames `att_pool' = `att_colnames'
    if `do_trim' {
        matrix `att_pool_trim' = J(`nboot', `ncols', .)
        matrix colnames `att_pool_trim' = `att_colnames'
    }
    
    // Standalone use should not replace the caller's current dataset or panel
    // declaration. Snapshot the caller state before any TT-file loading, then
    // restore it after aggregation or before rethrowing a runtime error.
    local _pte_agg_rc = 0
    local _pte_has_caller_data = 0
    tempfile _pte_caller_data
    mata: st_local("_pte_has_caller_data", strofreal(st_nvar() > 0))
    if `_pte_has_caller_data' {
        quietly save `"_pte_caller_data"', replace
    }
    local _pte_had_xtset = 0
    local _pte_panelvar ""
    local _pte_timevar ""
    local _pte_delta ""
    if `_pte_has_caller_data' {
        capture quietly xtset
        if _rc == 0 {
            local _pte_had_xtset = 1
            local _pte_panelvar `"`r(panelvar)'"'
            local _pte_timevar `"`r(timevar)'"'
            local _pte_delta `"`r(tdelta)'"'
        }
    }
    capture noisily {
        // Loop over bootstrap iterations
        forvalues b = 1/`nboot' {
            
            // Append TT data from all groups for this iteration. A pooled draw is
            // valid only if every group contributes to the same bootstrap index.
            local first_loaded = 0
            local loaded_groups = 0
            local expected_runid `"`runid'"'
            local saw_runid_meta = (`"`expected_runid'"' != "")
            local saw_missing_runid = 0
            forvalues g = 1/`ngroups' {
                local ttfile "`tmpdir'/`ttprefix'`g'_b`b'.dta"
                capture confirm file "`ttfile'"
                if _rc == 0 {
                    if `first_loaded' == 0 {
                        capture quietly use "`ttfile'", clear
                        if _rc == 0 {
                            local file_ok = 1
                            capture confirm string variable _pte_tt_runid
                            if _rc == 0 {
                                quietly levelsof _pte_tt_runid, local(_pte_file_runids) clean
                                local _pte_n_runids : word count `_pte_file_runids'
                                if `_pte_n_runids' != 1 {
                                    local file_ok = 0
                                }
                                else {
                                    local file_runid : word 1 of `_pte_file_runids'
                                    if `saw_missing_runid' {
                                        local file_ok = 0
                                    }
                                    else if `"`expected_runid'"' == "" {
                                        local expected_runid `"`file_runid'"'
                                        local saw_runid_meta = 1
                                    }
                                    else if `"`file_runid'"' != `"`expected_runid'"' {
                                        local file_ok = 0
                                    }
                                }
                            }
                            else if `"`expected_runid'"' != "" {
                                local file_ok = 0
                            }
                            else {
                                if `saw_runid_meta' {
                                    local file_ok = 0
                                }
                                else {
                                    local saw_missing_runid = 1
                                }
                            }
                            if `file_ok' {
                                capture confirm numeric variable _pte_nt
                                if _rc != 0 {
                                    local file_ok = 0
                                }
                            }
                            if `file_ok' {
                                capture confirm numeric variable _pte_tt_raw
                                if _rc != 0 {
                                    local file_ok = 0
                                }
                            }
                            if `file_ok' & `do_trim' {
                                capture confirm numeric variable _pte_tt_trim
                                if _rc != 0 {
                                    local file_ok = 0
                                }
                            }
                            if `file_ok' {
                                quietly count if !missing(_pte_nt) & !missing(_pte_tt_raw)
                                if r(N) == 0 {
                                    local file_ok = 0
                                }
                            }
                            if `file_ok' & `do_trim' {
                                quietly count if !missing(_pte_nt) & !missing(_pte_tt_trim)
                                if r(N) == 0 {
                                    local file_ok = 0
                                }
                            }
                            if `file_ok' {
                                local first_loaded = 1
                                local ++loaded_groups
                            }
                        }
                    }
                    else {
                        preserve
                        capture quietly use "`ttfile'", clear
                        if _rc == 0 {
                            local file_ok = 1
                            capture confirm string variable _pte_tt_runid
                            if _rc == 0 {
                                quietly levelsof _pte_tt_runid, local(_pte_file_runids) clean
                                local _pte_n_runids : word count `_pte_file_runids'
                                if `_pte_n_runids' != 1 {
                                    local file_ok = 0
                                }
                                else {
                                    local file_runid : word 1 of `_pte_file_runids'
                                    if `saw_missing_runid' {
                                        local file_ok = 0
                                    }
                                    else if `"`expected_runid'"' == "" {
                                        local expected_runid `"`file_runid'"'
                                        local saw_runid_meta = 1
                                    }
                                    else if `"`file_runid'"' != `"`expected_runid'"' {
                                        local file_ok = 0
                                    }
                                }
                            }
                            else if `"`expected_runid'"' != "" {
                                local file_ok = 0
                            }
                            else {
                                if `saw_runid_meta' {
                                    local file_ok = 0
                                }
                                else {
                                    local saw_missing_runid = 1
                                }
                            }
                            if `file_ok' {
                                capture confirm numeric variable _pte_nt
                                if _rc != 0 {
                                    local file_ok = 0
                                }
                            }
                            if `file_ok' {
                                capture confirm numeric variable _pte_tt_raw
                                if _rc != 0 {
                                    local file_ok = 0
                                }
                            }
                            if `file_ok' & `do_trim' {
                                capture confirm numeric variable _pte_tt_trim
                                if _rc != 0 {
                                    local file_ok = 0
                                }
                            }
                            if `file_ok' {
                                quietly count if !missing(_pte_nt) & !missing(_pte_tt_raw)
                                if r(N) == 0 {
                                    local file_ok = 0
                                }
                            }
                            if `file_ok' & `do_trim' {
                                quietly count if !missing(_pte_nt) & !missing(_pte_tt_trim)
                                if r(N) == 0 {
                                    local file_ok = 0
                                }
                            }
                        }
                        else {
                            local file_ok = 0
                        }
                        restore
                        if `file_ok' {
                            capture quietly append using "`ttfile'", force
                            if _rc == 0 {
                                local ++loaded_groups
                            }
                        }
                    }
                }
            }
            
            if `first_loaded' == 0 | `loaded_groups' != `ngroups' {
                continue
            }

            // The pooled grouped-bootstrap contract is defined on means of the
            // complete TT draw set, so row order must not leak execution-mode
            // or caller noisiness differences into floating-point accumulation.
            // Canonicalize the appended draw before summarize so serial,
            // parallel, and public noisy/quiet entry points consume the same
            // ordered payload.
            capture confirm variable _pte_firm_bs
            if _rc == 0 {
                if `do_trim' {
                    quietly sort _pte_nt _pte_firm_bs _pte_tt_raw _pte_tt_trim _pte_tt
                }
                else {
                    quietly sort _pte_nt _pte_firm_bs _pte_tt_raw _pte_tt
                }
            }
            else {
                if `do_trim' {
                    quietly sort _pte_nt _pte_tt_raw _pte_tt_trim _pte_tt
                }
                else {
                    quietly sort _pte_nt _pte_tt_raw _pte_tt
                }
            }
            
            // Compute pooled ATT = mean(TT) by nt
            // _pte_att generates _pte_tt_raw (raw track) and
            // _pte_tt/_pte_tt_trim (canonical trimmed track)
            // Per-period ATT in the official industry DO order:
            // ATT0 ATT1 ... ATT, with the pooled overall ATT in the last column.
            forvalues s = 0/`attperiods' {
                local col = `s' + 1
                capture {
                    quietly summarize _pte_tt_raw if _pte_nt == `s'
                    if r(N) > 0 {
                        matrix `att_pool'[`b', `col'] = r(mean)
                    }
                }
            }
            capture {
                quietly summarize _pte_tt_raw if inrange(_pte_nt, 0, `attperiods')
                if r(N) > 0 {
                    matrix `att_pool'[`b', `ncols'] = r(mean)
                }
            }
            
            // Trim track
            if `do_trim' {
                capture confirm variable _pte_tt_trim
                if _rc == 0 {
                    forvalues s = 0/`attperiods' {
                        local col = `s' + 1
                        capture {
                            quietly summarize _pte_tt_trim if _pte_nt == `s'
                            if r(N) > 0 {
                                matrix `att_pool_trim'[`b', `col'] = r(mean)
                            }
                        }
                    }
                    capture {
                        quietly summarize _pte_tt_trim if inrange(_pte_nt, 0, `attperiods')
                        if r(N) > 0 {
                            matrix `att_pool_trim'[`b', `ncols'] = r(mean)
                        }
                    }
                }
            }
        }
    }
    local _pte_agg_rc = _rc
    if `_pte_has_caller_data' {
        quietly use `"_pte_caller_data"', clear
        if `_pte_had_xtset' {
            local _pte_restore_delta_opt ""
            if `"`_pte_delta'"' != "" {
                local _pte_restore_delta_opt `"delta(`_pte_delta')"'
            }
            quietly xtset `_pte_panelvar' `_pte_timevar', `_pte_restore_delta_opt'
        }
        else {
            capture quietly xtset, clear
        }
    }
    else {
        quietly clear
    }
    if `_pte_agg_rc' != 0 {
        exit `_pte_agg_rc'
    }
    
    // Return results
    return matrix att_pool = `att_pool'
    if `do_trim' {
        return matrix att_pool_trim = `att_pool_trim'
    }
end
