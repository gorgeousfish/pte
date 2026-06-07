*! _pte_normalize.ado
*! Productivity Normalization Dispatcher
*! Dispatches to specific normalization methods:

version 14.0
capture program drop _pte_normalize
program define _pte_normalize, eclass
    version 14.0
    
    syntax , method(string) [ATTnorm Quietly]
    
    // ============ Validate preconditions ============
    
    // Check treatdependent is enabled
    if "`e(treatdependent)'" != "1" {
        di as error "normalize() requires treatdependent option"
        di as error "Run pte with: treatdependent normalize(`method')"
        exit 198
    }
    
    // ============ Dispatch to specific implementation ============
    
    if "`method'" == "indexing" {
        // Sub-module does NOT declare eclass
        // Returns results via scalar/matrix
        _pte_normalize_indexing, `attnorm' `quietly'
        
        // Append normalization results to e() in this eclass context
        ereturn local normalize_method "indexing"
        ereturn local omega_norm "_pte_omega_indexing"
        
        // Copy b0 matrix (use matrix copy to prevent move semantics)
        tempname b0_copy
        matrix `b0_copy' = _pte_norm_b0_used
        ereturn matrix b_untreated_used = `b0_copy'
        
        // Store verification scalars
        ereturn scalar normalize_d0_corr = scalar(_pte_norm_d0_corr)
        ereturn scalar normalize_d0_maxdiff = scalar(_pte_norm_d0_maxdiff)
        ereturn scalar normalize_d1_meandiff = scalar(_pte_norm_d1_meandiff)
        ereturn scalar normalize_verify_pass = scalar(_pte_norm_verify_pass)
        ereturn scalar normalize_n_params = scalar(_pte_norm_n_params)
        ereturn scalar normalize_omega_n = scalar(_pte_norm_omega_n)
        ereturn scalar normalize_omega_mean = scalar(_pte_norm_omega_mean)
        ereturn scalar normalize_omega_sd = scalar(_pte_norm_omega_sd)
        
        // Store ATT_norm results if computed (Task 28)
        ereturn scalar att_norm_computed = scalar(_pte_norm_att_norm_computed)
        if scalar(_pte_norm_att_norm_computed) == 1 {
            local att_norm_horizon = scalar(_pte_norm_att_norm_horizon)
            forvalues s = 0/`att_norm_horizon' {
                ereturn scalar att_norm_`s' = scalar(_pte_norm_att_norm_`s')
            }
            ereturn local att_norm_computed_flag "1"
        }
        else {
            ereturn local att_norm_computed_flag "0"
        }
        
        // Clean up temporary scalars/matrices from sub-module
        capture scalar drop _pte_norm_d0_corr
        capture scalar drop _pte_norm_d0_maxdiff
        capture scalar drop _pte_norm_d1_meandiff
        capture scalar drop _pte_norm_verify_pass
        capture scalar drop _pte_norm_n_params
        capture scalar drop _pte_norm_omega_n
        capture scalar drop _pte_norm_omega_mean
        capture scalar drop _pte_norm_omega_sd
        capture scalar drop _pte_norm_att_norm_computed
        capture scalar _pte_norm_att_norm_hmax_drop = _pte_norm_att_norm_horizon
        if _rc == 0 & !missing(_pte_norm_att_norm_hmax_drop) {
            local att_norm_hmax_drop = _pte_norm_att_norm_hmax_drop
            forvalues s = 0/`att_norm_hmax_drop' {
                capture scalar drop _pte_norm_att_norm_`s'
            }
        }
        capture scalar drop _pte_norm_att_norm_hmax_drop
        capture scalar drop _pte_norm_att_norm_horizon
        capture matrix drop _pte_norm_b0_used
    }
    else if "`method'" == "benchmark" {
        _pte_normalize_benchmark, `attnorm' `quietly'

        ereturn local normalize_method "benchmark"
        ereturn local omega_norm "_pte_omega_benchmark"

        tempname b0_copy b1_copy bench_copy
        matrix `b0_copy' = _pte_norm_b0_used
        matrix `b1_copy' = _pte_norm_b1_used
        matrix `bench_copy' = _pte_norm_benchmark_inputs
        ereturn matrix b_untreated_used = `b0_copy'
        ereturn matrix b_treated_used = `b1_copy'
        ereturn matrix benchmark_inputs = `bench_copy'

        ereturn scalar c_factor = scalar(_pte_norm_c)
        ereturn scalar benchmark_lnl_bar = scalar(_pte_norm_lnl_bar)
        ereturn scalar benchmark_lnk_bar = scalar(_pte_norm_lnk_bar)
        ereturn scalar delta_l = scalar(_pte_norm_delta_l)
        ereturn scalar delta_k = scalar(_pte_norm_delta_k)
        ereturn scalar normalize_d0_corr = scalar(_pte_norm_d0_corr)
        ereturn scalar normalize_d0_maxdiff = scalar(_pte_norm_d0_maxdiff)
        ereturn scalar normalize_d1_meandiff = scalar(_pte_norm_d1_meandiff)
        ereturn scalar normalize_verify_pass = scalar(_pte_norm_verify_pass)
        ereturn scalar normalize_n_params = scalar(_pte_norm_n_params)
        ereturn scalar normalize_omega_n = scalar(_pte_norm_omega_n)
        ereturn scalar normalize_omega_mean = scalar(_pte_norm_omega_mean)
        ereturn scalar normalize_omega_sd = scalar(_pte_norm_omega_sd)
        ereturn scalar att_norm_computed = 0
        ereturn local att_norm_computed_flag "0"

        capture scalar drop _pte_norm_c
        capture scalar drop _pte_norm_lnl_bar
        capture scalar drop _pte_norm_lnk_bar
        capture scalar drop _pte_norm_delta_l
        capture scalar drop _pte_norm_delta_k
        capture scalar drop _pte_norm_d0_corr
        capture scalar drop _pte_norm_d0_maxdiff
        capture scalar drop _pte_norm_d1_meandiff
        capture scalar drop _pte_norm_verify_pass
        capture scalar drop _pte_norm_n_params
        capture scalar drop _pte_norm_omega_n
        capture scalar drop _pte_norm_omega_mean
        capture scalar drop _pte_norm_omega_sd
        capture matrix drop _pte_norm_b0_used
        capture matrix drop _pte_norm_b1_used
        capture matrix drop _pte_norm_benchmark_inputs
    }
    else if "`method'" == "none" | "`method'" == "" {
        // No normalization — do nothing
        ereturn local normalize_method "none"
    }
    else {
        di as error "unknown normalization method: `method'"
        di as error "Valid options: none, indexing, benchmark"
        exit 198
    }
    
end
