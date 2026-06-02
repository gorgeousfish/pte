*! _pte_display_switch_statistics.ado

version 14.0
// _pte_display_switch_statistics: Format and display switching pattern stats
// Reads from e() scalars set by _pte_multiswitch or _pte_nonabs_ereturn

capture program drop _pte_display_switch_statistics
program define _pte_display_switch_statistics
    version 14.0

    syntax [, Verbose]

    // ================================================================
    // Retrieve switching statistics from e()
    // ================================================================
    local has_switch_stats = 0

    // Check if switching statistics are available
    capture confirm scalar e(N_never_switch)
    if _rc == 0 {
        local has_switch_stats = 1
    }

    if !`has_switch_stats' {
        if "`verbose'" != "" {
            di as text "[debug] _pte_display_switch_statistics: " ///
                "no switching statistics in e(), skipping"
        }
        exit 0
    }

    // ================================================================
    // Extract values
    // ================================================================
    local n_never    = e(N_never_switch)
    local n_once     = e(N_once_switch)
    local n_few      = e(N_few_switch)
    local n_frequent = e(N_frequent_switch)
    local n_total    = `n_never' + `n_once' + `n_few' + `n_frequent'

    // ================================================================
    // Display formatted table
    // ================================================================
    di as text ""
    di as text "{hline 70}"
    di as text "Sample composition by switching pattern:"
    di as text "{hline 70}"

    // Column headers
    di as text "  Category" _col(35) "Firms" _col(45) "Percent"
    di as text "  {hline 55}"

    // Never switch
    if `n_total' > 0 {
        local pct_never = round(100 * `n_never' / `n_total', 0.1)
        local pct_once  = round(100 * `n_once'  / `n_total', 0.1)
        local pct_few   = round(100 * `n_few'   / `n_total', 0.1)
        local pct_freq  = round(100 * `n_frequent' / `n_total', 0.1)
    }
    else {
        local pct_never = 0
        local pct_once  = 0
        local pct_few   = 0
        local pct_freq  = 0
    }
    local pct_total = cond(`n_total' > 0, 100, 0)

    di as text "  Never switch (0)"     _col(35) ///
        as result %6.0fc `n_never'      _col(45) ///
        as result %5.1f `pct_never' as text "%"

    di as text "  Single switch (1)"    _col(35) ///
        as result %6.0fc `n_once'       _col(45) ///
        as result %5.1f `pct_once' as text "%"

    di as text "  2-3 switches"         _col(35) ///
        as result %6.0fc `n_few'        _col(45) ///
        as result %5.1f `pct_few' as text "%"

    di as text "  Frequent (>3)"        _col(35) ///
        as result %6.0fc `n_frequent'   _col(45) ///
        as result %5.1f `pct_freq' as text "%"

    di as text "  {hline 55}"
    di as text "  Total"                _col(35) ///
        as result %6.0fc `n_total'      _col(45) ///
        as result %5.1f `pct_total' as text "%"

    // Additional info if available
    capture confirm scalar e(max_switch_observed)
    if _rc == 0 {
        di as text ""
        di as text "  Max switches observed: " as result e(max_switch_observed)
    }

    capture confirm scalar e(pct_frequent)
    if _rc == 0 & e(pct_frequent) > 0 {
        di as text "  Frequent switchers:    " ///
            as result %4.1f e(pct_frequent) as text "% of sample"
    }

    // Options used
    local first_switch_only `"`e(first_switch_only)'"'
    if `"`first_switch_only'"' == "yes" {
        di as text "  Option: first_switch_only applied"
    }

    capture confirm scalar e(maxswitch)
    if _rc == 0 {
        di as text "  Option: maxswitch(" as result e(maxswitch) as text ") applied"
    }

    di as text "{hline 70}"

    if "`verbose'" != "" {
        di as text "[debug] _pte_display_switch_statistics: " ///
            "displayed stats for `n_total' firms"
    }
end
