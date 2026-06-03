*! _pte_mata_error.ado
*! Usage:
*! <error_code> [, file(string) func(string)]
*! Error codes:
*! 601 - File not found
*! 602 - Syntax/compilation error
*! 603 - Version incompatible (Stata < 14.0)
*! 604 - Insufficient memory
*! 605 - Function name conflict
*! 606 - Post-compilation verification failed

version 14.0
capture program drop _pte_mata_error
program define _pte_mata_error
    version 14.0

    gettoken errcode 0 : 0
    syntax [, FILE(string) FUNC(string)]

    // Validate error code
    if "`errcode'" == "" {
        di as error "pte internal error: _pte_mata_error requires error code"
        exit 198
    }

    di as error ""
    di as error _dup(60) "-"

    if "`errcode'" == "601" {
        // File not found
        di as error "pte error 601: Mata source file not found"
        if "`file'" != "" {
            di as error "  File: `file'"
        }
        di as error ""
        di as error "  Recovery suggestions:"
        di as error "    1. Reinstall pte: net install pte, replace from(https://raw.githubusercontent.com/gorgeousfish/pte/main)"
        di as error "    2. Check adopath: adopath"
        di as error "    3. Verify file exists in mata/ directory"
        di as error "    4. See: help _pte_mata_init"
    }
    else if "`errcode'" == "602" {
        // Syntax/compilation error
        di as error "pte error 602: Mata compilation syntax error"
        if "`file'" != "" {
            di as error "  File: `file'"
        }
        di as error ""
        di as error "  Recovery suggestions:"
        di as error "    1. Reinstall pte: net install pte, replace from(https://raw.githubusercontent.com/gorgeousfish/pte/main)"
        di as error "    2. Check for corrupted .mata files"
        di as error "    3. Try: _pte_mata_init, force verbose"
        di as error "    4. See: help _pte_mata_init"
    }
    else if "`errcode'" == "603" {
        // Version incompatible
        di as error "pte error 603: Stata version incompatible"
        di as error "  pte requires Stata 14.0 or later."
        di as error "  Current version: `c(stata_version)'"
        di as error ""
        di as error "  Recovery suggestions:"
        di as error "    1. Upgrade Stata to version 14.0 or later"
        di as error "    2. Contact StataCorp for upgrade options"
    }
    else if "`errcode'" == "604" {
        // Insufficient memory
        di as error "pte error 604: Insufficient memory for Mata compilation"
        di as error ""
        di as error "  Recovery suggestions:"
        di as error "    1. Increase memory: set maxvar 10000"
        di as error "    2. Clear unused data: clear all"
        di as error "    3. Drop unused Mata functions: mata: mata clear"
        di as error "    4. Restart Stata with more memory"
    }
    else if "`errcode'" == "605" {
        // Function name conflict
        di as error "pte error 605: Mata function name conflict"
        if "`func'" != "" {
            di as error "  Function: `func'"
        }
        di as error ""
        di as error "  Recovery suggestions:"
        di as error "    1. Use force option: _pte_mata_init, force"
        di as error "    2. Clean existing functions: _pte_mata_clean, all confirm"
        di as error "    3. Check for conflicting packages"
    }
    else if "`errcode'" == "606" {
        // Post-compilation verification failed
        di as error "pte error 606: Mata function not found after compilation"
        if "`func'" != "" {
            di as error "  Expected function: `func'"
        }
        di as error ""
        di as error "  Recovery suggestions:"
        di as error "    1. Try force recompile: _pte_mata_init, force verbose"
        di as error "    2. Check .mata file contents for correct function names"
        di as error "    3. Reinstall pte: net install pte, replace from(https://raw.githubusercontent.com/gorgeousfish/pte/main)"
        di as error "    4. See: help _pte_mata_init"
    }
    else {
        // Unknown error code
        di as error "pte error `errcode': Unknown Mata initialization error"
        di as error ""
        di as error "  Recovery suggestions:"
        di as error "    1. Try: _pte_mata_init, force verbose"
        di as error "    2. Reinstall pte: net install pte, replace from(https://raw.githubusercontent.com/gorgeousfish/pte/main)"
        di as error "    3. See: help _pte_mata_init"
    }

    di as error _dup(60) "-"
    di as error ""
end
