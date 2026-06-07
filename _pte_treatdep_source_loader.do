*! version 1.0.0  06apr2026
*! Top-level loader for source-loading an installed treatdependent ado file.

version 14.0

local pte_loader_path `"`c(filename)'"'
local pte_loader_dir ""
if `"`pte_loader_path'"' != "" {
    local pte_loader_dir = reverse(substr(reverse(`"`pte_loader_path'"'), ///
        strpos(reverse(`"`pte_loader_path'"'), "/") + 1, .))
    if substr(`"`pte_loader_dir'"', -1, 1) == "/" {
        local pte_loader_dir = substr(`"`pte_loader_dir'"', 1, ///
            length(`"`pte_loader_dir'"') - 1)
    }
}

capture mata: mata describe facf1()
local pte_need_seed = (_rc != 0)
capture mata: mata describe facf2()
if _rc != 0 local pte_need_seed = 1
capture mata: mata describe facf3()
if _rc != 0 local pte_need_seed = 1
capture mata: mata describe opt_mata()
if _rc != 0 local pte_need_seed = 1

if `pte_need_seed' {
    local pte_seed_file ""
    if `"`pte_loader_dir'"' != "" {
        capture confirm file "`pte_loader_dir'/_pte_treatdep_seed_placeholders.do"
        if _rc == 0 {
            local pte_seed_file `"`pte_loader_dir'/_pte_treatdep_seed_placeholders.do'"'
        }
    }
    if `"`pte_seed_file'"' == "" {
        capture quietly findfile _pte_treatdep_seed_placeholders.do
        if _rc == 0 {
            local pte_seed_file `"`r(fn)'"'
        }
    }
    if `"`pte_seed_file'"' != "" {
        include `"`pte_seed_file'"'
    }
}

local pte_source_file `"$PTE_TREATDEP_SOURCE_FILE"'
include `"`pte_source_file'"'
