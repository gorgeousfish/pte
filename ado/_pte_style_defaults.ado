*! _pte_style_defaults.ado
*! Default style definitions for pte_graph

version 14.0
program define _pte_style_defaults, rclass
    version 14.0
    args type
    
    // Global defaults
    return local scheme "s1color"
    return local bgcolor "white"
    
    // TT density plot (Figure 4) defaults
    if "`type'" == "tt" {
        return local title "Firm-specific Treatment Effects"
        return local xtitle "TT"
        return local ytitle "Density"
        return local legend "ring(0) col(2) pos(10) region(fcolor(none) lpattern(blank))"
        return local refline "xline(0, lc(gray) lp(dash) lw(0.3))"
        
        // Period styles (matching replication code L224)
        return local lw_0 "0.8"
        return local lp_0 "solid"
        return local lc_0 "black"
        return local lw_1 "0.8"
        return local lp_1 "dash"
        return local lc_1 ""
        return local lw_2 "0.5"
        return local lp_2 "dash"
        return local lc_2 ""
        return local lw_3 "0.5"
        return local lp_3 "dot"
        return local lc_3 ""
        return local lw_4 "0.5"
        return local lp_4 "dash_dot"
        return local lc_4 ""
    }
    
    // CATT grouped plot (Figure 5) defaults
    else if "`type'" == "catt" {
        return local title "CATT by Initial Productivity"
        return local xtitle "periods"
        return local ytitle `"average {&omega}{sub:e}{sup:TT}"'
        return local legend "ring(0) col(2) pos(11) region(fcolor(none) lpattern(blank))"
        return local refline "yline(0, lc(gray) lp(dash) lw(0.3))"
        
        // 5 series styles (matching replication code L253-254)
        return local ms_0 "Oh"
        return local lp_0 "solid"
        return local lw_0 ""
        return local lc_0 ""
        return local ms_1 "Dh"
        return local lp_1 "solid"
        return local lw_1 ""
        return local lc_1 ""
        return local ms_2 "Th"
        return local lp_2 "dot"
        return local lw_2 "0.5"
        return local lc_2 ""
        return local ms_3 "Sh"
        return local lp_3 "dot"
        return local lw_3 "0.5"
        return local lc_3 ""
        return local ms_4 "X"
        return local lp_4 "dot"
        return local lw_4 "0.5"
        return local lc_4 ""
    }
    
    // Diagnostic plot (Figure E.1) defaults
    else if "`type'" == "diagnose" {
        return local title `"CDF of {&epsilon}{sup:0}"'
        return local xtitle `"productivity shocks: {&epsilon}{sup:0}"'
        return local ytitle "Probability"
        return local legend "ring(0) col(1) pos(10) region(fcolor(none) lpattern(blank))"
        
        return local lc_treated "blue"
        return local lp_treated "solid"
        return local lw_treated "0.8"
        return local lc_control "red"
        return local lp_control "dash"
        return local lw_control "0.8"
    }
    
    // ATT summary plot defaults
    else if "`type'" == "att" {
        return local title "Dynamic Treatment Effects"
        return local xtitle `"Periods since treatment ({&ell})"'
        return local ytitle "ATT estimate"
        return local legend "off"
        return local refline "yline(0, lc(gray) lp(dash) lw(0.3))"
        
        return local lcolor "blue"
        return local lwidth "0.8"
        return local msymbol "O"
        return local msize "medium"
        return local mcolor "blue"
    }
    
    // Scatter plot defaults
    else if "`type'" == "scatter" {
        return local title "TT vs Initial Productivity"
        return local xtitle "initial productivity"
        return local ytitle `"{&omega}{sub:e}{sup:TT}"'
        return local legend "off"
        return local refline "yline(0, lc(gray) lp(dash) lw(0.3))"
        
        return local msize "0.3"
        return local mcolor "blue"
        return local msymbol "O"
    }
    
    // Method comparison plot (Figure 6) defaults
    else if "`type'" == "compare" {
        return local title "Comparison with Other Methods"
        return local xtitle "Estimated Coefficient"
        return local ytitle ""
        return local legend "ring(1) col(3) pos(6) region(fcolor(none) lpattern(blank))"
        
        return local lc_nolag "blue"
        return local ms_nolag "Dh"
        return local lc_linear "red"
        return local ms_linear "Dh"
        return local lc_cubic "green"
        return local ms_cubic "Dh"
    }
    
    // Evolution plot defaults
    else if "`type'" == "evolution" {
        return local title "Productivity Evolution"
        return local xtitle "Year"
        return local ytitle `"{&omega}"'
        return local legend "ring(0) col(2) pos(10) region(fcolor(none) lpattern(blank))"
        return local refline ""
        
        return local lc_treated "blue"
        return local lp_treated "solid"
        return local lw_treated "0.8"
        return local ms_treated "O"
        return local lc_control "red"
        return local lp_control "dash"
        return local lw_control "0.8"
        return local ms_control "D"
    }
    
    // Heterogeneity plot defaults
    else if "`type'" == "heterogeneity" {
        return local title "Treatment Effect Heterogeneity"
        return local xtitle "Group"
        return local ytitle "ATT"
        return local legend "off"
        return local refline "yline(0, lc(gray) lp(dash) lw(0.3))"
        
        return local lcolor "blue"
        return local lwidth "medium"
        return local msymbol "O"
        return local msize "medium"
        return local mcolor "blue"
    }
    
    // Default (unknown type)
    else {
        return local title ""
        return local xtitle ""
        return local ytitle ""
        return local legend "ring(0) col(2) pos(10) region(fcolor(none) lpattern(blank))"
        return local refline ""
        return local lwidth "0.8"
        return local lpattern "solid"
        return local msymbol "O"
        return local msize "medium"
    }
    
end
