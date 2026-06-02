*! _pte_get_line_style.ado
*! Line style mapping for TT density plots
*! Returns line width, pattern, and color based on period number
*! Consistent with replication code L224 mapping

version 14.0
capture program drop _pte_get_line_style
program define _pte_get_line_style, rclass
    version 14.0
    
    // Parse arguments: period number (positional argument)
    args period
    
    // Validate input
    if "`period'" == "" {
        di as error "_pte_get_line_style: period argument required"
        exit 198
    }
    
    // Map period to line style attributes
    // Mapping table (consistent with replication code L224):
    //   period 0: lw=0.8, lp=solid,    lc=black
    //   period 1: lw=0.8, lp=dash,     lc=""
    //   period 2: lw=0.5, lp=dash,     lc=""
    //   period 3: lw=0.5, lp=dot,      lc=""
    //   period 4: lw=0.5, lp=dash_dot, lc=""
    //   other:    lw=0.5, lp=solid,    lc=""
    
    if `period' == 0 {
        local lw "0.8"
        local lp "solid"
        local lc "black"
    }
    else if `period' == 1 {
        local lw "0.8"
        local lp "dash"
        local lc ""
    }
    else if `period' == 2 {
        local lw "0.5"
        local lp "dash"
        local lc ""
    }
    else if `period' == 3 {
        local lw "0.5"
        local lp "dot"
        local lc ""
    }
    else if `period' == 4 {
        local lw "0.5"
        local lp "dash_dot"
        local lc ""
    }
    else {
        local lw "0.5"
        local lp "solid"
        local lc ""
    }
    
    // Return results
    return local lw "`lw'"
    return local lp "`lp'"
    return local lc "`lc'"
    
end
