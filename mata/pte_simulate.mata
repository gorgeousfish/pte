*! version 1.0.0  20Feb2026
*! pte_simulate.mata - US-E3-009 Task 9
*! Mata function for omega^0 counterfactual path simulation (ATT estimation)
*! Implements Proposition 4.3: single-phase recursive simulation using h_bar_0
*!   ell=0:  omega0 = h_bar_0(omega_start)
*!   ell>0:  omega0 = h_bar_0(omega0_lag) + lagged eps0 draw
*! The counterfactual asks "what if untreated?" so only the untreated
*! evolution function h̄₀ is used — NO treatment interaction terms (γ, δ).
*! Reference: Chen, Liao & Schurter (2026) Proposition 4.3

version 14.0

mata:

// ====================================================================
// pte_simulate_paths: Simulate omega^0 counterfactual paths for ATT
// ====================================================================
//
// Proposition 4.3 single-phase recursion (untreated evolution only):
//   ell = 0:
//     omega0 = h_bar_0(omega_start)
//   ell > 0:
//     omega0 = h_bar_0(omega0_lag) + lagged eps0 draw
//
// where h_bar_0 is the polynomial:
//   h_bar_0(omega) = rho[1] + rho[2]*omega + rho[3]*omega^2 + ... + rho[p+1]*omega^p
//
// This does NOT use treatment interaction terms (gamma, delta).
// The counterfactual asks "what would productivity be if untreated?"
//
// Parameters:
//   omega_start  - N x 1 column vector: starting omega values (omega at nt=-1)
//   rho          - 1 x (p+1) row vector: h_bar_0 coefficients
//                  [const, omega, omega^2, ..., omega^p]
//   sigma_eps    - scalar: std dev of eps0 shocks (from G_epsilon^0)
//   n_periods    - scalar: number of periods to simulate (attperiods + 1)
//   n_paths      - scalar: number of simulation paths per firm (nsim)
//   seed         - scalar: random seed (set via rseed() at beginning)
//
// Returns:
//   N x (n_paths * n_periods) real matrix
//   Column layout: [path1_ell0, path1_ell1, ..., path1_ell(L-1),
//                   path2_ell0, path2_ell1, ..., path2_ell(L-1), ...]
//
// Complexity:
//   TIME:  O(N * n_paths * n_periods * p)
//   SPACE: O(N * n_paths * n_periods)
// ====================================================================

real matrix pte_simulate_paths(
    real colvector omega_start,
    real rowvector rho,
    real scalar sigma_eps,
    real scalar n_periods,
    real scalar n_paths,
    real scalar seed)
{
    // Local variable declarations
    real scalar N, p, m, j, ell, col_idx
    real colvector eps0_draw, eps0_lag, h_val, omega0_cur, omega0_lag
    real matrix result

    // Set random seed for reproducibility
    rseed(seed)

    N = rows(omega_start)
    p = cols(rho) - 1  // polynomial order

    // Initialize result matrix
    result = J(N, n_paths * n_periods, .)

    for (m = 1; m <= n_paths; m++) {

        // Initialize lag as starting omega values
        omega0_lag = omega_start

        eps0_lag = J(N, 1, 0)

        // ============================================================
        // All periods use h_bar_0 (untreated evolution function).
        // ell=0 is the deterministic ATT onset benchmark; the draw made
        // on that row is consumed by the next recursive state.
        // ============================================================
        for (ell = 0; ell < n_periods; ell++) {
            eps0_draw = rnormal(N, 1, 0, sigma_eps)

            // Evaluate polynomial h_bar_0(omega0_lag)
            h_val = J(N, 1, rho[1])
            for (j = 1; j <= p; j++) {
                h_val = h_val + rho[j + 1] * (omega0_lag :^ j)
            }

            if (ell == 0) {
                omega0_cur = h_val
            }
            else {
                omega0_cur = h_val + eps0_lag
            }

            // Store in result matrix
            col_idx = (m - 1) * n_periods + ell + 1
            result[., col_idx] = omega0_cur

            // Update lag for next period
            omega0_lag = omega0_cur
            eps0_lag = eps0_draw
        }
    }

    return(result)
}

end
