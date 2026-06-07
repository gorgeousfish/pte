*! pte_export.ado
*! Export pte e() results to LaTeX/XLSX/CSV.

version 14.0
capture program drop pte_export
program define pte_export, rclass
    version 14.0

    // Contract: only the "results" subcommand is supported; output is derived from current e().
    gettoken subcmd 0 : 0
    local subcmd_raw `"`subcmd'"'
    local subcmd = lower(strtrim(`"`subcmd'"'))
    if "`subcmd'" != "results" {
        di as error "{bf:Error}: Unknown subcommand '`subcmd_raw''"
        di as error "Usage: pte_export results using filename [, options]"
        exit 198
    }

    local parser0 = lower(`"`0'"')

    syntax using/ [, FORmat(string) INClude(string) ///
                     STARS(numlist min=3 max=3 ascending) ///
                     noSE REPLACE DECimals(integer 3) ///
                     TItle(string) NOTE(string)]

    // Keep track of which format-specific options were explicitly supplied so
    // non-LaTeX exports can reject no-op public options up front. String
    // options can be explicitly provided as "". Stata also accepts both
    // title("") and title ("") spellings, so we scan the raw option tail for
    // their tokens instead of relying only on post-syntax macro contents.
    //
    // Restrict the scan to the option tail after the first comma that appears
    // outside quoted using filenames. Otherwise paths such as
    // "tables/export title (draft).csv" would be misread as public title().
    local parser_opts ""
    local _pte_scan_in_quote = 0
    local _pte_scan_start = 0
    local _pte_scan_len = strlen(`"`parser0'"')
    local _pte_quote `"`=char(34)'"'
    forvalues _pte_i = 1/`_pte_scan_len' {
        local _pte_scan_ch = substr(`"`parser0'"', `_pte_i', 1)
        if `"`_pte_scan_ch'"' == `"`_pte_quote'"' {
            local _pte_scan_in_quote = 1 - `_pte_scan_in_quote'
        }
        else if `"`_pte_scan_ch'"' == "," & `_pte_scan_in_quote' == 0 {
            local _pte_scan_start = `_pte_i' + 1
            continue, break
        }
    }
    if `_pte_scan_start' > 0 {
        local parser_opts = substr(`"`parser0'"', `_pte_scan_start', .)
    }

    local title_explicit = (`"`title'"' != "")
    foreach tok in "ti" "tit" "titl" "title" {
        if regexm(`"`parser_opts'"', "(^|[ ,])`tok'[ ]*[(]") local title_explicit = 1
    }

    local note_explicit = (`"`note'"' != "")
    foreach tok in "n" "no" "not" "note" {
        if regexm(`"`parser_opts'"', "(^|[ ,])`tok'[ ]*[(]") local note_explicit = 1
    }

    local stars_explicit = ("`stars'" != "")
    foreach tok in "s" "st" "sta" "star" "stars" {
        if regexm(`"`parser_opts'"', "(^|[ ,])`tok'[ ]*[(]") local stars_explicit = 1
    }

    // Defaults (sentinels chosen to avoid forwarding empty options downstream).
    if "`format'" == "" local format "latex"
    local format = lower("`format'")
    if "`format'" == "excel" local format "xlsx"

    if "`format'" != "latex" {
        local nonlatex_opts ""
        if `title_explicit' local nonlatex_opts "`nonlatex_opts' title()"
        if `note_explicit' local nonlatex_opts "`nonlatex_opts' note()"
        if `stars_explicit' local nonlatex_opts "`nonlatex_opts' stars()"
        local nonlatex_opts = trim("`nonlatex_opts'")
        if `"`nonlatex_opts'"' != "" {
            di as error "{bf:Error}: `nonlatex_opts' require format(latex)"
            di as error "CSV/XLSX exports are numeric-only and do not render captions, footnotes, or significance stars."
            exit 198
        }
    }

    local include = lower(trim(`"`include'"'))
    if "`include'" == "" local include "all"
    if "`include'" != "all" {
        di as error "{bf:Error}: include(`include') is not supported"
        di as error "The current released exporter accepts only include(all)."
        exit 198
    }
    if "`stars'" == "" local stars "0.01 0.05 0.10"
    if `decimals' < 0 | `decimals' > 8 {
        di as error "{bf:Error}: decimals() must be between 0 and 8"
        exit 198
    }
    local show_se = ("`se'" != "nose")

    // Results availability: require e(att); other matrices are optional.

    capture matrix _tmp_att = e(att)
    if _rc {
        di as error "{bf:Error}: No estimation results found."
        di as error "Run pte estimation that stores e(att) first."
        exit 301
    }

    // Grouped public ATT results publish their own row-mapped contracts
    // through e(att_by)/e(att_by_point) and related grouped metadata. This
    // exporter only knows how to serialize one pooled ATT path, so accepting
    // grouped results would silently discard cross-group heterogeneity.
    local _pte_grouped_by ""
    capture local _pte_grouped_by = e(by)
    if _rc == 0 & `"`_pte_grouped_by'"' == "." {
        local _pte_grouped_by ""
    }
    quietly _pte_has_grouped_att_payload
    local _pte_has_grouped_att = r(has_grouped_att)
    local _pte_grouped_payloads `"`r(grouped_payloads)'"'
    if `_pte_has_grouped_att' {
        di as error "{bf:Error}: grouped ATT results are not supported by pte_export"
        if `"`_pte_grouped_by'"' != "" {
            di as error "Current e() results were produced with by()/industry() and contain group-specific ATT paths."
        }
        else {
            di as error "Current e() results still contain grouped ATT payloads even though route metadata are incomplete."
        }
        if `"`_pte_grouped_payloads'"' != "" di as error "Detected grouped payload(s): `macval(_pte_grouped_payloads)'"
        di as error "Exporting pooled e(att) here would silently drop grouped heterogeneity."
        di as error "Re-run pooled pte results for pte_export, or export grouped matrices manually."
        exit 198
    }

    // Extract e() matrices (period columns plus one pooled column).
    tempname ATT ATT_SE ATT_pval ATE ATE_SE ATE_pval Delta Delta_SE Delta_pval

    matrix `ATT' = e(att)
    _pte_export_require_rowvector `ATT' . "e(att)"
    local ncols = colsof(`ATT')
    local nperiods = `ncols' - 1

    // Event-time labels must follow the stored ATT support exactly. Falling
    // back to 0..L-1 silently relabels sparse or otherwise noncanonical
    // dynamic ATT columns and breaks the same e(attperiods) contract used by
    // other postestimation consumers.
    local periodlist ""
    capture confirm matrix e(attperiods)
    if _rc {
        di as error "{bf:Error}: e(attperiods) matrix not found in e()"
        di as error "pte_export requires e(attperiods) to label dynamic ATT periods exactly."
        di as error "Re-run pte so the ATT support matrix is posted before exporting."
        exit 301
    }
    tempname ATTPERIODS
    matrix `ATTPERIODS' = e(attperiods)
    if rowsof(`ATTPERIODS') == 1 & colsof(`ATTPERIODS') != `nperiods' {
        di as error "{bf:Error}: e(att) dimension mismatch with e(attperiods)"
        di as error "Expected colsof(e(attperiods)) = `nperiods', got " colsof(`ATTPERIODS')
        exit 503
    }
    quietly _pte_attperiods_support `ATTPERIODS' `nperiods' "pte_export"
    matrix `ATTPERIODS' = r(periods)
    local periodlist `"`r(periodlist)'"'
    quietly _pte_dynamic_colstripe_contract `ATT' `ATTPERIODS' `nperiods' ///
        "pte_export" "e(att)"

    capture confirm matrix e(att_se)
    local has_se = (_rc == 0)
    if `has_se' {
        matrix `ATT_SE' = e(att_se)
        _pte_export_require_rowvector `ATT_SE' `ncols' "e(att_se)"
        quietly _pte_dynamic_colstripe_contract `ATT_SE' `ATTPERIODS' `nperiods' ///
            "pte_export" "e(att_se)"
        if `show_se' {
            _pte_export_require_bundle `ATT_SE' "e(att_se)" ///
                "pte_export requires nonmissing ATT standard errors for every exported support row and the pooled summary."
        }
    }

    capture confirm matrix e(att_pval)
    local has_att_pval = (_rc == 0)
    if `has_att_pval' {
        matrix `ATT_pval' = e(att_pval)
        _pte_export_require_rowvector `ATT_pval' `ncols' "e(att_pval)"
        quietly _pte_dynamic_colstripe_contract `ATT_pval' `ATTPERIODS' `nperiods' ///
            "pte_export" "e(att_pval)"
        _pte_export_require_bundle `ATT_pval' "e(att_pval)" ///
            "pte_export requires nonmissing ATT p-values for every exported support row and the pooled summary."
    }

    // Keep the parser-level SE intent separate from ATT_SE availability so
    // ATE_count/Delta SE columns can still surface when only those objects
    // are present.
    local has_ate_pval = 0
    local has_delta_pval = 0
    local has_any_pval = `has_att_pval'

    capture confirm matrix e(ate_count)
    local has_ate = (_rc == 0)
    local has_ate_se = 0
    local has_delta_se = 0

    if `has_ate' {
        matrix `ATE' = e(ate_count)
        _pte_export_require_rowvector `ATE' `ncols' "e(ate_count)"
        quietly _pte_dynamic_colstripe_contract `ATE' `ATTPERIODS' `nperiods' ///
            "pte_export" "e(ate_count)"

        capture confirm matrix e(ate_count_se)
        if !_rc {
            local has_ate_se = 1
            matrix `ATE_SE' = e(ate_count_se)
            _pte_export_require_rowvector `ATE_SE' `ncols' "e(ate_count_se)"
            quietly _pte_dynamic_colstripe_contract `ATE_SE' `ATTPERIODS' `nperiods' ///
                "pte_export" "e(ate_count_se)"
            if `show_se' {
                _pte_export_require_bundle `ATE_SE' "e(ate_count_se)" ///
                    "pte_export requires nonmissing ATE{sup:count} standard errors for every exported support row and the pooled summary."
            }
        }

        capture confirm matrix e(ate_count_pval)
        if !_rc {
            local has_ate_pval = 1
            matrix `ATE_pval' = e(ate_count_pval)
            _pte_export_require_rowvector `ATE_pval' `ncols' "e(ate_count_pval)"
            quietly _pte_dynamic_colstripe_contract `ATE_pval' `ATTPERIODS' `nperiods' ///
                "pte_export" "e(ate_count_pval)"
            _pte_export_require_bundle `ATE_pval' "e(ate_count_pval)" ///
                "pte_export requires nonmissing ATE{sup:count} p-values for every exported support row and the pooled summary."
        }

        capture confirm matrix e(delta)
        if !_rc {
            matrix `Delta' = e(delta)
            _pte_export_require_rowvector `Delta' `ncols' "e(delta)"
            quietly _pte_dynamic_colstripe_contract `Delta' `ATTPERIODS' `nperiods' ///
                "pte_export" "e(delta)"
        }

        capture confirm matrix e(delta_se)
        if !_rc {
            local has_delta_se = 1
            matrix `Delta_SE' = e(delta_se)
            _pte_export_require_rowvector `Delta_SE' `ncols' "e(delta_se)"
            quietly _pte_dynamic_colstripe_contract `Delta_SE' `ATTPERIODS' `nperiods' ///
                "pte_export" "e(delta_se)"
            if `show_se' {
                _pte_export_require_bundle `Delta_SE' "e(delta_se)" ///
                    "pte_export requires nonmissing Delta standard errors for every exported support row and the pooled summary."
            }
        }

        capture confirm matrix e(delta_pval)
        if !_rc {
            local has_delta_pval = 1
            matrix `Delta_pval' = e(delta_pval)
            _pte_export_require_rowvector `Delta_pval' `ncols' "e(delta_pval)"
            quietly _pte_dynamic_colstripe_contract `Delta_pval' `ATTPERIODS' `nperiods' ///
                "pte_export" "e(delta_pval)"
            _pte_export_require_bundle `Delta_pval' "e(delta_pval)" ///
                "pte_export requires nonmissing Delta p-values for every exported support row and the pooled summary."
        }
    }

    local has_any_pval = (`has_att_pval' | `has_ate_pval' | `has_delta_pval')

    // The exporter writes one row for every stored support period plus the
    // pooled summary row, so supported ATT / ATE_count cells must be realized
    // rather than missing placeholders.
    forvalues _pte_col = 1/`ncols' {
        if missing(`ATT'[1, `_pte_col']) {
            di as error "{bf:Error}: e(att) contains missing values on the exported support."
            di as error "pte_export requires nonmissing ATT values for every stored event-time row and the pooled summary."
            exit 198
        }
        if `has_ate' {
            if missing(`ATE'[1, `_pte_col']) {
                di as error "{bf:Error}: e(ate_count) contains missing values on the exported support."
                di as error "pte_export requires nonmissing ATE{sup:count} values for every stored event-time row and the pooled summary."
                exit 198
            }
        }
    }

    // Star thresholds are p-value cutoffs in ascending order:
    //   star1 => ***, star2 => **, star3 => *
    tokenize `stars'
    local star1 = `1'  // *** threshold (e.g., 0.01)
    local star2 = `2'  // ** threshold (e.g., 0.05)
    local star3 = `3'  // * threshold (e.g., 0.10)
    if !(`star1' > 0 & `star1' < 1 & ///
          `star2' > 0 & `star2' < 1 & ///
          `star3' > 0 & `star3' < 1) {
        di as error "{bf:Error}: stars() thresholds must be strictly between 0 and 1"
        exit 198
    }
    if !(`star1' < `star2' & `star2' < `star3') {
        di as error "{bf:Error}: stars() thresholds must be strictly increasing (star1 < star2 < star3)"
        exit 198
    }

    // Bootstrap rep-count metadata follows the same canonical fallback used by
    // the live display path: main-command producers publish e(bootstrap),
    // some bootstrap helpers also publish e(breps) or e(nboot).
    local nboot = .
    capture confirm scalar e(bootstrap)
    if _rc == 0 {
        local nboot = e(bootstrap)
    }
    else {
        capture confirm scalar e(breps)
        if _rc == 0 {
            local nboot = e(breps)
        }
        else {
            capture confirm scalar e(nboot)
            if _rc == 0 {
                local nboot = e(nboot)
            }
        }
    }
    if !missing(`nboot') & `nboot' <= 0 {
        local nboot = .
    }

    // Dispatch to format-specific writer.

    if "`format'" == "latex" {
        _pte_export_latex using "`using'", ///
            ncols(`ncols') nperiods(`nperiods') ///
            has_se(`has_se') has_att_pval(`has_att_pval') has_ate(`has_ate') ///
            has_ate_pval(`has_ate_pval') has_delta_pval(`has_delta_pval') has_any_pval(`has_any_pval') ///
            has_ate_se(`has_ate_se') has_delta_se(`has_delta_se') show_se(`show_se') decimals(`decimals') ///
            periodlist(`periodlist') ///
            star1(`star1') star2(`star2') star3(`star3') ///
            nboot(`nboot') ///
            title(`"`title'"') note(`"`note'"') ///
            `replace'
    }
    else if "`format'" == "xlsx" {
        _pte_export_excel using "`using'", ///
            ncols(`ncols') nperiods(`nperiods') ///
            has_se(`has_se') has_att_pval(`has_att_pval') has_ate(`has_ate') ///
            has_ate_pval(`has_ate_pval') has_delta_pval(`has_delta_pval') has_any_pval(`has_any_pval') ///
            has_ate_se(`has_ate_se') has_delta_se(`has_delta_se') show_se(`show_se') decimals(`decimals') periodlist(`periodlist') nboot(`nboot') ///
            `replace'
    }
    else if "`format'" == "csv" {
        _pte_export_csv using "`using'", ///
            ncols(`ncols') nperiods(`nperiods') ///
            has_se(`has_se') has_att_pval(`has_att_pval') has_ate(`has_ate') ///
            has_ate_pval(`has_ate_pval') has_delta_pval(`has_delta_pval') has_any_pval(`has_any_pval') ///
            has_ate_se(`has_ate_se') has_delta_se(`has_delta_se') show_se(`show_se') decimals(`decimals') periodlist(`periodlist') nboot(`nboot') ///
            `replace'
    }
    else {
        di as error "{bf:Error}: Unknown format '`format''"
        di as error "Supported formats: latex, xlsx, csv"
        exit 198
    }

    // r(): echo the export target and basic table dimensions.
    return local filename "`using'"
    return local format "`format'"
    return scalar n_periods = `nperiods'

end


// Internal: LaTeX writer for ATT and optional ATE_count/Delta tables.

capture program drop _pte_export_require_rowvector
program define _pte_export_require_rowvector
    version 14.0

    args matname expected_cols surfacename

    if rowsof(`matname') != 1 {
        di as error "{bf:Error}: `surfacename' must be a 1 x K row vector"
        exit 503
    }

    if "`expected_cols'" != "." {
        if colsof(`matname') != `expected_cols' {
            di as error "{bf:Error}: e(att) and `surfacename' dimensions are inconsistent"
            di as error "Expected colsof(`surfacename') = `expected_cols', got " colsof(`matname')
            exit 503
        }
    }
end

capture program drop _pte_export_resolve_delta
program define _pte_export_resolve_delta
    version 14.0

    args delta_name att_name ate_name expected_cols

    local use_fallback = 0
    capture matrix `delta_name' = e(delta)
    if _rc {
        local use_fallback = 1
    }
    else if rowsof(`delta_name') != 1 | colsof(`delta_name') != `expected_cols' {
        local use_fallback = 1
    }
    else {
        forvalues _pte_col = 1/`expected_cols' {
            if missing(`delta_name'[1, `_pte_col']) {
                local use_fallback = 1
                continue, break
            }
        }
    }

    if `use_fallback' {
        matrix `delta_name' = `att_name' - `ate_name'
    }
end

capture program drop _pte_export_require_bundle
program define _pte_export_require_bundle
    version 14.0

    args matname surfacename errmsg

    local _pte_bundle_cols = colsof(`matname')
    forvalues _pte_col = 1/`_pte_bundle_cols' {
        if missing(`matname'[1, `_pte_col']) {
            di as error "{bf:Error}: `surfacename' contains missing values on the exported support."
            di as error `"`errmsg'"'
            exit 198
        }
    }
end

capture program drop _pte_export_latex
program define _pte_export_latex
    version 14.0

    syntax using/ , ncols(integer) nperiods(integer) ///
        has_se(integer) has_att_pval(integer) has_ate(integer) ///
        has_ate_pval(integer) has_delta_pval(integer) has_any_pval(integer) ///
        has_ate_se(integer) has_delta_se(integer) show_se(integer) decimals(integer) periodlist(string asis) ///
        star1(real) star2(real) star3(real) ///
        nboot(real) ///
        [title(string) note(string) REPLACE]

    // Read the same e() matrices as the caller; keep this subprogram stateless.
    tempname ATT ATT_SE ATT_pval ATE ATE_SE ATE_pval Delta Delta_SE Delta_pval
    matrix `ATT' = e(att)

    if `has_se' {
        matrix `ATT_SE' = e(att_se)
    }
    if `has_att_pval' {
        matrix `ATT_pval' = e(att_pval)
    }
    if `has_ate' {
        matrix `ATE' = e(ate_count)
        capture matrix `ATE_SE' = e(ate_count_se)
        if `has_ate_pval' capture matrix `ATE_pval' = e(ate_count_pval)
        _pte_export_resolve_delta `Delta' `ATT' `ATE' `ncols'
        capture matrix `Delta_SE' = e(delta_se)
        if `has_delta_pval' capture matrix `Delta_pval' = e(delta_pval)
    }

    // Numeric formatting: keep column widths stable across decimals().
    local fmt "%`=`decimals'+4'.`decimals'f"
    local fmt_se "%`=`decimals'+3'.`decimals'f"
    local _tex_dollar : display char(36)
    local _tex_ell "\ell"
    local _tex_ate "ATE^{count}"
    local _tex_delta "\Delta"
    local _tex_lt "<"
    // Default title for standalone use.
    if `"`title'"' == "" {
        local title "Treatment Effects on Productivity"
    }
    local _pte_tex_bs = char(92)
    local _pte_tex_dollar = char(36)
    local title_tex `"`title'"'
    local title_tex : subinstr local title_tex "&"  "`_pte_tex_bs'&",  all
    local title_tex : subinstr local title_tex "%"  "`_pte_tex_bs'%",  all
    local title_tex : subinstr local title_tex "`_pte_tex_dollar'"  "`_pte_tex_bs'`_pte_tex_dollar'",  all
    local title_tex : subinstr local title_tex "#"  "`_pte_tex_bs'#",  all
    local title_tex : subinstr local title_tex "_"  "`_pte_tex_bs'_",  all
    local note_tex `"`note'"'
    if `"`note_tex'"' != "" {
        local note_tex : subinstr local note_tex "&"  "`_pte_tex_bs'&",  all
        local note_tex : subinstr local note_tex "%"  "`_pte_tex_bs'%",  all
        local note_tex : subinstr local note_tex "`_pte_tex_dollar'"  "`_pte_tex_bs'`_pte_tex_dollar'",  all
        local note_tex : subinstr local note_tex "#"  "`_pte_tex_bs'#",  all
        local note_tex : subinstr local note_tex "_"  "`_pte_tex_bs'_",  all
    }

    // Open/overwrite is controlled by replace.
    tempname fh
    file open `fh' using "`using'", write `replace'

    // Table header and column layout.
    file write `fh' "\begin{table}[htbp]" _n
    file write `fh' "\centering" _n
    file write `fh' `"\caption{`title_tex'}"' _n
    file write `fh' "\begin{threeparttable}" _n

    // Column spec depends on whether ATE^count is available and whether
    // standard errors are shown.
    local show_att_se = (`show_se' & `has_se')
    local show_ate_se = (`show_se' & `has_ate_se')
    local show_delta_se = (`show_se' & `has_delta_se')

    local any_se = (`show_att_se' | `show_ate_se' | `show_delta_se')
    local colspec "lc"
    if `show_att_se' {
        local colspec "`colspec'c"
    }
    if `has_ate' {
        local colspec "`colspec'cc"
        if `show_ate_se' {
            local colspec "`colspec'c"
        }
        if `show_delta_se' {
            local colspec "`colspec'c"
        }
    }
    file write `fh' "\begin{tabular}{`colspec'}" _n

    file write `fh' "\hline\hline" _n

    // Column headers. Write math tokens in separate segments so Stata never
    // interprets "$ATE" as a global-macro expansion while assembling LaTeX.
    if `has_ate' {
        file write `fh' "Period (" "`macval(_tex_dollar)'" "\ell" "`macval(_tex_dollar)'" ") & ATT"
        if `show_att_se' {
            file write `fh' " & SE(ATT)"
        }
        file write `fh' " & " "`macval(_tex_dollar)'" "ATE^{count}" "`macval(_tex_dollar)'"
        if `show_ate_se' {
            file write `fh' " & SE(" "`macval(_tex_dollar)'" "ATE^{count}" "`macval(_tex_dollar)'" ")"
        }
        file write `fh' " & " "`macval(_tex_dollar)'" "\Delta" "`macval(_tex_dollar)'"
        if `show_delta_se' {
            file write `fh' " & SE(" "`macval(_tex_dollar)'" "\Delta" "`macval(_tex_dollar)'" ")"
        }
        file write `fh' " \\" _n
    }
    else {
        file write `fh' "Period (" "`macval(_tex_dollar)'" "\ell" "`macval(_tex_dollar)'" ") & ATT"
        if `show_att_se' {
            file write `fh' " & SE(ATT)"
        }
        file write `fh' " \\" _n
    }
    file write `fh' "\hline" _n

    // Data rows: periods 0..L, with the pooled column handled below.
    forvalues col = 1/`nperiods' {
        local ell : word `col' of `periodlist'

        // Stars are computed from p-values when available.
        local att_val = `ATT'[1, `col']
        local att_stars ""
        if `has_att_pval' {
            local pv = `ATT_pval'[1, `col']
            if `pv' < `star1' local att_stars "***"
            else if `pv' < `star2' local att_stars "**"
            else if `pv' < `star3' local att_stars "*"
        }

        // SEs are included only when both show_se and the corresponding matrix exist.
        local att_se_str ""
        if `show_att_se' {
            local att_se_val = `ATT_SE'[1, `col']
            local att_se_str : di `fmt_se' `att_se_val'
            local att_se_str = strtrim("`att_se_str'")
        }

        if `has_ate' {
            // Optional ATE_count and Delta blocks follow the same pattern.
            local ate_val = `ATE'[1, `col']
            local ate_stars ""
            if `has_ate_pval' {
                local pv = `ATE_pval'[1, `col']
                if `pv' < `star1' local ate_stars "***"
                else if `pv' < `star2' local ate_stars "**"
                else if `pv' < `star3' local ate_stars "*"
            }

            // ATE_count SE (if available).
            local ate_se_str ""
            capture local ate_se_val = `ATE_SE'[1, `col']
            if _rc == 0 & `show_ate_se' {
                local ate_se_str : di `fmt_se' `ate_se_val'
                local ate_se_str = strtrim("`ate_se_str'")
            }

            // Delta value and stars (if available).
            local delta_val = `Delta'[1, `col']
            local delta_stars ""
            if `has_delta_pval' {
                local pv = `Delta_pval'[1, `col']
                if `pv' < `star1' local delta_stars "***"
                else if `pv' < `star2' local delta_stars "**"
                else if `pv' < `star3' local delta_stars "*"
            }

            // Write row.
            local att_str : di `fmt' `att_val'
            local att_str = strtrim("`att_str'")
            local ate_str : di `fmt' `ate_val'
            local ate_str = strtrim("`ate_str'")
            local delta_str : di `fmt' `delta_val'
            local delta_str = strtrim("`delta_str'")
            local delta_se_str ""
            capture local delta_se_val = `Delta_SE'[1, `col']
            if _rc == 0 & `show_delta_se' {
                local delta_se_str : di `fmt_se' `delta_se_val'
                local delta_se_str = strtrim("`delta_se_str'")
            }

            local _tex_row `"`ell' & `att_str'`att_stars'"'
            if `show_att_se' {
                local _tex_row `"`_tex_row' & (`att_se_str')"'
            }
            local _tex_row `"`_tex_row' & `ate_str'`ate_stars'"'
            if `show_ate_se' {
                local _tex_row `"`_tex_row' & (`ate_se_str')"'
            }
            local _tex_row `"`_tex_row' & `delta_str'`delta_stars'"'
            if `show_delta_se' {
                local _tex_row `"`_tex_row' & (`delta_se_str')"'
            }
            local _tex_row `"`_tex_row' \\"'
            file write `fh' `"`_tex_row'"' _n
        }
        else {
            // ATT-only table.
            local att_str : di `fmt' `att_val'
            local att_str = strtrim("`att_str'")

            if `show_att_se' {
                file write `fh' "`ell' & `att_str'`att_stars' & (`att_se_str') \\" _n
            }
            else {
                file write `fh' "`ell' & `att_str'`att_stars' \\" _n
            }
        }
    }

    // Pooled column (last column of each matrix).
    file write `fh' "\hline" _n

    local col = `ncols'
    local att_val = `ATT'[1, `col']
    local att_stars ""
    if `has_att_pval' {
        local pv = `ATT_pval'[1, `col']
        if `pv' < `star1' local att_stars "***"
        else if `pv' < `star2' local att_stars "**"
        else if `pv' < `star3' local att_stars "*"
    }
    local att_str : di `fmt' `att_val'
    local att_str = strtrim("`att_str'")

    local att_se_str ""
    if `show_att_se' {
        local att_se_val = `ATT_SE'[1, `col']
        local att_se_str : di `fmt_se' `att_se_val'
        local att_se_str = strtrim("`att_se_str'")
    }

    if `has_ate' {
        local ate_val = `ATE'[1, `col']
        local ate_stars ""
        if `has_ate_pval' {
            local pv = `ATE_pval'[1, `col']
            if `pv' < `star1' local ate_stars "***"
            else if `pv' < `star2' local ate_stars "**"
            else if `pv' < `star3' local ate_stars "*"
        }
        local ate_str : di `fmt' `ate_val'
        local ate_str = strtrim("`ate_str'")

        local ate_se_str ""
        capture local ate_se_val = `ATE_SE'[1, `col']
        if _rc == 0 & `show_ate_se' {
            local ate_se_str : di `fmt_se' `ate_se_val'
            local ate_se_str = strtrim("`ate_se_str'")
        }

        local delta_val = `Delta'[1, `col']
        local delta_stars ""
        if `has_delta_pval' {
            local pv = `Delta_pval'[1, `col']
            if `pv' < `star1' local delta_stars "***"
            else if `pv' < `star2' local delta_stars "**"
            else if `pv' < `star3' local delta_stars "*"
        }
        local delta_str : di `fmt' `delta_val'
        local delta_str = strtrim("`delta_str'")
        local delta_se_str ""
        capture local delta_se_val = `Delta_SE'[1, `col']
        if _rc == 0 & `show_delta_se' {
            local delta_se_str : di `fmt_se' `delta_se_val'
            local delta_se_str = strtrim("`delta_se_str'")
        }

        local _tex_row `"Pooled & `att_str'`att_stars'"'
        if `show_att_se' {
            local _tex_row `"`_tex_row' & (`att_se_str')"'
        }
        local _tex_row `"`_tex_row' & `ate_str'`ate_stars'"'
        if `show_ate_se' {
            local _tex_row `"`_tex_row' & (`ate_se_str')"'
        }
        local _tex_row `"`_tex_row' & `delta_str'`delta_stars'"'
        if `show_delta_se' {
            local _tex_row `"`_tex_row' & (`delta_se_str')"'
        }
        local _tex_row `"`_tex_row' \\"'
        file write `fh' `"`_tex_row'"' _n
    }
    else {
        if `show_att_se' {
            file write `fh' "Pooled & `att_str'`att_stars' & (`att_se_str') \\" _n
        }
        else {
            file write `fh' "Pooled & `att_str'`att_stars' \\" _n
        }
    }

    // Table footer.
    file write `fh' "\hline\hline" _n
    file write `fh' "\end{tabular}" _n

    // Notes: caller-supplied note() is appended ahead of automatic metadata.
    local write_notes = 0
    if `"`note'"' != "" {
        local write_notes = 1
    }
    else if `any_se' | (`nboot' < .) | `has_any_pval' {
        local write_notes = 1
    }

    if `write_notes' {
        file write `fh' "\begin{tablenotes}" _n
        file write `fh' "\small" _n

        if `"`note'"' != "" {
            file write `fh' `"\item `note_tex'"' _n
        }

        local default_note ""
        if `any_se' {
            local default_note "\item Standard errors in parentheses."
        }
        if `nboot' < . {
            if "`default_note'" != "" {
                local default_note "`default_note' Bootstrap B=`nboot'."
            }
            else {
                local default_note "\item Bootstrap B=`nboot'."
            }
        }
        if "`default_note'" != "" {
            file write `fh' "`default_note'" _n
        }
        if `has_any_pval' {
            local _tex_sig_note `"\item * p`macval(_tex_dollar)'<`macval(_tex_dollar)'`star3', ** p`macval(_tex_dollar)'<`macval(_tex_dollar)'`star2', *** p`macval(_tex_dollar)'<`macval(_tex_dollar)'`star1'"'
            file write `fh' `"`macval(_tex_sig_note)'"' _n
        }

        file write `fh' "\end{tablenotes}" _n
    }
    file write `fh' "\end{threeparttable}" _n
    file write `fh' "\end{table}" _n

    file close `fh'

    di as text "LaTeX table exported to: `using'"

