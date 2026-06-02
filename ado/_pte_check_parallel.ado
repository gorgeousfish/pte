*! _pte_check_parallel.ado
*! Detect parallel computing environment and select optimal strategy
*! for bootstrap inference.
*!
*! Detection steps:
*!   1. Stata environment: version, flavor (IC/SE/MP), MP support
*!   2. Processor count and max matsize
*!   3. Memory detection (data and total)
*!   4. parallel package: check if SSC `parallel` is installed + version
*!   5. Strategy selection with degradation logic:
*!      parallel_pkg > native_mp > serial
*!
*! Returns (rclass):
*!   r(stata_version)      - Stata version number
*!   r(stata_flavor)       - Stata flavor string (IC/SE/MP)
*!   r(is_mp)              - 1 if Stata/MP, 0 otherwise
*!   r(processors)         - number of available processors
*!   r(max_matsize)        - maximum matsize
*!   r(has_parallel)       - 1 if parallel package installed
*!   r(parallel_version)   - parallel package version string
*!   r(data_memory)        - data memory usage in MB
*!   r(total_memory)       - total memory in MB (. if unavailable)
*!   r(parallel_method)    - selected strategy: serial/parallel_pkg/native_mp
*!   r(recommended_nproc)  - recommended number of processors

version 14.0
capture program drop _pte_check_parallel
program define _pte_check_parallel, rclass
    version 14.0
    
    // Task 1-2: Program framework and syntax parsing
    syntax [, Quiet]
    local output_verbose = ("`quiet'" == "")

    // ================================================================
    // Task 4: Stata version, flavor, MP detection
    // ================================================================
    local stata_version = c(stata_version)
    local stata_flavor "`c(flavor)'"
    local is_mp = (c(MP) == 1)

    // ================================================================
    // Task 5: Processor and matsize detection
    // ================================================================
    local processors = c(processors)
    local max_matsize = c(max_matsize)

    // ================================================================
    // Task 6: Memory detection
    // ================================================================
    // Stata 18+ memory command does not return r() values
    // Use describe + _N*width for data memory, c(memory) for allocated
    local data_memory = 0
    if _N > 0 {
        quietly describe, short
        local data_memory = (_N * r(width)) / (1024^2)
    }
    
    // Total allocated memory from c(memory), in MB
    // c(memory) returns bytes of allocated data memory
    local total_memory = c(memory) / (1024^2)

    // ================================================================
    // Task 7-8: parallel package detection and version
    // ================================================================
    capture which parallel
    local has_parallel = (_rc == 0)
    
    local parallel_version ""
    if `has_parallel' {
        capture quietly parallel version
        if _rc == 0 {
            capture local parallel_version = r(pll_vers)
            if _rc != 0 {
                local parallel_version "unknown"
            }
        }
        else {
            local parallel_version "unknown"
        }
    }

    // ================================================================
    // Task 9-10: Decision logic with degradation
    // ================================================================
    // Degradation: non-MP or single processor -> serial
    if !`is_mp' | `processors' == 1 {
        local parallel_method "serial"
        local recommended_nproc 1
    }
    else if `has_parallel' {
        // parallel_pkg: MP + parallel installed + multi-processor
        local parallel_method "parallel_pkg"
        local recommended_nproc = min(`processors', 8)
    }
    else {
        // native_mp: MP + multi-processor but no parallel package
        local parallel_method "native_mp"
        local recommended_nproc = min(`processors', 4)
    }

    // ================================================================
    // Task 11: Formatted report output (respects quiet option)
    // ================================================================
    if `output_verbose' {
        di as text "{hline 60}"
        di as text "PTE Parallel Environment Detection"
        di as text "{hline 60}"
        di as text "Stata version:     " as result "`stata_version'"
        di as text "Stata flavor:      " as result "`stata_flavor'"
        di as text "MP enabled:        " as result cond(`is_mp', "Yes", "No")
        di as text "Processors:        " as result "`processors'"
        di as text "Max matsize:       " as result "`max_matsize'"
        if `has_parallel' {
            di as text "parallel pkg:      " as result "Yes (v`parallel_version')"
        }
        else {
            di as text "parallel pkg:      " as result "No"
        }
        di as text "Data memory:       " as result %9.1f `data_memory' " MB"
        di as text "Allocated memory:  " as result %9.1f `total_memory' " MB"
        di as text "{hline 60}"
        di as text "Recommended method:" as result " `parallel_method'"
        di as text "Recommended nproc: " as result "`recommended_nproc'"
        di as text "{hline 60}"
        
        // Degradation reason hints
        if "`parallel_method'" == "serial" {
            if !`is_mp' {
                di as text "Note: Serial mode selected" ///
                    " (Stata `stata_flavor' does not support parallel)"
            }
            else if `processors' == 1 {
                di as text "Note: Serial mode selected" ///
                    " (single processor detected)"
            }
        }
    }

    // ================================================================
    // Task 12: Complete return values
    // ================================================================
    return scalar stata_version = `stata_version'
    return local  stata_flavor "`stata_flavor'"
    return scalar is_mp = `is_mp'
    return scalar processors = `processors'
    return scalar max_matsize = `max_matsize'
    return scalar has_parallel = `has_parallel'
    return local  parallel_version "`parallel_version'"
    return scalar data_memory = `data_memory'
    return scalar total_memory = `total_memory'
    return local  parallel_method "`parallel_method'"
    return scalar recommended_nproc = `recommended_nproc'
end


*! Task allocation for parallel bootstrap
*! Computes worker task ranges: start_w to end_w for each worker w

capture program drop _pte_task_allocate
program define _pte_task_allocate, rclass
    version 14.0
    syntax, nboot(integer) nproc(integer)
    
    // Validate inputs
    if `nboot' < 1 {
        di as error "[pte] Error: nboot must be >= 1"
        exit 198
    }
    if `nproc' < 1 {
        di as error "[pte] Error: nproc must be >= 1"
        exit 198
    }
    
    // Cap nproc at nboot (no point having more workers than tasks)
    local nproc_eff = min(`nproc', `nboot')
    
    // Compute batch size (ceiling division)
    local batch_size = ceil(`nboot' / `nproc_eff')
    
    // Compute ranges for each worker
    // Worker w gets iterations [start_w, end_w]
    forvalues w = 1/`nproc_eff' {
        local start_`w' = (`w' - 1) * `batch_size' + 1
        local end_`w' = min(`w' * `batch_size', `nboot')
        local count_`w' = `end_`w'' - `start_`w'' + 1
    }
    
    // Return results
    return scalar nproc_eff = `nproc_eff'
    return scalar batch_size = `batch_size'
    forvalues w = 1/`nproc_eff' {
        return scalar start_`w' = `start_`w''
        return scalar end_`w' = `end_`w''
        return scalar count_`w' = `count_`w''
    }
end
