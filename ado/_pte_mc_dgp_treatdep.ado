*! _pte_mc_dgp_treatdep.ado
*! Treatment-dependent DGP for Monte Carlo simulation
*!
*! Generates simulated panel data with treatment-dependent production
*! function coefficients (beta0 vs beta1) and evolution (h_bar_0 vs h_bar_1).

version 14.0
program define _pte_mc_dgp_treatdep, rclass
    version 14.0
    
    syntax, Seed(integer) ///
        [Nfirms(integer 500) Tperiods(integer 10) ///
         BETAl0(real 0.6) BETAk0(real 0.3) ///
         BETAl1(real 0.5) BETAk1(real 0.35) ///
         RHO0(real 0.1) RHO1(real 0.85) ///
         RHO4(real 0.05) RHO7(real 0.02) ///
         Sigma_eps(real 0.15) Sigma_eta(real 0.1) ///
         TREATshare(real 0.3) ///
         DEGenerate ///
         PFunc(string)]
    
    // Default production function
    if "`pfunc'" == "" local pfunc "cd"
    
    // Degenerate mode: beta1 = beta0, rho4 = rho7 = 0
    if "`degenerate'" != "" {
        local betal1 = `betal0'
        local betak1 = `betak0'
        local rho4 = 0
        local rho7 = 0
    }
    
    // ---------------------------------------------------------------
    // Step 1: Generate balanced panel structure
    // ---------------------------------------------------------------
    clear
    set seed `seed'
    local nobs = `nfirms' * `tperiods'
    qui set obs `nobs'
    
    // Panel identifiers
    qui gen int firm = ceil(_n / `tperiods')
    qui gen int year = mod(_n - 1, `tperiods') + 1
    qui xtset firm year
    
    // ---------------------------------------------------------------
    // Step 2: Treatment assignment (~treatshare of firms)
    // ---------------------------------------------------------------
    // Assign treatment year randomly in [4, tperiods-3]
    local ty_min = 4
    local ty_max = `tperiods' - 3
    
    tempvar treat_draw ty_draw
    qui gen double `treat_draw' = runiform() if year == 1
    qui bys firm (year): replace `treat_draw' = `treat_draw'[1]
    qui gen byte treat = (`treat_draw' < `treatshare')
    
    qui gen int `ty_draw' = floor(runiform() * (`ty_max' - `ty_min' + 1)) + `ty_min' if year == 1 & treat == 1
    qui bys firm (year): replace `ty_draw' = `ty_draw'[1]
    qui gen int treat_yr0 = `ty_draw' if treat == 1
    
    qui gen byte treat_post = (year >= treat_yr0) if treat == 1
    qui replace treat_post = 0 if treat == 0
    
    // Transition indicator: mid = 1 when D_t != D_{t-1}
    qui gen byte mid = (treat_post != L.treat_post) if !missing(L.treat_post)
    qui replace mid = 0 if missing(mid)
    
    // Relative time
    qui gen int nt = year - treat_yr0 if treat == 1
    
    // ---------------------------------------------------------------
    // Step 3: Generate inputs
    // ---------------------------------------------------------------
    qui gen double lnk = rnormal(2, 0.5)
    qui gen double lnl = rnormal(1.5, 0.4)
    
    // Interaction terms for treatment-dependent model
    qui gen double lnl_tp = lnl * treat_post
    qui gen double lnk_tp = lnk * treat_post
    
    // ---------------------------------------------------------------
    // Step 4: Generate omega with treatment-dependent evolution
    //   D=0 path (h_bar_0): omega_t = rho0 + rho1*omega_{t-1} + eps
    //   D=1 path (h_bar_1): omega_t = (rho0+rho7) + (rho1+rho4)*omega_{t-1} + eps
    //   Counterfactual (omega0_cf): always uses h_bar_0 for treated firms
    // ---------------------------------------------------------------
    qui gen double omega = rnormal(1, 0.3) if year == 1
    qui gen double omega0_cf = . 
    qui gen double _pte_eps = rnormal(0, `sigma_eps')
    
    // Recursive evolution year by year
    forvalues t = 2/`tperiods' {
        // h_bar_0 for control observations (treat_post==0 at t-1)
        qui bys firm (year): replace omega = `rho0' ///
            + `rho1' * omega[_n-1] + _pte_eps[_n-1] ///
            if year == `t' & L.treat_post == 0
        
        // h_bar_1 for treated observations (treat_post==1 at t-1)
        qui bys firm (year): replace omega = (`rho0' + `rho7') ///
            + (`rho1' + `rho4') * omega[_n-1] + _pte_eps[_n-1] ///
            if year == `t' & L.treat_post == 1
    }
    
    // ---------------------------------------------------------------
    // Step 5: Counterfactual omega (h_bar_0 path for treated firms)
    //   This is what omega would be if the firm was never treated.
    //   Always uses rho0, rho1 only (no rho4, rho7).
    // ---------------------------------------------------------------
    // Initialize counterfactual at treatment year - 1
    qui replace omega0_cf = omega if year == treat_yr0 - 1 & treat == 1
    
    // Forward simulate using h_bar_0 only
    forvalues t = 2/`tperiods' {
        qui bys firm (year): replace omega0_cf = `rho0' ///
            + `rho1' * omega0_cf[_n-1] + _pte_eps[_n-1] ///
            if year == `t' & treat == 1 & year >= treat_yr0 & omega0_cf[_n-1] != .
    }
    
    // ---------------------------------------------------------------
    // Step 6: Generate output (treatment-dependent production function)
    //   D=0: lny = beta_l0*lnl + beta_k0*lnk + omega + eta
    //   D=1: lny = beta_l1*lnl + beta_k1*lnk + omega + eta
    // ---------------------------------------------------------------
    qui gen double eta = rnormal(0, `sigma_eta')
    qui gen double lny = `betal0' * lnl + `betak0' * lnk + omega + eta ///
        if treat_post == 0
    qui replace lny = `betal1' * lnl + `betak1' * lnk + omega + eta ///
        if treat_post == 1
    
    // Proxy variable
    qui gen double lnm = 0.5 * lnl + 0.3 * lnk + 0.2 * omega + rnormal(0, 0.1)
    
    // Time trend
    qui gen int t = year
    
    // ---------------------------------------------------------------
    // Step 7: True ATT calculation (Task 8)
    //   ATT_true = E[omega_actual - omega0_cf | D=1, post-treatment]
    //   Only rho0-rho1 used in counterfactual (h_bar_0 path)
    // ---------------------------------------------------------------
    qui gen double TT_true = omega - omega0_cf if treat_post == 1
    
    qui sum TT_true if treat_post == 1, meanonly
    local att_true = r(mean)
    local n_att = r(N)
    
    // ---------------------------------------------------------------
    // Step 8: Cleanup and return values
    // ---------------------------------------------------------------
    drop _pte_eps eta
    
    // Panel setup
    qui xtset firm year
    
    // Count firms
    qui distinct firm if treat == 1
    local n_treated = r(ndistinct)
    qui distinct firm if treat == 0
    local n_control = r(ndistinct)
    
    // Verify: rho7 > 0 should make ATT > 0
    if "`degenerate'" == "" & `rho7' > 0 {
        if `att_true' <= 0 {
            di as text "  Warning: ATT_true = " %7.4f `att_true' " <= 0 despite rho7 > 0"
        }
    }
    
    // Return scalars
    return scalar att_true   = `att_true'
    return scalar n_att      = `n_att'
    return scalar n_firms    = `nfirms'
    return scalar n_treated  = `n_treated'
    return scalar n_control  = `n_control'
    return scalar beta_l0    = `betal0'
    return scalar beta_k0    = `betak0'
    return scalar beta_l1    = `betal1'
    return scalar beta_k1    = `betak1'
    return scalar rho0       = `rho0'
    return scalar rho1       = `rho1'
    return scalar rho4       = `rho4'
    return scalar rho7       = `rho7'
    return scalar seed       = `seed'
    
    di as text "DGP generated: `nfirms' firms, " ///
        "`n_treated' treated, `n_control' control"
    di as text "  beta0: l=" %5.3f `betal0' " k=" %5.3f `betak0' ///
        "  beta1: l=" %5.3f `betal1' " k=" %5.3f `betak1'
    di as text "  rho: 0=" %5.3f `rho0' " 1=" %5.3f `rho1' ///
        " 4=" %5.3f `rho4' " 7=" %5.3f `rho7'
    di as text "  ATT_true = " %7.4f `att_true' " (N=" `n_att' ")"
    
end