end


// Internal: XLSX writer via putexcel (keeps numeric values, no star rendering).

capture program drop _pte_export_excel
program define _pte_export_excel
    version 14.0

    syntax using/ , ncols(integer) nperiods(integer) ///
        has_se(integer) has_att_pval(integer) has_ate(integer) ///
        has_ate_pval(integer) has_delta_pval(integer) has_any_pval(integer) ///
        has_ate_se(integer) has_delta_se(integer) show_se(integer) decimals(integer) periodlist(string asis) nboot(real) [REPLACE]

    // Read e() matrices; missing optional matrices are handled via capture.
    tempname ATT ATT_SE ATT_pval ATE ATE_SE ATE_pval Delta Delta_SE Delta_pval
    matrix `ATT' = e(att)
    if `has_se' matrix `ATT_SE' = e(att_se)
    if `has_att_pval' matrix `ATT_pval' = e(att_pval)
    if `has_ate' {
        matrix `ATE' = e(ate_count)
        capture matrix `ATE_SE' = e(ate_count_se)
        if `has_ate_pval' capture matrix `ATE_pval' = e(ate_count_pval)
        _pte_export_resolve_delta `Delta' `ATT' `ATE' `ncols'
        capture matrix `Delta_SE' = e(delta_se)
        if `has_delta_pval' capture matrix `Delta_pval' = e(delta_pval)
    }

    local round_unit = 10^(-`decimals')
    local pval_round_unit = 1e-6

    local show_att_se = (`show_se' & `has_se')
    local show_ate_se = (`show_se' & `has_ate_se')
    local show_delta_se = (`show_se' & `has_delta_se')

    // putexcel requires an active workbook handle.
    quietly putexcel set "`using'", `replace'

    // Header row depends on which optional inference objects are truly available.
    local nextcol = 3
    local col_att_se ""
    local col_att_pval ""
    local col_ate ""
    local col_ate_se ""
    local col_ate_pval ""
    local col_delta ""
    local col_delta_se ""
    local col_delta_pval ""

    if `show_att_se' {
        local col_att_se = char(64 + `nextcol')
        local ++nextcol
    }
    if `has_att_pval' {
        local col_att_pval = char(64 + `nextcol')
        local ++nextcol
    }
    if `has_ate' {
        local col_ate = char(64 + `nextcol')
        local ++nextcol
        if `show_ate_se' {
            local col_ate_se = char(64 + `nextcol')
            local ++nextcol
        }
        if `has_ate_pval' {
            local col_ate_pval = char(64 + `nextcol')
            local ++nextcol
        }
        local col_delta = char(64 + `nextcol')
        local ++nextcol
        if `show_delta_se' {
            local col_delta_se = char(64 + `nextcol')
            local ++nextcol
        }
        if `has_delta_pval' {
            local col_delta_pval = char(64 + `nextcol')
            local ++nextcol
        }
    }

    quietly putexcel A1 = ("Period")
    quietly putexcel B1 = ("ATT")
    if "`col_att_se'" != "" quietly putexcel `col_att_se'1 = ("ATT_SE")
    if "`col_att_pval'" != "" quietly putexcel `col_att_pval'1 = ("ATT_pval")
    if "`col_ate'" != "" quietly putexcel `col_ate'1 = ("ATE_count")
    if "`col_ate_se'" != "" quietly putexcel `col_ate_se'1 = ("ATE_count_SE")
    if "`col_ate_pval'" != "" quietly putexcel `col_ate_pval'1 = ("ATE_count_pval")
    if "`col_delta'" != "" quietly putexcel `col_delta'1 = ("Delta")
    if "`col_delta_se'" != "" quietly putexcel `col_delta_se'1 = ("Delta_SE")
    if "`col_delta_pval'" != "" quietly putexcel `col_delta_pval'1 = ("Delta_pval")

    // Data rows include periods 0..L and a pooled row.
    forvalues col = 1/`ncols' {
        local row = `col' + 1
        if `col' <= `nperiods' {
            local ell : word `col' of `periodlist'
            quietly putexcel A`row' = (`ell')
        }
        else {
            quietly putexcel A`row' = ("Pooled")
        }

        quietly putexcel B`row' = (round(`ATT'[1, `col'], `round_unit'))
        if "`col_att_se'" != "" quietly putexcel `col_att_se'`row' = (round(`ATT_SE'[1, `col'], `round_unit'))
        if "`col_att_pval'" != "" quietly putexcel `col_att_pval'`row' = (round(`ATT_pval'[1, `col'], `pval_round_unit'))

        if `has_ate' {
            quietly putexcel `col_ate'`row' = (round(`ATE'[1, `col'], `round_unit'))
            if "`col_ate_se'" != "" capture quietly putexcel `col_ate_se'`row' = (round(`ATE_SE'[1, `col'], `round_unit'))
            if "`col_ate_pval'" != "" capture quietly putexcel `col_ate_pval'`row' = (round(`ATE_pval'[1, `col'], `pval_round_unit'))
            quietly putexcel `col_delta'`row' = (round(`Delta'[1, `col'], `round_unit'))
            if "`col_delta_se'" != "" capture quietly putexcel `col_delta_se'`row' = (round(`Delta_SE'[1, `col'], `round_unit'))
            if "`col_delta_pval'" != "" capture quietly putexcel `col_delta_pval'`row' = (round(`Delta_pval'[1, `col'], `pval_round_unit'))
        }
    }

    // Metadata.
    if `nboot' < . {
        local metarow = `ncols' + 3
        quietly putexcel A`metarow' = ("Bootstrap iterations")
        quietly putexcel B`metarow' = (`nboot')
    }

    quietly putexcel clear

    di as text "Excel table exported to: `using'"

end


// Internal: CSV writer; missing optional matrices are written as ".".

capture program drop _pte_export_csv
program define _pte_export_csv
    version 14.0

    syntax using/ , ncols(integer) nperiods(integer) ///
        has_se(integer) has_att_pval(integer) has_ate(integer) ///
        has_ate_pval(integer) has_delta_pval(integer) has_any_pval(integer) ///
        has_ate_se(integer) has_delta_se(integer) show_se(integer) decimals(integer) periodlist(string asis) nboot(real) [REPLACE]

    // Read e() matrices; optional blocks are guarded with capture.
    tempname ATT ATT_SE ATT_pval ATE ATE_SE ATE_pval Delta Delta_SE Delta_pval
    matrix `ATT' = e(att)
    if `has_se' matrix `ATT_SE' = e(att_se)
    if `has_att_pval' matrix `ATT_pval' = e(att_pval)
    if `has_ate' {
        matrix `ATE' = e(ate_count)
        capture matrix `ATE_SE' = e(ate_count_se)
        if `has_ate_pval' capture matrix `ATE_pval' = e(ate_count_pval)
        _pte_export_resolve_delta `Delta' `ATT' `ATE' `ncols'
        capture matrix `Delta_SE' = e(delta_se)
        if `has_delta_pval' capture matrix `Delta_pval' = e(delta_pval)
    }

    local fmt "%`=`decimals'+4'.`decimals'f"
    local show_att_se = (`show_se' & `has_se')
    local show_ate_se = (`show_se' & `has_ate_se')
    local show_delta_se = (`show_se' & `has_delta_se')

    tempname fh
    file open `fh' using "`using'", write `replace'

    // Header varies with which optional inference objects are truly available.
    local header "period,att"
    if `show_att_se' local header "`header',att_se"
    if `has_att_pval' local header "`header',att_pval"
    if `has_ate' {
        local header "`header',ate_count"
        if `show_ate_se' local header "`header',ate_count_se"
        if `has_ate_pval' local header "`header',ate_count_pval"
        local header "`header',delta"
        if `show_delta_se' local header "`header',delta_se"
        if `has_delta_pval' local header "`header',delta_pval"
    }
    file write `fh' "`header'" _n

    // Data rows include periods 0..L and a pooled row.
    forvalues col = 1/`ncols' {
        // Period label.
        if `col' <= `nperiods' {
            local ell : word `col' of `periodlist'
            local period_str "`ell'"
        }
        else {
            local period_str "pooled"
        }

        // ATT values.
        local att_str : di `fmt' `ATT'[1, `col']
        local att_str = strtrim("`att_str'")

        local att_se_str "."
        if `show_att_se' {
            local att_se_str : di `fmt' `ATT_SE'[1, `col']
            local att_se_str = strtrim("`att_se_str'")
        }

        local att_pv_str "."
        if `has_att_pval' {
            local att_pv_str : di %8.6f `ATT_pval'[1, `col']
            local att_pv_str = strtrim("`att_pv_str'")
        }

        if `has_ate' {
            local ate_str : di `fmt' `ATE'[1, `col']
            local ate_str = strtrim("`ate_str'")

            local ate_se_str "."
            capture local v = `ATE_SE'[1, `col']
            if `show_ate_se' & _rc == 0 {
                local ate_se_str : di `fmt' `v'
                local ate_se_str = strtrim("`ate_se_str'")
            }

            local ate_pv_str "."
            if `has_ate_pval' {
                local v = `ATE_pval'[1, `col']
                local ate_pv_str : di %8.6f `v'
                local ate_pv_str = strtrim("`ate_pv_str'")
            }

            local delta_str "."
            capture local v = `Delta'[1, `col']
            if _rc == 0 {
                local delta_str : di `fmt' `v'
                local delta_str = strtrim("`delta_str'")
            }

            local delta_se_str "."
            capture local v = `Delta_SE'[1, `col']
            if `show_delta_se' & _rc == 0 {
                local delta_se_str : di `fmt' `v'
                local delta_se_str = strtrim("`delta_se_str'")
            }

            local delta_pv_str "."
            if `has_delta_pval' {
                local v = `Delta_pval'[1, `col']
                local delta_pv_str : di %8.6f `v'
                local delta_pv_str = strtrim("`delta_pv_str'")
            }

            local row "`period_str',`att_str'"
            if `show_att_se' local row "`row',`att_se_str'"
            if `has_att_pval' local row "`row',`att_pv_str'"
            local row "`row',`ate_str'"
            if `show_ate_se' local row "`row',`ate_se_str'"
            if `has_ate_pval' local row "`row',`ate_pv_str'"
            local row "`row',`delta_str'"
            if `show_delta_se' local row "`row',`delta_se_str'"
            if `has_delta_pval' local row "`row',`delta_pv_str'"
            file write `fh' "`row'" _n
        }
        else {
            local row "`period_str',`att_str'"
            if `show_att_se' local row "`row',`att_se_str'"
            if `has_att_pval' local row "`row',`att_pv_str'"
            file write `fh' "`row'" _n
        }
    }

    file close `fh'

    di as text "CSV table exported to: `using'"

end
