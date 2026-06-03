*! pte_version.ado
*! Version query command for pte package

version 14.0
capture program drop pte_version
program define pte_version, rclass
    version 14.0
    
    // =========================================================================
    // Version constants (SSOT - Single Source of Truth)
    // =========================================================================
    local version     "1.0.0"
    local date        "2026-05-31"
    local date_stata  "31may2026"
    local date_pkg    "20260531"
    local authors     "Chen, Liao, Schurter"
    local title       "Identifying Treatment Effects on Productivity"
    local paper_year  "2026"
    local paper_type  "Working Paper"
    
    // Release history: "version|date|changes"
    local history_1   "1.0.0|2026-01-01|Initial release: production function estimation (CD, Translog), ATT estimation with bootstrap inference, diagnostic and visualization commands"
    local history_n   1
    
    // =========================================================================
    // Syntax parsing
    // =========================================================================
    syntax [, Detail Check]
    
    // Option conflict detection
    if "`detail'" != "" & "`check'" != "" {
        di as error "options {bf:detail} and {bf:check} may not be combined"
        exit 198
    }
    
    // =========================================================================
    // Basic output (always displayed)
    // =========================================================================
    di as text ""
    di as text "{hline 60}"
    di as text "{bf:pte}: Productivity Treatment Effects"
    di as result "Version `version'" as text " (`date')"
    di as text "Authors: `authors'"
    di as text ""
    di as text "Reference: Chen, Z., Liao, M., & Schurter, K. (`paper_year')."
    di as text "  `title'."
    di as text "  `paper_type'."
    di as text "{hline 60}"
    
    // =========================================================================
    // detail option: release history
    // =========================================================================
    if "`detail'" != "" {
        di as text ""
        di as text "{bf:Release History:}"
        
        forvalues i = `history_n'(-1)1 {
            local history_entry "`history_`i''"
            
            // Parse: version|date|changes
            gettoken hist_version history_entry : history_entry, parse("|")
            gettoken sep history_entry : history_entry, parse("|")
            gettoken hist_date history_entry : history_entry, parse("|")
            gettoken sep history_entry : history_entry, parse("|")
            local hist_changes "`history_entry'"
            
            di as text ""
            di as text "  " as result "`hist_version'" as text " (`hist_date')"
            
            // Format change items (comma-separated)
            local changes_remaining "`hist_changes'"
            while "`changes_remaining'" != "" {
                gettoken change_item changes_remaining : changes_remaining, parse(",")
                if "`change_item'" != "," {
                    local change_item = trim("`change_item'")
                    if "`change_item'" != "" {
                        di as text "    * `change_item'"
                    }
                }
            }
        }
        
        di as text ""
        di as text "{hline 60}"
    }
    
    // =========================================================================
    // check option: GitHub update check
    // =========================================================================
    if "`check'" != "" {
        di as text ""
        di as text "Checking for updates..."
        di as text ""
        di as text "Your installed version: " as result "`version'"
        di as text ""
        di as text "To update to the latest version, run:"
        di as text `"  {stata `"net install pte, replace from("https://raw.githubusercontent.com/gorgeousfish/pte/main")"'}"'
        di as text ""
        di as text `"Release notes: {browse "https://github.com/gorgeousfish/pte"}"'
    }
    
    // =========================================================================
    // Store r() return values
    // =========================================================================
    return local version  "`version'"
    return local date     "`date'"
    return local authors  "`authors'"
    
end
