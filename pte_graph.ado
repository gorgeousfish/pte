*! pte_graph.ado
*! Route public graph requests to the appropriate internal graph module.

version 14.0
program define pte_graph, rclass
    version 14.0
    
    // Preserve the raw by() token so the public router can reject Stata's
    // silent abbreviation binding for grouping variables.
    local _pte_by_literal ""

    // Preserve whether refline() / legend() were explicitly supplied so the
    // public conflict checks do not depend on parsed sentinel or empty-string
    // representations.
    local _pte_optscan `"`0'"'
    local _pte_q1 = strpos(`"`_pte_optscan'"', char(34))
    while `_pte_q1' > 0 {
        local _pte_q2 = strpos(substr(`"`_pte_optscan'"', `=`_pte_q1' + 1', .), char(34))
        if `_pte_q2' <= 0 {
            continue, break
        }
        local _pte_q2 = `_pte_q1' + `_pte_q2'
        local _pte_optscan = substr(`"`_pte_optscan'"', 1, `=`_pte_q1' - 1') + ///
            substr(`"`_pte_optscan'"', `=`_pte_q2' + 1', .)
        local _pte_q1 = strpos(`"`_pte_optscan'"', char(34))
    }
    if regexm(lower(`"`_pte_optscan'"'), "(^|[ ,])by[(]([^)]*)[)]") {
        local _pte_by_literal `"`=regexs(2)'"'
        local _pte_by_literal = lower(strtrim(`"`_pte_by_literal'"'))
    }
    local _pte_has_save = regexm(lower(`"`_pte_optscan'"'), "(^|[ ,])sav(e)[ ]*[(]")
    local _pte_has_refline = regexm(lower(`"`_pte_optscan'"'), "(^|[ ,])refl(i(n(e)?)?)?[(]")
    local _pte_has_legend = regexm(lower(`"`_pte_optscan'"'), "(^|[ ,])leg(e(n(d)?)?)?[(]")
    // Match the minimum legal ALpha() abbreviation (`al()`) so explicit
    // alpha payloads are validated and forwarded consistently.
    local _pte_has_alpha = regexm(lower(`"`_pte_optscan'"'), "(^|[ ,])al(p(h(a)?)?)?[(]")
    local _pte_has_currentlawchecked = regexm(lower(`"`_pte_optscan'"'), "(^|[ ,])currentlawchecked($|[ ,])")

    syntax [, TT CATT ATT COMPare HETerogeneity SCATter ///
              EVOlution DIAGnose COMBine BY(name) ///
              /// Counterfactual graph types
              COMPare_cf ATT_dynamic ATE_count_dynamic ///
              TT_distribution EPS0_diagnostic ///
              /// Backward-compatible public aliases
              TYPE(string) SAVing(string) CI ///
              /// Style options passed through to the selected graph worker
              PReset(string) SCHeme(string) ///
              LColor(string) LWidth(string) LPattern(string) ///
              MSymbol(string) MSize(string) MColor(string) MFColor(string) ///
              TItle(string) XTItle(string) YTItle(string) ///
              SUBtitle(string) NOTE(string) ///
              LEGend(string) LEGENDPos(integer -1) ///
              LEGENDCols(integer -1) LEGENDRing(integer -1) NOLEGend ///
              XLine(string) YLine(string) ///
              REFLine(real -999) NOREFLine ///
              BGColor(string) GRID NOGRID GRIDStyle(string) ///
              ALpha(integer 100) ///
              *]
    
    // by()-wrapper families accept combine as a layout request rather than a
    // second graph-family selector. Outside that route, combine remains its
    // own public graph family.
    local _pte_by_supported_legacy = 0
    local _pte_noncombine_count = 0
    local _pte_noncombine_selected ""
    foreach gtype in tt catt att compare heterogeneity scatter evolution diagnose compare_cf att_dynamic ate_count_dynamic tt_distribution eps0_diagnostic {
        if "``gtype''" != "" {
            local _pte_noncombine_count = `_pte_noncombine_count' + 1
            local _pte_noncombine_selected "`gtype'"
        }
    }

    local _pte_by_layout_combine = 0
    if "`by'" != "" & "`combine'" != "" {
        local _pte_by_supported_legacy = inlist("`_pte_noncombine_selected'", ///
            "tt", "catt", "compare", "scatter", "evolution", "diagnose")
        if `_pte_noncombine_count' == 0 {
            local _pte_by_layout_combine = 1
        }
        else if `_pte_noncombine_count' == 1 & `_pte_by_supported_legacy' {
            local _pte_by_layout_combine = 1
        }
    }

    // Exactly one graph family can be selected per call.
    if "`selected'" == "" {
        local n_types = 0
        foreach gtype in tt catt att compare heterogeneity scatter evolution diagnose combine compare_cf att_dynamic ate_count_dynamic tt_distribution eps0_diagnostic {
            if "`gtype'" == "combine" & `_pte_by_layout_combine' {
                continue
            }
            if "``gtype''" != "" {
                local n_types = `n_types' + 1
                local selected "`gtype'"
            }
        }
    }
    
    // Legacy type() aliases used in the long-form manual are normalized here
    // so the public router, not the downstream worker syntax, owns backward
    // compatibility for graph-family selection.
    local _pte_type_norm = lower(strtrim(`"`type'"'))
    local _pte_type_selected ""
    local _pte_diag_type_alias ""
    if "`_pte_type_norm'" == "eps0_diag" {
        local _pte_type_norm "eps0_diagnostic"
    }
    if "`_pte_type_norm'" == "density" {
        local _pte_type_norm "kdensity"
    }

    local _pte_type_family_aliases "tt catt att compare heterogeneity scatter evolution diagnose combine compare_cf att_dynamic ate_count_dynamic tt_distribution eps0_diagnostic"
    local _pte_type_diag_aliases "cdf kdensity eps0_byyear diff_omega0 eps0_treat_control placebo omega_density"

    if `: list _pte_type_norm in _pte_type_family_aliases' {
        local _pte_type_selected "`_pte_type_norm'"
    }
    else if `: list _pte_type_norm in _pte_type_diag_aliases' {
        local _pte_type_selected "diagnose"
        local _pte_diag_type_alias "`_pte_type_norm'"
    }

    if "`_pte_type_selected'" != "" {
        if `n_types' == 0 {
            local selected "`_pte_type_selected'"
            local n_types = 1
        }
        else if "`selected'" != "`_pte_type_selected'" {
            di as error "{bf:Error}: type(`type') conflicts with the selected graph family."
            di as error "Choose one graph family, either through the family option or the legacy type() alias."
            exit 198
        }
    }
    else if "`_pte_type_norm'" != "" {
        di as error "{bf:Error}: unsupported type(`type') alias."
        di as error "Use a graph family such as att or evolution, or use diagnose type(cdf|kdensity|eps0_byyear|diff_omega0|eps0_treat_control|placebo|omega_density)."
        exit 198
    }

    // Keep the common postestimation graph as the implicit default.
    if `n_types' == 0 {
        local selected "att"
    }
    
    // Reject ambiguous graph routing.
    if `n_types' > 1 {
        di as error "{bf:Error}: Only one graph type can be specified at a time."
        di as error "Choose one of: tt, catt, att, compare, heterogeneity, scatter, evolution, diagnose, combine, compare_cf, att_dynamic, ate_count_dynamic, tt_distribution, eps0_diagnostic"
        exit 198
    }

    // Public router style flags must remain unambiguous before they reach
    // worker-specific graph builders.
    if "`grid'" != "" & "`nogrid'" != "" {
        di as error "{bf:Error}: grid and nogrid cannot be combined."
        di as error "Choose either grid or nogrid."
        exit 198
    }
    if `_pte_has_refline' & "`norefline'" != "" {
        di as error "{bf:Error}: refline() and norefline cannot be combined."
        di as error "Choose either refline(#) or norefline."
        exit 198
    }
    if `_pte_has_legend' & "`nolegend'" != "" {
        di as error "{bf:Error}: legend() and nolegend cannot be combined."
        di as error "Choose either legend(...) or nolegend."
        exit 198
    }
    if `_pte_has_save' & "`saving'" != "" {
        di as error "{bf:Error}: save() and saving() cannot be combined."
        di as error "Use save() or the legacy saving() alias, not both."
        exit 198
    }
    if `_pte_has_currentlawchecked' {
        di as error "{bf:Error}: currentlawchecked is an internal option."
        di as error "Use the documented pte_graph public syntax."
        exit 198
    }
    if "`ci'" != "" & !inlist("`selected'", "att", "att_dynamic") {
        di as error "{bf:Error}: legacy ci is supported only for att-family graphs."
        di as error "Use bare ci only with att or att_dynamic, or use the worker-specific ci() contract."
        exit 198
    }

    // Enforce the documented public style-value contract before dispatch so
    // invalid common style ranges do not leak into worker-specific parsers.
    local _pte_style_validate_opts ""
    if "`scheme'"    != "" local _pte_style_validate_opts `"`_pte_style_validate_opts' scheme(`scheme')"'
    if "`lcolor'"    != "" local _pte_style_validate_opts `"`_pte_style_validate_opts' lcolor(`lcolor')"'
    if "`lwidth'"    != "" local _pte_style_validate_opts `"`_pte_style_validate_opts' lwidth(`lwidth')"'
    if "`lpattern'"  != "" local _pte_style_validate_opts `"`_pte_style_validate_opts' lpattern(`lpattern')"'
    if "`msymbol'"   != "" local _pte_style_validate_opts `"`_pte_style_validate_opts' msymbol(`msymbol')"'
    if "`msize'"     != "" local _pte_style_validate_opts `"`_pte_style_validate_opts' msize(`msize')"'
    if "`preset'"    != "" local _pte_style_validate_opts `"`_pte_style_validate_opts' preset(`preset')"'
    if `legendpos'  != -1  local _pte_style_validate_opts `"`_pte_style_validate_opts' legendpos(`legendpos')"'
    if `_pte_has_alpha'      local _pte_style_validate_opts `"`_pte_style_validate_opts' alpha(`alpha')"'
    if trim(`"`_pte_style_validate_opts'"') != "" {
        _pte_style_validate, `_pte_style_validate_opts'
    }
    
    local style_opts ""
    
    // Preserve user-supplied quoting for string options.
    if "`preset'"    != "" local style_opts `"`style_opts' preset(`preset')"'
    if "`scheme'"    != "" local style_opts `"`style_opts' scheme(`scheme')"'
    if "`lcolor'"    != "" local style_opts `"`style_opts' lcolor(`lcolor')"'
    if "`lwidth'"    != "" local style_opts `"`style_opts' lwidth(`lwidth')"'
    if "`lpattern'"  != "" local style_opts `"`style_opts' lpattern(`lpattern')"'
    if "`msymbol'"   != "" local style_opts `"`style_opts' msymbol(`msymbol')"'
    if "`msize'"     != "" local style_opts `"`style_opts' msize(`msize')"'
    if "`mcolor'"    != "" local style_opts `"`style_opts' mcolor(`mcolor')"'
    if "`mfcolor'"   != "" local style_opts `"`style_opts' mfcolor(`mfcolor')"'
    if `"`title'"'   != "" local style_opts `"`style_opts' title(`title')"'
    if `"`xtitle'"'  != "" local style_opts `"`style_opts' xtitle(`xtitle')"'
    if `"`ytitle'"'  != "" local style_opts `"`style_opts' ytitle(`ytitle')"'
    if `"`subtitle'"' != "" local style_opts `"`style_opts' subtitle(`subtitle')"'
    if `"`note'"'    != "" local style_opts `"`style_opts' note(`note')"'
    if `"`legend'"'  != "" local style_opts `"`style_opts' legend(`legend')"'
    if "`xline'"     != "" local style_opts `"`style_opts' xline(`xline')"'
    if "`yline'"     != "" local style_opts `"`style_opts' yline(`yline')"'
    if "`bgcolor'"   != "" local style_opts `"`style_opts' bgcolor(`bgcolor')"'
    if "`gridstyle'" != "" local style_opts `"`style_opts' gridstyle(`gridstyle')"'
    
    // Forward numeric options only when the caller changes sentinel defaults.
    if `legendpos'  != -1   local style_opts `"`style_opts' legendpos(`legendpos')"'
    if `legendcols' != -1   local style_opts `"`style_opts' legendcols(`legendcols')"'
    if `legendring' != -1   local style_opts `"`style_opts' legendring(`legendring')"'
    if `_pte_has_refline' local style_opts `"`style_opts' refline(`refline')"'
    if `_pte_has_alpha'     local style_opts `"`style_opts' alpha(`alpha')"'
    
    // Boolean flags are forwarded verbatim.
    if "`nolegend'"  != "" local style_opts `"`style_opts' nolegend"'
    if "`norefline'" != "" local style_opts `"`style_opts' norefline"'
    if "`grid'"      != "" local style_opts `"`style_opts' grid"'
    if "`nogrid'"    != "" local style_opts `"`style_opts' nogrid"'

    local _pte_legacy_worker_opts ""
    if "`saving'" != "" {
        local _pte_legacy_worker_opts `"`_pte_legacy_worker_opts' save(`saving')"'
    }
    if "`selected'" == "diagnose" & "`_pte_diag_type_alias'" != "" {
        local _pte_legacy_worker_opts `"`_pte_legacy_worker_opts' type(`_pte_diag_type_alias')"'
    }
    
    // by() is implemented only for the legacy grouped-graph families that
    // _pte_graph_by actually understands. Heterogeneity accepts by()
    // through its own worker contract; unsupported families must reject
    // public by() before any exact-name check can mask that contract.
    local _pte_by_supported = inlist("`selected'", "tt", "catt", ///
        "compare", "scatter", "evolution", "diagnose")
    local _pte_by_requires_exact = (`_pte_by_supported' | "`selected'" == "heterogeneity")
    local _pte_by_opts ""
    if `_pte_by_layout_combine' {
        local _pte_by_opts "`_pte_by_opts' combine"
    }
    local _pte_by_family_opts "`tt' `catt' `att' `scatter' `evolution' `compare' `diagnose'"
    if trim("`_pte_by_family_opts'") == "" & "`selected'" != "" {
        local _pte_by_family_opts "`selected'"
    }
    if "`by'" != "" {
        if "`selected'" == "att" {
            di as error "{bf:Error}: by() is not supported for att graphs."
            di as error "Stored e(att) results are pooled across groups, so a grouped ATT graph would silently reuse the same full-sample ATT path."
            di as error "Use tt, catt, compare, scatter, evolution, diagnose, or heterogeneity with by()."
            exit 198
        }
        if !`_pte_by_requires_exact' {
            di as error "{bf:Error}: by() is supported only for tt, catt, compare, scatter, evolution, diagnose, and heterogeneity."
            if "`selected'" == "combine" {
                di as error "Use byperiod, byindustry, or bygroup() with combine graphs."
            }
            exit 198
        }
        capture confirm variable `by', exact
        if _rc != 0 {
            di as error "[pte] Error: variable '`by'' not found"
            di as error "[pte] specify the exact grouping variable name in by()"
            exit 111
        }
        if `_pte_by_supported' {
            _pte_graph_by `by', ///
                `_pte_by_family_opts' ///
                `_pte_by_opts' ///
                `_pte_legacy_worker_opts' `style_opts' `options'
            return add
            exit
        }
    }

    // Grouped estimation results publish pooled e(att) alongside grouped ATT
    // payloads. Pooled-only graph families must reject that state rather than
    // silently dropping heterogeneity on the public graph path.
    local _pte_grouped_by ""
    capture local _pte_grouped_by = e(by)
    if _rc == 0 & `"`_pte_grouped_by'"' == "." {
        local _pte_grouped_by ""
    }
    quietly _pte_has_grouped_att_payload
    local _pte_has_grouped_att = r(has_grouped_att)
    local _pte_grouped_payloads `"`r(grouped_payloads)'"'
    if `_pte_has_grouped_att' & inlist("`selected'", "att", "compare_cf", "att_dynamic", "ate_count_dynamic") {
        di as error "{bf:Error}: grouped ATT results are not supported by pte_graph, `selected'"
        if `"`_pte_grouped_by'"' != "" {
            di as error "Current e() results were produced with by()/industry() and contain group-specific ATT paths."
            di as error "Use {bf:pte_graph, heterogeneity by(`_pte_grouped_by')}, or re-run pooled pte results."
        }
        else {
            di as error "Current e() results still contain grouped ATT payloads even though route metadata are incomplete."
            di as error "Use {bf:pte_graph, heterogeneity} only after reconstructing the grouped route metadata, or re-run pooled pte results."
        }
        if `"`_pte_grouped_payloads'"' != "" di as error "Detected grouped payload(s): `macval(_pte_grouped_payloads)'"
        di as error "Plotting pooled e(att) here would silently drop grouped heterogeneity."
        exit 198
    }
    
    if "`selected'" == "tt" {
        _pte_graph_tt, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "catt" {
        _pte_graph_catt, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "att" {
        // Non-absorbing ATT results are split into switch-in and switch-out components.
        // Choose the worker based on the stored treatment type in e().
        local _pte_trt_type = lower("`e(trt_type)'")
        if "`_pte_trt_type'" == "" {
            local _pte_trt_type = lower("`e(treatment_type)'")
        }
        local _pte_nonabs_helper_state = 0
        local _pte_nonabs_one_sided = 0
        local _pte_nonabs_one_sided_side ""
        if "`e(cmd)'" == "_pte_bootstrap_nonabs" {
            capture confirm matrix e(att_plus)
            local _pte_has_att_plus = (_rc == 0)
            capture confirm matrix e(att_minus)
            local _pte_has_att_minus = (_rc == 0)
            if `_pte_has_att_plus' & `_pte_has_att_minus' {
                local _pte_nonabs_helper_state = 1
            }
            else if `_pte_has_att_plus' | `_pte_has_att_minus' {
                local _pte_nonabs_one_sided = 1
                if `_pte_has_att_plus' {
                    local _pte_nonabs_one_sided_side "ATT+ only"
                }
                else {
                    local _pte_nonabs_one_sided_side "ATT- only"
                }
            }
        }

        if inlist("`_pte_trt_type'", "non-absorbing", "nonabsorbing") | `_pte_nonabs_helper_state' {
            di as text "Note: Non-absorbing treatment detected. Plotting switch-in and switch-out ATT components."
            _pte_graph_att_nonabs, `_pte_legacy_worker_opts' `style_opts' `options'
            return add
        }
        else if `_pte_nonabs_one_sided' {
            di as error "pte_graph: one-sided nonabsorbing helper bundle detected (`_pte_nonabs_one_sided_side')."
            di as error "  Public nonabsorbing ATT graphs require both e(att_plus) and e(att_minus)."
            di as error "  Current bundle is not an absorbing e(att) result and cannot be graphed by _pte_graph_att."
            exit 198
        }
        else {
            _pte_graph_att, `_pte_legacy_worker_opts' `style_opts' `options'
            return add
        }
    }
    else if "`selected'" == "compare" {
        _pte_graph_compare, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "heterogeneity" {
        if "`by'" != "" {
            _pte_graph_heterogeneity, by(`by') `_pte_legacy_worker_opts' `style_opts' `options'
        }
        else {
            _pte_graph_heterogeneity, `_pte_legacy_worker_opts' `style_opts' `options'
        }
        local _pte_graph_type "`r(graph_type)'"
        local _pte_type "`r(type)'"
        local _pte_filename "`r(filename)'"
        local _pte_by "`r(by)'"
        local _pte_group_labels `"`r(group_labels)'"'
        return add
        if "`_pte_graph_type'" != "" {
            return local graph_type "`_pte_graph_type'"
        }
        if "`_pte_type'" != "" {
            return local type "`_pte_type'"
        }
        if "`_pte_filename'" != "" {
            return local filename "`_pte_filename'"
        }
        if "`_pte_by'" != "" {
            return local by "`_pte_by'"
        }
        if `"`_pte_group_labels'"' != "" {
            return local group_labels `"`_pte_group_labels'"'
        }
    }
    else if "`selected'" == "scatter" {
        _pte_graph_scatter, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "evolution" {
        _pte_graph_evolution, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "diagnose" {
        _pte_graph_diagnose, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "combine" {
        _pte_graph_combine, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "compare_cf" {
        _pte_graph_compare_cf, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "att_dynamic" {
        _pte_graph_att_dynamic, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "ate_count_dynamic" {
        _pte_graph_ate_dynamic, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "tt_distribution" {
        _pte_graph_tt_dist, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    else if "`selected'" == "eps0_diagnostic" {
        _pte_graph_eps0_diag, `_pte_legacy_worker_opts' `style_opts' `options'
        return add
    }
    
end
