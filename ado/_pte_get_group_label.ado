*! _pte_get_group_label.ado
*! Group label generator for CATT plots

version 14.0
capture program drop _pte_get_group_label
program define _pte_get_group_label, rclass
    version 14.0
    args g quantiles
    
    if `quantiles' == 3 {
        if `g' == 1 local lab "low productivity"
        else if `g' == 2 local lab "medium productivity"
        else local lab "high productivity"
    }
    else if `quantiles' == 5 {
        // Fix replication code L267 bug (groups 3/4 both labeled "medium productivity")
        if `g' == 1 local lab "low productivity"
        else if `g' == 2 local lab "medium-low"
        else if `g' == 3 local lab "medium"
        else if `g' == 4 local lab "medium-high"
        else local lab "high productivity"
    }
    else if `quantiles' == 4 {
        if `g' == 1 local lab "low"
        else if `g' == 2 local lab "medium-low"
        else if `g' == 3 local lab "medium-high"
        else local lab "high"
    }
    else {
        local lab "Q`g'"
    }
    
    return local label "`lab'"
end
