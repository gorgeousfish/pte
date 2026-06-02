*! _pte_parallel_groups_cleanup.ado
*! Explicitly removes all PTE_PAR_* globals without affecting other macros
*! Note: Stata forbids global macro names starting with underscore

version 14.0
capture program drop _pte_parallel_groups_cleanup
program define _pte_parallel_groups_cleanup
    version 14.0

    // Cross-process grouped parallel artifacts must use stable file paths so
    // child sessions can still see them after the caller program returns.
    // Remove them explicitly here instead of relying on program-scope
    // tempfile garbage collection.
    local _pte_master_data "$PTE_PAR_MASTER_DATA"
    if `"`_pte_master_data'"' != "" {
        capture erase `"`_pte_master_data'"'
    }
    local _pte_worker_dofile "$PTE_PAR_WORKER_DOFILE"
    if `"`_pte_worker_dofile'"' != "" {
        capture erase `"`_pte_worker_dofile'"'
    }
    
    // Clean up parameter globals (explicit list, NOT wildcard)
    foreach _g in MASTER_DATA RESULTBASE BY BYVAR_TYPE DEPVAR ///
        FREE STATE PROXY TREATMENT CONTROL ///
        PFUNC POLY OMEGAPOLY EPS0WINDOW NSIM ATTPERIODS SEED NOTRIMEPS ///
        NPROC N_GROUPS GROUPS PANELVAR TIMEVAR XTDELTA TOUSEVAR ///
        WORKER_DOFILE RUNSEQ {
        capture macro drop PTE_PAR_`_g'
    }
    
    // Clean up all dynamically created per-worker task lists.
    local _pte_task_globals : all globals "PTE_PAR_TASKS_*"
    foreach _g of local _pte_task_globals {
        capture macro drop `_g'
    }
    
    // Clean up parallel package artifacts (may not be installed)
    capture parallel clean, all force
    
end
