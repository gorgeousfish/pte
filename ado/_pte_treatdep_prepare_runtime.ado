*! _pte_treatdep_prepare_runtime.ado
*! Materialize the treatdependent runtime contract before dependency checks.

version 14.0
capture program drop _pte_treatdep_prepare_runtime
program define _pte_treatdep_prepare_runtime, rclass
    version 14.0

    local seeded_facf1 0
    local seeded_facf2 0
    local seeded_facf3 0
    local seeded_opt_mata 0
    local source_loaded 0
    local source_file ""
    local source_rc .
    local warm_rc .
    local patch_file ""
    local patch_rc .
    local patch_applied 0
    local upstream_core_ready 0
    local source_loader ""
    local final_ready 0
    local final_missing ""

    quietly _pte_treatdep_contract_ready
    local contract_ready = r(ready)
    local missing_contract `"`r(missing)'"'

    if `contract_ready' == 0 {
        capture quietly findfile endopolyprodest.ado
        if _rc == 0 {
            local source_file `"`r(fn)'"'
            capture quietly findfile _pte_treatdep_source_loader.do
            if _rc == 0 {
                local source_loader `"`r(fn)'"'
            }

            capture mata: mata describe facf1()
            if _rc != 0 local seeded_facf1 1
            capture mata: mata describe facf2()
            if _rc != 0 local seeded_facf2 1
            capture mata: mata describe facf3()
            if _rc != 0 local seeded_facf3 1
            capture mata: mata describe opt_mata()
            if _rc != 0 local seeded_opt_mata 1

            if `"`source_loader'"' != "" {
                global PTE_TREATDEP_SOURCE_FILE `"`source_file'"'
                capture quietly do `"`source_loader'"'
                global PTE_TREATDEP_SOURCE_FILE
            }
            else {
                capture quietly include `"`source_file'"'
            }
            local source_rc = _rc
            if `source_rc' == 0 {
                local source_loaded 1
            }
            else {
                if `seeded_facf1' capture mata: mata drop facf1()
                if `seeded_facf2' capture mata: mata drop facf2()
                if `seeded_facf3' capture mata: mata drop facf3()
                if `seeded_opt_mata' capture mata: mata drop opt_mata()
            }

            // Some installed ado variants materialize their companion Mata
            // objects only when the command executes. include'ing the ado then
            // defining the patch is not enough for a cold session because the
            // runnable contract still lacks facf1()/facf2() until the first
            // endopolyprodest call. Warm the installed ado on a disposable
            // fixture, then apply the package patch on the materialized
            // functions.
            quietly _pte_treatdep_contract_ready
            local contract_ready = r(ready)
            local missing_contract `"`r(missing)'"'
            if `contract_ready' == 0 {
                capture quietly _pte_treatdep_warm_installed_ado
                local warm_rc = _rc
                quietly _pte_treatdep_contract_ready
                local contract_ready = r(ready)
                local missing_contract `"`r(missing)'"'
            }
        }
    }

    capture mata: mata describe facf1()
    local facf1_ready = (_rc == 0)
    capture mata: mata describe facf2()
    local facf2_ready = (_rc == 0)
    local upstream_core_ready = (`facf1_ready' & `facf2_ready')

    capture quietly findfile _pte_mata_endopoly_patch.do
    if _rc == 0 {
        local patch_file `"`r(fn)'"'
    }

    if `upstream_core_ready' {
        if `"`patch_file'"' != "" {
            capture quietly do `"`patch_file'"'
            local patch_rc = _rc
            if `patch_rc' == 0 {
                local patch_applied 1
            }
        }
    }

    quietly _pte_treatdep_contract_ready
    local final_ready = r(ready)
    local final_missing `"`r(missing)'"'
    if `final_ready' == 0 {
        // Some installed ado variants materialize facf1()/facf2() only on the
        // first executable call. Run the same consumer-family signature once
        // to load lazy runtime objects before deciding the contract is broken.
        capture quietly _pte_treatdep_warm_installed_ado
        local warm_rc = _rc
        quietly _pte_treatdep_contract_ready
        local final_ready = r(ready)
        local final_missing `"`r(missing)'"'
    }
    if `final_ready' == 0 {
        // A failed dependency-prepare cycle must not leave the patch-only
        // companion objects visible in Mata when the upstream contract never
        // materialized. Roll back the package patch before clearing any
        // placeholder symbols so callers return to a clean not-ready state.
        if `patch_applied' {
            capture mata: mata drop facf3()
            capture mata: mata drop opt_mata()
        }
        if `seeded_facf1' capture mata: mata drop facf1()
        if `seeded_facf2' capture mata: mata drop facf2()
        if `seeded_facf3' capture mata: mata drop facf3()
        if `seeded_opt_mata' capture mata: mata drop opt_mata()
        quietly _pte_treatdep_contract_ready
        local final_ready = r(ready)
        local final_missing `"`r(missing)'"'
    }
    return scalar ready = `final_ready'
    return local missing = `"`final_missing'"'
    return scalar source_loaded = `source_loaded'
    return scalar source_rc = `source_rc'
    return scalar warm_rc = `warm_rc'
    return local source_file `"`source_file'"'
    return scalar patch_ready = (`patch_rc' == 0)
    return scalar patch_rc = `patch_rc'
    return local patch_file `"`patch_file'"'
end

capture program drop _pte_treatdep_warm_installed_ado
program define _pte_treatdep_warm_installed_ado
    version 14.0

    local restore_ok 0
    local orig_rngstate `"`c(rngstate)'"'
    local restore_rng `"capture set rngstate `orig_rngstate'"'
    tempname _pte_prev_est
    local has_prev_est 0
    capture local _pte_prev_cmd = e(cmd)
    if _rc == 0 & `"`_pte_prev_cmd'"' != "" {
        capture estimates store `_pte_prev_est', copy
        if _rc == 0 {
            local has_prev_est 1
        }
    }

    capture preserve
    if _rc == 0 {
        local restore_ok 1
    }

    quietly clear
    quietly set obs 4
    quietly gen double y = 1
    quietly gen double x = 1
    quietly gen double x_tp = x
    quietly gen double k = 1
    quietly gen double k_tp = k
    quietly gen double m = 1
    quietly gen double t = _n
    quietly gen double D = cond(_n >= 3, 1, 0)

    capture quietly endopolyprodest y, ///
        free(x x_tp) state(k k_tp) proxy(m) control(t) endo(D) treat(D) ///
        method(lp) reps(2) prodpoly(3) translog valueadded acf
    local warm_rc = _rc
    `restore_rng'

    if `restore_ok' {
        restore
    }
    else {
        quietly clear
    }

    if `has_prev_est' {
        capture estimates restore `_pte_prev_est'
        capture estimates drop `_pte_prev_est'
    }
    else {
        // Warming a cold runtime is a dependency-side effect only; if the
        // caller did not enter with an active estimation result, do not leak
        // the disposable endopolyprodest e() bundle into public state.
        capture ereturn clear
        capture estimates clear
    }

    exit `warm_rc'
end
