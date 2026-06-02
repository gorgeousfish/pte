*! _pte_convergence_warning.ado

version 14.0
capture program drop _pte_convergence_warning
program define _pte_convergence_warning
    version 14.0
    
    // Parse arguments: fval iterations maxiter
    args fval iterations maxiter
    
    // Validate inputs
    if mi("`fval'") | mi("`iterations'") | mi("`maxiter'") {
        di as error "_pte_convergence_warning requires: fval iterations maxiter"
        exit 198
    }
    
    // Display warning header
    di as error ""
    di as error "{hline 60}"
    di as error "Warning: GMM optimization did not converge"
    di as error "{hline 60}"
    di as error "  Final criterion value:  " as result %12.8f `fval'
    di as error "  Iterations:             " as result %12.0f `iterations'
    di as error "  Maximum iterations:     " as result %12.0f `maxiter'
    di as error "{hline 60}"
    di as error ""
    di as error "Diagnostic suggestions:"
    di as error ""
    di as error "  Level 1 - Data issues:"
    di as error "    - Check for extreme outliers in production variables"
    di as error "    - Ensure sufficient sample size (N > 100)"
    di as error "    - Verify panel structure (xtset)"
    di as error ""
    di as error "  Level 2 - Optimization settings:"
    di as error "    - Try custom starting values: init(numlist)"
    di as error "    - Enable multi-start search: grid"
    di as error "    - Increase iterations: maxiter(20000)"
    di as error "    - Relax tolerance: tolerance(1e-5)"
    di as error ""
    di as error "  Level 3 - Model specification:"
    di as error "    - Try Cobb-Douglas: pfunc(cd)"
    di as error "    - Reduce polynomial order: omegapoly(1)"
    di as error "    - Check instrument validity"
    di as error ""
    
end
