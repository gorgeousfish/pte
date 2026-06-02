# pte

**Productivity Treatment Effects for Stata**

[![Stata 14.0+](https://img.shields.io/badge/Stata-14.0%2B-blue.svg)](https://www.stata.com/)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Version: 1.0.0](https://img.shields.io/badge/Version-1.0.0-green.svg)]()

## Overview

`pte` implements the **Productivity Treatment Effects** framework proposed by Chen, Liao & Schurter (2026, *RAND Journal of Economics*) for Stata. The package integrates semiparametric production function estimation with treatment effect analysis, providing a unified toolkit for applied researchers studying how interventions affect productive efficiency.

The core innovation is the **CLK correction**: in ACF-style production function estimation, transition-period observations (where treatment status changes) are excluded, and two separate productivity evolution paths are estimated for treated and control firms. Counterfactual productivity paths are then simulated via Monte Carlo to compute Average Treatment Effects on the Treated (ATT).

**Features:**

- Production function estimation via semiparametric GMM with CLK correction (Cobb-Douglas and Translog)
- Firm-level productivity recovery from estimated parameters
- ATT estimation through Monte Carlo counterfactual simulation (Proposition 4.3)
- Clustered bootstrap inference with stratified resampling
- Non-absorbing treatment and treatment-dependent production function extensions
- Cohort analysis, heterogeneity analysis, and method comparison
- Parallel computing support for grouped bootstrap acceleration
- Visualization for treatment effects, diagnostics, and productivity distributions

## Requirements

- Stata 14.0 or later
- No additional dependencies for baseline estimation

Optional workflow packages:

| Package                           | Required For                                      |
| --------------------------------- | ------------------------------------------------- |
| `reghdfe`                       | `pte_compare` (TWFE comparison)                 |
| `prodest` / `endopolyprodest` | Treatment-dependent production function workflows |
| `parallel`                      | Parallel bootstrap acceleration                   |

Use `pte_check_deps` to verify dependencies before advanced workflows.

## Installation

### From GitHub

```stata
net install pte, from("https://raw.githubusercontent.com/gorgeousfish/pte/main")
```

### From SSC (after public release)

```stata
ssc install pte
```

### Verify Installation

```stata
which pte
help pte
pte_version
```

## Quick Start

```stata
* Load bundled example data (installed to your adopath via net install)
findfile pte_example.dta
use "`r(fn)'", clear
xtset firm year

* Estimate treatment effects on productivity (Cobb-Douglas)
pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) pfunc(cd)

* View results
ereturn list
matrix list e(att)

* Visualize treatment effects
pte_graph, att
```

## Commands

| Command               | Description                                                                             |
| --------------------- | --------------------------------------------------------------------------------------- |
| `pte`               | Main estimation command (production function + productivity recovery + ATT + bootstrap) |
| `pte_setup`         | Panel data preparation and treatment-path diagnostics                                   |
| `pte_diagnose`      | Assumption diagnostics                                                                  |
| `pte_graph`         | Results visualization                                                                   |
| `pte_compare`       | Method comparison (CLK vs TWFE, etc.)                                                   |
| `pte_heterogeneity` | Heterogeneity analysis (CATT)                                                           |
| `pte_export`        | Results export (LaTeX/CSV/Excel)                                                        |
| `pte_check_deps`    | Dependency check                                                                        |
| `pte_version`       | Version information                                                                     |
| `pte_p`             | Postestimation predictions (predict interface)                                          |

## Syntax

### pte

```stata
pte depvar, free(varname) state(varname) proxy(varname) treatment(varname) [options]
```

**Required:**

| Option | Description |
|--------|-------------|
| `free(varname)` | Free input variable (e.g., labor) |
| `state(varname)` | State variable (e.g., capital) |
| `proxy(varname)` | Proxy variable (e.g., materials) |
| `treatment(varname)` | Binary treatment indicator |

**Key options:**

| Option | Default | Description |
|--------|---------|-------------|
| `pfunc(string)` | translog | Production function: `cd` or `translog` |
| `omegapoly(#)` | 3 | Productivity evolution polynomial order (1–4) |
| `attperiods(#)` | 4 | Maximum event-time horizon |
| `nsim(#)` | auto | Number of Monte Carlo simulation paths |
| `bootstrap(#)` | 0 | Bootstrap replications (0 or ≥2) |
| `by(varname)` | — | Group-by variable (e.g., industry) |
| `control(varlist)` | — | Control variables for first-stage regression |
| `seed(#)` | 1/123456 | Random number seed (1 for bootstrap, 123456 for point estimation) |
| `level(#)` | 95 | Confidence level |
| `nonabsorbing` | — | Enable non-absorbing treatment analysis |
| `treatdependent` | — | Enable treatment-dependent production function |
| `noparallel` | — | Force sequential bootstrap |
| `nolog` | — | Suppress progress output |

### pte_setup

```stata
pte_setup, treatment(varname) [options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `treatment(varname)` | required | Binary treatment indicator |
| `firmid(varname)` | xtset id | Panel ID variable |
| `timevar(varname)` | xtset time | Time variable |
| `check` | — | Audit mode (no variable generation) |
| `absorbing` | — | Strict absorbing-treatment check |
| `report` | — | Print setup summary |
| `replace` | — | Overwrite existing `_pte_*` variables |

### pte_diagnose

```stata
pte_diagnose [, options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `all` | default | Run all diagnostics |
| `parallel` | — | Parallel trends test |
| `kstest` | — | Kolmogorov-Smirnov test |
| `conditional` | — | Conditional independence test |
| `cdf` | — | CDF comparison |
| `preperiods(#)` | 4 | Number of pre-treatment periods |
| `alpha(#)` | 0.05 | Significance level |

### pte_graph

```stata
pte_graph [, graph_type style_options]
```

**Graph types:** `att` (default) | `tt` | `tt_distribution` | `catt` | `compare` | `compare_cf` | `heterogeneity` | `scatter` | `evolution` | `diagnose` | `eps0_diagnostic` | `combine`

| Option | Description |
|--------|-------------|
| `by(varname)` | Grouped graph routing |
| `preset(string)` | Style preset name |
| `ci` | Display confidence intervals |
| `saving(filename)` | Save graph to file |
| `title(string)` | Graph title |

### pte_compare

```stata
pte_compare [, options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `method(string)` | expost | Comparison method: `expost`, `endog`, `clktwfe`, or `all` |
| `specs(numlist)` | 1 2 3 | TWFE specification numbers |
| `diagnose` | — | Show bias-source analysis |

**Methods:** I = ex-post regression + TWFE; II = endogenous productivity + TWFE; III = CLK + TWFE

### pte_heterogeneity

```stata
pte_heterogeneity, by(varname) [options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `by(varname)` | required | Discrete grouping variable |
| `test` | — | Perform heterogeneity test (Q-statistic) |
| `level(#)` | 95 | Confidence level |
| `nocontribution` | — | Suppress contribution decomposition |

### pte_export

```stata
pte_export results using filename [, options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `format(string)` | latex | Output format: `latex`, `xlsx`, or `csv` |
| `se` / `nose` | se | Include/suppress standard errors |
| `stars(numlist)` | 0.01 0.05 0.10 | Significance thresholds (LaTeX only) |
| `decimals(#)` | 3 | Decimal places |
| `replace` | — | Overwrite existing file |
| `title(string)` | — | Table title (LaTeX only) |

## Documentation

In Stata:

```stata
help pte
help pte_setup
help pte_graph
help pte_compare
```

Theoretical foundation: Chen, Liao & Schurter (2026), "Identifying Treatment Effects on Productivity: Theory with an Application to Production Digitalization," *RAND Journal of Economics*.

## References

Chen, Z., Liao, M., & Schurter, K. (2026). Identifying Treatment Effects on Productivity: Theory with an Application to Production Digitalization. *RAND Journal of Economics*.

## Authors

**Stata Implementation:**

- **Xuanyu Cai**, City University of Macau
  Email: [xuanyuCAI@outlook.com](mailto:xuanyuCAI@outlook.com)

**Methodology:**

- **Zhiyuan Chen**, University of Zurich
- **Moyu Liao**, City University of Macau
- **Karl Schurter**, University of Texas at Austin

## License

AGPL-3.0. See [LICENSE](LICENSE) for details.

## Citation

If you use this package in your research, please cite both the methodology paper and the Stata implementation:

**APA Format:**

> Cai, X. (2026). *pte: Stata module for Productivity Treatment Effects estimation* (Version 1.0.0) [Computer software]. GitHub. https://github.com/gorgeousfish/pte
>
> Chen, Z., Liao, M., & Schurter, K. (2026). Identifying Treatment Effects on Productivity: Theory with an Application to Production Digitalization. *RAND Journal of Economics*.

**BibTeX:**

```bibtex
@software{pte2026stata,
  title={pte: Stata module for Productivity Treatment Effects estimation},
  author={Xuanyu Cai},
  year={2026},
  version={1.0.0},
  url={https://github.com/gorgeousfish/pte}
}

@article{chen2026pte,
  title={Identifying Treatment Effects on Productivity: Theory with an Application to Production Digitalization},
  author={Chen, Zhiyuan and Liao, Moyu and Schurter, Karl},
  journal={RAND Journal of Economics},
  year={2026}
}
```

## See Also

- Paper: Chen, Z., Liao, M., & Schurter, K. (2026). *RAND Journal of Economics*.
