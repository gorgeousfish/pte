*! _pte_mata_findpath.ado
*! Usage:
*! , file(filename) [verbose]
*! Search order: project ado/ -> src/mata/ -> mata/ -> findfile (adopath) -> cwd
*! Returns:
*! r(found)    - 1 if file found, 0 otherwise
*! r(filepath) - Full path to file (empty if not found)
*! r(source)   - Where file was found (project_ado/src_mata/mata/adopath/cwd)

version 14.0
capture global PTE_MATA_FINDPATH_FILE `"`c(filename)'"'
capture program drop _pte_mata_findpath
program define _pte_mata_findpath, rclass
    version 14.0

    syntax , FILE(string) [VERBOSE]

    local found = 0
    local filepath ""
    local source ""

    // Derive project root from the currently loaded helper file rather than
    // re-resolving the package root along adopath. Otherwise a stale PLUS /
    // PERSONAL shadow or an unmaterialized package install can hijack the
    // source-tree root while the live repo helper is executing.
    local project_root ""
    local _caller_path `"`c(filename)'"'
    if `"`_caller_path'"' == "" {
        local _caller_path `"${PTE_MATA_FINDPATH_FILE}"'
    }
    if `"`_caller_path'"' != "" {
        if regexm(`"`_caller_path'"', "^(.*)/ado/_pte_mata_findpath\\.ado$") {
            local _pte_candidate_root `"`=regexs(1)'"'
            capture confirm file "`_pte_candidate_root'/ado/_pte_mata_findpath.ado"
            if _rc == 0 {
                local project_root "`_pte_candidate_root'"
            }
        }
    }
    if "`project_root'" == "" {
        capture quietly findfile pte.ado
        if _rc == 0 {
            local _pte_ado_path "`r(fn)'"
            if regexm(`"`_pte_ado_path'"', "^(.*)/ado/pte\\.ado$") {
                local _pte_candidate_root `"`=regexs(1)'"'
                capture confirm file "`_pte_candidate_root'/ado/_pte_mata_findpath.ado"
                if _rc == 0 {
                    local project_root "`_pte_candidate_root'"
                }
            }
        }
    }
    if "`project_root'" == "" & `"`_caller_path'"' != "" {
        local _probe_dir = reverse(substr(reverse(`"`_caller_path'"'), ///
            strpos(reverse(`"`_caller_path'"'), "/") + 1, .))
        if substr(`"`_probe_dir'"', -1, 1) == "/" {
            local _probe_dir = substr(`"`_probe_dir'"', 1, length(`"`_probe_dir'"') - 1)
        }
        forvalues _pte_up = 0/8 {
            capture confirm file "`_probe_dir'/ado/_pte_mata_findpath.ado"
            if _rc == 0 {
                local project_root "`_probe_dir'"
                continue, break
            }
            if strpos(`"`_probe_dir'"', "/") <= 1 {
                continue, break
            }
            local _probe_dir = reverse(substr(reverse(`"`_probe_dir'"'), ///
                strpos(reverse(`"`_probe_dir'"'), "/") + 1, .))
            if substr(`"`_probe_dir'"', -1, 1) == "/" {
                local _probe_dir = substr(`"`_probe_dir'"', 1, length(`"`_probe_dir'"') - 1)
            }
        }
    }
    local _ado_path `"${PTE_MATA_FINDPATH_FILE}"'
    if "`project_root'" == "" & `"`_ado_path'"' == "" {
        capture quietly findfile _pte_mata_findpath.ado
        if _rc == 0 {
            local _ado_path "`r(fn)'"
        }
    }
    if "`project_root'" == "" & `"`_ado_path'"' != "" {
        if regexm(`"`_ado_path'"', "^(.*)/ado/_pte_mata_findpath\\.ado$") {
            local project_root `"`=regexs(1)'"'
        }
    }

    // ================================================================
    // Priority 1: ado/ relative to project root
    // ----------------------------------------------------------------
    // Companion Mata sources shipped inside the active source tree must take
    // precedence over stale same-name shadows in PLUS/PERSONAL. Public worker
    // gates and runtimes share the same resolver, so certifying a foreign
    // shadow while executing local ado code would break the bundle contract.
    // ================================================================
    if `found' == 0 & "`project_root'" != "" {
        capture confirm file "`project_root'/ado/`file'"
        if _rc == 0 {
            local filepath "`project_root'/ado/`file'"
            local source "project_ado"
            local found = 1
        }
    }

    // ================================================================
    // Priority 2: src/mata/ relative to project root
    // ================================================================
    if `found' == 0 & "`project_root'" != "" {
        capture confirm file "`project_root'/src/mata/`file'"
        if _rc == 0 {
            local filepath "`project_root'/src/mata/`file'"
            local source "src_mata"
            local found = 1
        }
    }

    // ================================================================
    // Priority 3: mata/ relative to project root
    // ================================================================
    if `found' == 0 & "`project_root'" != "" {
        capture confirm file "`project_root'/mata/`file'"
        if _rc == 0 {
            local filepath "`project_root'/mata/`file'"
            local source "mata"
            local found = 1
        }
    }

    // ================================================================
    // Priority 4: findfile along adopath (general fallback)
    // ----------------------------------------------------------------
    // This keeps installed-package use working while respecting the caller's
    // actual adopath order once source-tree companions are absent.
    // ================================================================
    if `found' == 0 {
        capture quietly findfile `file'
        if _rc == 0 {
            local filepath "`r(fn)'"
            local source "adopath"
            local found = 1
        }
    }

    // ================================================================
    // Priority 5: cwd-relative fallback (mata/ and src/mata/)
    // ================================================================
    if `found' == 0 {
        foreach dir in mata src/mata {
            capture confirm file "`dir'/`file'"
            if _rc == 0 {
                local filepath "`dir'/`file'"
                local source "cwd"
                local found = 1
                continue, break
            }
        }
    }

    // Report
    if "`verbose'" != "" {
        if `found' {
            di as text "  [FOUND] `file' -> `source': `filepath'"
        }
        else {
            di as error "  [NOT FOUND] `file'"
        }
    }

    // Return values
    return scalar found = `found'
    return local filepath "`filepath'"
    return local source "`source'"
end
