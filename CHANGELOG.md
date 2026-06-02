# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-05-31

### Initial Release

First public release of `pte` (Productivity Treatment Effects), implementing the framework proposed by Chen, Liao & Schurter (2026, *RAND Journal of Economics*).

### Core Features

- **Production function estimation** via semiparametric GMM with CLK correction
  - Cobb-Douglas and Translog specifications
  - Concentrated-out optimization with Nelder-Mead
  - Transition-period exclusion for consistent estimation
- **Productivity recovery** from estimated production function parameters
  - Polynomial evolution law (orders 1–4)
  - Separate evolution paths for treated and control firms
- **ATT estimation** through Monte Carlo counterfactual simulation
  - Event-time dynamic effects
  - Configurable simulation paths
- **Bootstrap inference** with clustered stratified resampling
  - Parallel computing support via `parallel` package
  - Reproducible dual-layer seed management

### Commands

| Command | Description |
|---------|-------------|
| `pte` | Main estimation command |
| `pte_setup` | Panel data preparation and diagnostics |
| `pte_diagnose` | Assumption diagnostics (parallel trends, KS test, CDF) |
| `pte_graph` | Results visualization |
| `pte_compare` | Method comparison (CLK vs TWFE) |
| `pte_heterogeneity` | Heterogeneity analysis (CATT) |
| `pte_export` | Results export (LaTeX/CSV/Excel) |
| `pte_esttab_att` | ATT table formatting for esttab |
| `pte_check_deps` | Dependency verification |
| `pte_version` | Version information |
| `pte_p` | Postestimation predict interface |

### Extensions

- Non-absorbing treatment analysis
- Treatment-dependent production function
- Cohort effect analysis
- Industry-level grouped estimation
