*! _pte_error.ado
*! Unified error handling for pte package

version 14.0
/*
=============================================================================
PTE Error Code Registry (v1.0)
=============================================================================

STANDARD STATA ERROR CODES
--------------------------
Code  Category       Description                      Usage
----  --------       -----------                      -----
198   syntax         Invalid option value             method(op), omegapoly(5)
301   estimation     Previous estimation not found    predict before pte
111   variable       Variable does not exist          internal var deleted
459   data           Data not xtset                   no xtset
498   assumption     Assumption/data condition fail   Assumption 3.3 violated
430   convergence    Optimization did not converge    GMM iteration limit
601   loading        Resource not found               Mata function missing

PTE EXTENSION ERROR CODES (2000+)
---------------------------------
Code  Feature        Description                      Trigger
----  -------        -----------                      -------
2001  assumption     No consecutive untreated obs     Assumption 3.3
2002  assumption     No consecutive treated obs       Assumption 3.3
2003  assumption     No treatment variation           All D=0 or all D=1
2004  assumption     No control group                 All firms treated
3001  FR-015         persistperiods exceeds T/2       persistperiods > T/2
3002  FR-015         Invalid switchdirection          switchdirection invalid
3003  FR-016         Normalization failed             no valid base sample
3004  FR-017         Fewer than 2 cohorts             cohort var < 2 levels
3005  FR-018         Panel length insufficient        T < lagperiods + 1
3006  FR-019         Invalid target group             targetgroup empty/uniform
3007  combination    Mutually exclusive options        incompatible combination
3008  sample         Insufficient observations        cell count < 30
3009  data           Panel too short                  panel < min required

=============================================================================
*/

capture program drop _pte_error
program define _pte_error
    version 14.0
    
    // Parse arguments
    syntax, errcode(integer) msg(string) [suggestion(string)]
    
    // Validate error code
    if `errcode' < 0 {
        di as error "_pte_error: Invalid error code `errcode'"
        exit 198
    }
    
    // Output error message with pte: prefix
    di as error "pte: `msg'"
    
    // Output suggested fix if provided
    if `"`suggestion'"' != "" {
        di as error " "
        di as error "  Suggested fix: `suggestion'"
    }
    
    // Exit with error code
    exit `errcode'
end
