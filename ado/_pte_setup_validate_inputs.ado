*! _pte_setup_validate_inputs.ado
*! Validate the logged production-function variables supplied to pte_setup.

version 14.0
capture program drop _pte_setup_validate_inputs
program define _pte_setup_validate_inputs, rclass
	version 14.0
	
	// Use string options rather than varname so this helper, not the syntax
	// parser, owns the error surface and can explain which role failed.
	syntax , ///
		[OUTput(string)]   /// output variable name (e.g. lnq)
		[FREE(string)]     /// free input variable list (e.g. lnl lnm)
		[STATe(string)]    /// state variable list (e.g. lnk)
		[PROXy(string)]    /// proxy variable list (e.g. lnm)

	local output : list uniq output
	local free : list uniq free
	local state : list uniq state
	local proxy : list uniq proxy
	
	// Merge all roles into one validation surface, but keep duplicates from
	// inflating counts when the same logged variable is passed through more
	// than one option.
    // Public PTE commands pass logged production-function variables
    // (e.g. lny, lnl, lnk, lnm). Negative logged values are admissible
    // because they correspond to level variables in (0,1). Data cleaning
    // for level positivity belongs upstream in the raw-data preparation
    // step, not in this logged-variable surface validator.
    local all_vars `output' `free' `state' `proxy'
	
	local unique_vars : list uniq all_vars
	
	// Some callers validate only the panel metadata. In that case this helper
	// exits quietly with explicit skipped markers in r().
	if "`unique_vars'" == "" {
		return scalar validation_skipped = 1
		return scalar validation_passed = .
		return scalar total_invalid = .
		return scalar total_nonpos = .
		return scalar total_miss = .
		return scalar n_invalid_obs = .
		return scalar n_vars_validated = 0
		return local validated_vars ""
		exit
	}
	
	foreach var of local unique_vars {
		capture confirm variable `var'
		if _rc != 0 {
			di as error ""
			di as error "pte: variable {bf:`var'} not found"
			di as error "  please check variable name spelling"
			exit 111
		}
	}
	
	// Downstream production-function code assumes numeric storage because it
	// applies markout and algebra directly to these columns.
	foreach var of local unique_vars {
		capture confirm numeric variable `var'
		if _rc != 0 {
			di as error ""
			di as error "pte: variable {bf:`var'} is not numeric"
			di as error "  production variables must be numeric for log transformation"
			di as error "  use {bf:destring `var', replace} if appropriate"
			exit 109
		}
	}
	
	di as txt _n "Input Variable Validation:"
	di as txt "{hline 60}"
	
	local display_total_nonpos = 0
	local display_total_miss = 0
	local n_vars = 0
	
	// Create tempvar to track unique invalid observations
	tempvar _any_invalid
	qui gen byte `_any_invalid' = 0
	
	foreach var of local unique_vars {
		local n_vars = `n_vars' + 1
		
        // Logged public inputs may be negative, so the only invalid cells on
        // this surface are missings, not non-positive realized values.
        local n_nonpos = 0
		
		// missing() also covers extended missing codes .a-.z, which would
		// otherwise silently leak into markout and sample counts.
		qui count if missing(`var')
		local n_miss = r(N)
		
		// Track the union of invalid rows across all roles so callers know how
		// many observations disappear after setup, not just how many cells fail.
        qui replace `_any_invalid' = 1 if missing(`var')
		
		return scalar n_nonpos_`var' = `n_nonpos'
		return scalar n_miss_`var' = `n_miss'
		
		if `n_nonpos' > 0 | `n_miss' > 0 {
			di as txt "  `var': " _c
			if `n_nonpos' > 0 {
				di as result "`n_nonpos' non-positive" _c
			}
			if `n_nonpos' > 0 & `n_miss' > 0 {
				di as txt ", " _c
			}
			if `n_miss' > 0 {
				di as result "`n_miss' missing" _c
			}
			di ""
		}
		else {
			di as txt "  `var': " as result "valid"
		}
		
		local display_total_nonpos = `display_total_nonpos' + `n_nonpos'
		local display_total_miss = `display_total_miss' + `n_miss'
	}
	
	di as txt "{hline 60}"
	local total_nonpos = 0
	local total_miss = 0
	foreach var of local all_vars {
		local n_nonpos = 0
		qui count if missing(`var')
		local n_miss = r(N)
		local total_nonpos = `total_nonpos' + `n_nonpos'
		local total_miss = `total_miss' + `n_miss'
	}
	local total_invalid = `total_nonpos' + `total_miss'
	
	qui count if `_any_invalid' == 1
	local n_invalid_obs = r(N)
	
	if `total_invalid' > 0 {
		di as txt "Total invalid input-role cells: " as result `total_invalid'
		di as txt "  Non-positive: " as result `total_nonpos'
		di as txt "  Missing:      " as result `total_miss'
		di as txt "Unique invalid obs: " as result `n_invalid_obs'
		di as txt ""
		di as txt "Note: These observations will be automatically excluded"
		di as txt "      during pte estimation (via markout mechanism)"
	}
	else {
		di as txt "All input variables " as result "valid"
	}
	
	return scalar total_nonpos = `total_nonpos'
	return scalar total_miss = `total_miss'
	return scalar total_invalid = `total_invalid'
	return scalar n_invalid_obs = `n_invalid_obs'
	return scalar validation_passed = (`n_invalid_obs' == 0)
	return scalar validation_skipped = 0
	return scalar n_vars_validated = `n_vars'
	return local validated_vars "`unique_vars'"
	
end
