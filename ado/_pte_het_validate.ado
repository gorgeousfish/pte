*! _pte_het_validate.ado
*! Validate preconditions for pte_heterogeneity
*! Checks:
*! 1. pte main command has been run (e(cmd) == "pte")
*! 2. _pte_tt exists and remains numeric (treatment effects)
*! 3. _pte_nt exists and remains integer-valued (normalized time)
*! 4. Valid treated observations exist (_pte_tt non-missing, _pte_nt >= 0)
*! 5. by-variable exists and has non-missing values on treated support
*! Error codes:
*! 301: pte has not been run
*! 111: Required variable not found
*! 2000: No valid observations

version 14.0
capture program drop _pte_het_validate
program define _pte_het_validate
    version 14.0
    
    syntax , BY(varname)
    
    // ================================================================
    // Check 1: pte has been run (e(cmd) == "pte")
    // ================================================================
    
    if "`e(cmd)'" != "pte" & "`e(cmd)'" != "pte_heterogeneity" {
        di as error "pte has not been run; use {bf:pte} first"
        exit 301
    }
    
    // ================================================================
    // Check 2: _pte_tt variable exists
    // ================================================================
    
    capture confirm variable _pte_tt, exact
    if _rc != 0 {
        di as error "_pte_tt variable not found"
        di as error "This variable should be created by pte main command"
        exit 111
    }

    capture confirm numeric variable _pte_tt, exact
    if _rc != 0 {
        di as error "_pte_tt must be numeric"
        di as error "This variable should be created by pte main command"
        exit 111
    }
    
    // ================================================================
    // Check 3: _pte_nt variable exists
    // ================================================================
    
    capture confirm variable _pte_nt, exact
    if _rc != 0 {
        di as error "_pte_nt variable not found"
        di as error "This variable should be created by pte main command"
        exit 111
    }

    capture confirm numeric variable _pte_nt, exact
    if _rc != 0 {
        di as error "_pte_nt must be numeric"
        di as error "This variable should be created by pte main command"
        exit 111
    }

    capture assert abs(_pte_nt - round(_pte_nt)) <= 1e-10 if !missing(_pte_nt)
    if _rc != 0 {
        di as error "_pte_nt must be integer-valued when non-missing"
        di as error "This variable should be created by pte main command"
        exit 450
    }

    capture confirm variable _pte_treat, exact
    if _rc != 0 {
        di as error "_pte_treat variable not found"
        di as error "Heterogeneity analysis requires the exact treated-support bridge from pte"
        exit 111
    }
    capture confirm numeric variable _pte_treat, exact
    if _rc != 0 {
        di as error "_pte_treat must be numeric"
        di as error "This variable should be created by pte main command"
        exit 111
    }
    capture assert inlist(_pte_treat, 0, 1) if !missing(_pte_treat)
    if _rc != 0 {
        di as error "_pte_treat must be binary when non-missing"
        di as error "This variable should be created by pte main command"
        exit 450
    }
    local treated_condition " & _pte_treat == 1"
    
    // ================================================================
    // Check 4: Valid observations exist
    // ================================================================
    
    quietly count if !missing(_pte_tt) & _pte_nt >= 0`treated_condition'
    if r(N) == 0 {
        di as error "no valid treated observations with nt >= 0 and non-missing TT"
        exit 2000
    }
    
    // ================================================================
    // Check 5: by-variable has non-missing values among valid obs
    // ================================================================
    
    quietly count if !missing(_pte_tt) & _pte_nt >= 0`treated_condition' & !missing(`by')
    if r(N) == 0 {
        di as error "by-variable `by' has no non-missing values among valid treated observations"
        exit 2000
    }
    
end
