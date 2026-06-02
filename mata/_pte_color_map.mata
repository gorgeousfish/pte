*! version 1.0.0  17Feb2026
*! Color mapping for pte_graph
*! Part of pte package - Chen, Liao & Schurter (2026)

version 14.0

mata:

struct pte_color_map {
    string scalar tt_period0
    string scalar tt_period1
    string scalar tt_period2
    string scalar tt_period3
    string scalar tt_period4
    
    string scalar catt_low
    string scalar catt_medium
    string scalar catt_high
    
    string scalar diag_treated
    string scalar diag_control
    
    string scalar comp_nolag
    string scalar comp_linear
    string scalar comp_cubic
    
    string scalar reference
    string scalar background
}

struct pte_color_map scalar pte_default_colors()
{
    struct pte_color_map scalar c
    
    c.tt_period0 = "black"
    c.tt_period1 = ""
    c.tt_period2 = ""
    c.tt_period3 = ""
    c.tt_period4 = ""
    
    c.catt_low = "blue"
    c.catt_medium = "red"
    c.catt_high = "green"
    
    c.diag_treated = "blue"
    c.diag_control = "red"
    
    c.comp_nolag = "blue"
    c.comp_linear = "red"
    c.comp_cubic = "green"
    
    c.reference = "gray"
    c.background = "white"
    
    return(c)
}

struct pte_color_map scalar pte_grayscale_colors()
{
    struct pte_color_map scalar c
    
    c.tt_period0 = "black"
    c.tt_period1 = "gs4"
    c.tt_period2 = "gs6"
    c.tt_period3 = "gs8"
    c.tt_period4 = "gs10"
    
    c.catt_low = "gs2"
    c.catt_medium = "gs5"
    c.catt_high = "gs8"
    
    c.diag_treated = "gs4"
    c.diag_control = "gs8"
    
    c.comp_nolag = "gs2"
    c.comp_linear = "gs5"
    c.comp_cubic = "gs8"
    
    c.reference = "gs10"
    c.background = "white"
    
    return(c)
}

struct pte_color_map scalar pte_colorblind_colors()
{
    struct pte_color_map scalar c
    
    // Wong (2011) colorblind-safe palette
    c.tt_period0 = "0 0 0"
    c.tt_period1 = "230 159 0"
    c.tt_period2 = "86 180 233"
    c.tt_period3 = "0 158 115"
    c.tt_period4 = "204 121 167"
    
    c.catt_low = "0 114 178"
    c.catt_medium = "230 159 0"
    c.catt_high = "0 158 115"
    
    c.diag_treated = "0 114 178"
    c.diag_control = "230 159 0"
    
    c.comp_nolag = "0 114 178"
    c.comp_linear = "230 159 0"
    c.comp_cubic = "0 158 115"
    
    c.reference = "120 120 120"
    c.background = "white"
    
    return(c)
}

end