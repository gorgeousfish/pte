*! _pte_pool_merge_data.ado
*! Appends firm-level TT data from all industry groups into one dataset

version 14.0
program define _pte_pool_merge_data
    version 14.0
    syntax, groups(string) tempdir(string)
    
    local required_vars "TT_mean nt"
    
    // ─────────────────────────────────────────────────────────────
    // Step 1: Load first industry data as base
    // ─────────────────────────────────────────────────────────────
    local first_grp : word 1 of `groups'
    
    capture confirm file "`tempdir'/tt_`first_grp'.dta"
    if _rc {
        di as error "Data file not found: `tempdir'/tt_`first_grp'.dta"
        exit 601
    }
    
    use "`tempdir'/tt_`first_grp'.dta", clear
    foreach var of local required_vars {
        capture confirm numeric variable `var'
        if _rc {
            di as error "Required numeric variable `var' not found in `tempdir'/tt_`first_grp'.dta"
            exit 111
        }
    }
    local total_expected = _N
    
    // ─────────────────────────────────────────────────────────────
    // Step 2: Append remaining industries
    // ─────────────────────────────────────────────────────────────
    foreach grp of local groups {
        if "`grp'" != "`first_grp'" {
            // Verify file exists before append
            capture confirm file "`tempdir'/tt_`grp'.dta"
            if _rc {
                di as error "Data file not found: `tempdir'/tt_`grp'.dta"
                exit 601
            }
            
            // Get row count for verification
            qui describe using "`tempdir'/tt_`grp'.dta"
            local total_expected = `total_expected' + r(N)
            
            preserve
            quietly use "`tempdir'/tt_`grp'.dta", clear
            foreach var of local required_vars {
                capture confirm numeric variable `var'
                if _rc {
                    restore
                    di as error "Required numeric variable `var' not found in `tempdir'/tt_`grp'.dta"
                    exit 111
                }
            }
            restore
            
            // Append with force (allow variable mismatch)
            append using "`tempdir'/tt_`grp'.dta", force
        }
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 3: Verify merge results
    // ─────────────────────────────────────────────────────────────
    count
    local n_merged = r(N)
    if `n_merged' != `total_expected' {
        di as error "Merge count mismatch. Expected `total_expected', got `n_merged'"
        exit 9
    }
    
    // Verify required variables exist
    foreach var in TT_mean nt {
        capture confirm variable `var'
        if _rc {
            di as error "Required variable `var' not found after merge"
            exit 111
        }
    }
    
    di as text "Merged `n_merged' observations from " `: word count `groups'' " industries"
end
