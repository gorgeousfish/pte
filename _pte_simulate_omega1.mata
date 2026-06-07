*! version 1.0.0  20Feb2026
*! _pte_simulate_omega1.mata - US-E12-003 Task 19A
*! Mata function for omega^1 path simulation (Divergent Counterfactual ATE)
*! Implements Proposition D.3: dual-phase recursive simulation
*!   ell=0:   h_1^+ (transition function, untreated -> treated)
*!   ell>=1:  h_bar_1 (steady-state treated evolution, rho + gamma/delta)
*! Reference: Chen, Liao & Schurter (2026) Appendix D.3.2

version 14.0

mata:

// ====================================================================
// _pte_simulate_omega1: Simulate omega^1 paths for divergent ATE
// ====================================================================
//
// Proposition D.3 dual-phase recursion:
//   ell=0:   omega1 = h_1^+(omega_start) + eps1
//   ell>=1:  omega1 = h_bar_1(omega1_lag) + eps1
//
// Parameters:
//   omega_start  - N x 1 column vector: starting productivity values
//   h_plus       - 1 x (p+1) row vector: h_1^+ coefficients
//                  [const, omega, omega^2, ..., omega^p]
//   rho_h1       - 1 x (p+1) row vector: h_bar_1 coefficients
//                  [const, omega, omega^2, ..., omega^p]
//                  where h_bar_1 = (rho_0+delta, rho_1+gamma_1, ...)
//   sigma_eps1   - scalar: std dev of eps1 shocks (from G_epsilon^1)
//   nperiods     - scalar: number of periods after ell=0
//   nsim         - scalar: number of simulation paths per firm
//   seed         - scalar: random seed (set at beginning)
//
// Returns:
//   N x (nsim * (nperiods + 1)) real matrix
//   Column layout: [path1_ell0, path1_ell1, ..., path1_ellL,
//                   path2_ell0, path2_ell1, ..., path2_ellL, ...]
//
// Complexity:
//   TIME:  O(N * nsim * nperiods * p)
//   SPACE: O(N * nsim * (nperiods + 1))
// ====================================================================

real matrix _pte_simulate_omega1(
    real colvector omega_start,
    real rowvector h_plus,
    real rowvector rho_h1,
    real scalar sigma_eps1,
    real scalar nperiods,
    real scalar nsim,
    real scalar seed)
{
    // Local variable declarations
    real scalar N, p, m, j, ell, col_idx
    real colvector eps1_draw, h_val, omega1_cur, omega1_lag
    real matrix result

    // Set random seed for reproducibility
    rseed(seed)

    N = rows(omega_start)
    p = cols(h_plus) - 1  // polynomial order

    // Initialize result matrix
    result = J(N, nsim * (nperiods + 1), .)

    for (m = 1; m <= nsim; m++) {

        // ============================================================
        // ell=0: Use h_1^+ (transition function)
        // omega1_0 = h_1^+(omega_start) + eps1_0
        // ============================================================
        eps1_draw = rnormal(N, 1, 0, sigma_eps1)

        // Evaluate polynomial h_1^+(omega_start)
        h_val = J(N, 1, h_plus[1])
        for (j = 1; j <= p; j++) {
            h_val = h_val + h_plus[j + 1] * (omega_start :^ j)
        }

        omega1_cur = h_val + eps1_draw

        // Store in result matrix
        col_idx = (m - 1) * (nperiods + 1) + 1
        result[., col_idx] = omega1_cur

        // Save as lag for next period
        omega1_lag = omega1_cur

        // ============================================================
        // ell>=1: Use h_bar_1 (steady-state treated evolution)
        // omega1_ell = h_bar_1(omega1_{ell-1}) + eps1_ell
        // ============================================================
        for (ell = 1; ell <= nperiods; ell++) {
            eps1_draw = rnormal(N, 1, 0, sigma_eps1)

            // Evaluate polynomial h_bar_1(omega1_lag)
            h_val = J(N, 1, rho_h1[1])
            for (j = 1; j <= p; j++) {
                h_val = h_val + rho_h1[j + 1] * (omega1_lag :^ j)
            }

            omega1_cur = h_val + eps1_draw

            // Store in result matrix
            col_idx = (m - 1) * (nperiods + 1) + ell + 1
            result[., col_idx] = omega1_cur

            // Update lag for next period
            omega1_lag = omega1_cur
        }
    }

    return(result)
}

end
