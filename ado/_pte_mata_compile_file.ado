*! _pte_mata_compile_file.ado
*! Usage:
*! , file(filename) [clean verbose nolog]
*! Returns:
*! r(success)    - 1 if compilation succeeded, 0 otherwise
*! r(error_code) - 0 on success, Stata error code on failure
*! r(filepath)   - Full path of compiled file
*! r(source)     - Where file was found (adopath/mata/findfile)

version 14.0
capture global PTE_MATA_COMPILE_FILE `"`c(filename)'"'
capture program drop _pte_mata_compile_file
program define _pte_mata_compile_file, rclass
    version 14.0

    syntax, FILE(string) [CLEAN VERBOSE NOLOG]

    local success = 0
    local error_code = 0
    local filepath ""
    local source ""

    // ================================================================
    // Step 1: Find the .mata file
    // ================================================================
    // Reuse the audited resolver so compilation, dependency probes, and live
    // runtime repair all consume the same source-tree preference contract.
    capture quietly _pte_mata_findpath, file(`file')
    if _rc == 0 & r(found) == 1 {
        local filepath `"`r(filepath)'"'
        local source `"`r(source)'"'
    }

    // File not found
    if "`filepath'" == "" {
        if "`nolog'" == "" {
            di as error "  [FAIL] `file' not found"
        }
        return scalar success = 0
        return scalar error_code = 601
        return local filepath ""
        return local source ""
        exit
    }

    // ================================================================
    // Step 2: Compile the file
    // ================================================================
    if "`nolog'" == "" & "`verbose'" != "" {
        di as text "  [COMPILE] `file' (from `source': `filepath')"
    }

    // Keep successful compilation silent on public nolog paths; otherwise the
    // raw .mata source text leaks into estimator output. Preserve noisy
    // execution for non-nolog callers so compile failures still surface their
    // underlying diagnostics.
    if "`nolog'" != "" {
        capture quietly do "`filepath'"
    }
    else {
        capture noisily do "`filepath'"
    }
    local compile_rc = _rc

    if `compile_rc' != 0 {
        local error_code = `compile_rc'
        if "`nolog'" == "" {
            di as error "  [FAIL] `file' compilation error (rc=`compile_rc')"
        }
        return scalar success = 0
        return scalar error_code = `error_code'
        return local filepath "`filepath'"
        return local source "`source'"
        exit
    }

    // Success
    local success = 1
    if "`nolog'" == "" & "`verbose'" != "" {
        di as text "  [OK]      `file' compiled successfully"
    }

    return scalar success = `success'
    return scalar error_code = 0
    return local filepath "`filepath'"
    return local source "`source'"
end
