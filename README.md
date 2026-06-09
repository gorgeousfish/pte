# pte

**Productivity Treatment Effects for Stata**

[![Stata 14.0+](https://img.shields.io/badge/Stata-14.0%2B-blue.svg)](https://www.stata.com/)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Version: 1.0.0](https://img.shields.io/badge/Version-1.0.0-green.svg)]()

<p align="center">
  <img src="image/image.png" alt="The Shadow of Efficiency - Productivity Treatment Effects"
       width="100%">
</p>

---

## 1. Introduction

### Overview

`pte` implements the **Productivity Treatment Effects** framework proposed by
Chen, Liao & Schurter (2026, *RAND Journal of Economics*) for Stata. The package
provides a unified toolkit for applied researchers studying how interventions
affect productive efficiency — integrating semiparametric production function
estimation, causal treatment effect analysis, and Monte Carlo inference in a
single command.

### The Productivity Problem

Estimating how policies affect firm productivity faces two fundamental challenges:

**Challenge 1: Productivity is unobservable.** TFP must be *recovered* from a
production function, but firms observe their own productivity before choosing
inputs. This creates simultaneity bias that the proxy variable literature
(Olley-Pakes 1996, Levinsohn-Petrin 2003, ACF 2015) addresses — but ignores
treatment entirely.

**Challenge 2: Treatment contaminates the productivity evolution.** Standard
approaches (TWFE on recovered omega) fail because: (1) including transition
observations in GMM biases input elasticities; (2) the Markov assumption is
violated when treated firms jump to a different law of motion; (3) TWFE conflates
time-varying effects with structural bias.

### The CLK Correction

The core innovation is a simple but powerful insight:

> *If transition periods contaminate estimation, exclude them. If treated and*
> *control firms follow different evolution laws, estimate them separately.*
> *If you want the counterfactual, simulate it.*

Concretely:

- **Exclude transitions** — Remove observations where D_t ≠ D_{t-1} from GMM
  moment conditions so production function parameters are uncontaminated.
- **Separate evolution paths** — Estimate h̄₀ (control) and h̄₁ (treated)
  separately, allowing treatment to shift the entire Markov process.
- **Simulate the counterfactual** — For each treated firm, draw innovation
  shocks from the control-group distribution and propagate forward under h̄₀.
  The difference is the ATT.

### Why CLK Matters

| Method | Endogeneity Corrected | Dynamic Treatment Effect | No Structural Model | Heterogeneous Timing |
|--------|:---------------------:|:------------------------:|:-------------------:|:--------------------:|
| OLS on output | ✗ | ✗ | ✓ | ✗ |
| TWFE on recovered ω | ✓ (partially) | ✗ | ✓ | ✗ |
| Structural IO models | ✓ | ✓ | ✗ | varies |
| prodest + DiD | ✓ | ✗ | ✓ | ✗ |
| **CLK (`pte`)** | **✓** | **✓** | **✓** | **✓** |

### Key Features

- **Semiparametric GMM** with CLK correction (Cobb-Douglas and Translog)
- **Dynamic ATT** at each post-treatment horizon via Monte Carlo simulation
- **Clustered bootstrap** with stratified resampling for valid inference
- **Treatment-dependent production function** extensions (Appendix C.1)
- **Cohort analysis** and **heterogeneity analysis** (CATT by subgroup)
- **Method comparison** (CLK vs TWFE vs endogenous) via `pte_compare`
- **Parallel computing** support for bootstrap acceleration
- **Publication-quality visualization** and full `eclass` integration

---

## 2. Theoretical Framework

> The full theoretical framework is developed in Chen, Liao & Schurter (2026).
> Here we summarize the key estimation stages.

The `pte` estimation proceeds in four stages:

1. **Production Function Estimation** — First-stage polynomial regression yields
   gross productivity proxy φ̂; control variables are subtracted; transition
   observations (D_t ≠ D_{t-1}) are excluded; GMM on remaining sample recovers
   unbiased input elasticities β.

2. **Productivity Recovery and Evolution** — Firm-level productivity
   ω = φ − f(k, l; β̂) is recovered. Separate evolution laws h̄₀ (control) and
   h̄₁ (treated) are estimated as flexible polynomials in lagged ω. Innovation
   shocks ε⁰ are Winsorized at the 1st and 99th percentiles.

3. **ATT via Monte Carlo Simulation** — For each treated firm, N counterfactual
   paths are simulated using h̄₀ and draws from the ε⁰ distribution. The ATT at
   each event-time horizon is the average gap between observed and simulated
   productivity.

4. **Bootstrap Inference** — Stratified cluster resampling repeats Stages 1–3
   to construct confidence intervals. A dual-layer seed design (outer seed for
   resampling, fixed inner seed for simulation) ensures reproducibility.

See Chen, Liao & Schurter (2026) for formal assumptions, identification proofs,
and asymptotic properties.

---

## 3. Stata Commands

### 3.1 Installation

#### Method 1: GitHub via `github` Command (Recommended)

```stata
* Install the github command first (one-time setup)
net install github, from("https://haghish.github.io/github/")

* Then install pte directly
github install gorgeousfish/pte
```

#### Method 2: GitHub via `net install`

Due to Stata's per-package file limit, `pte` is distributed as three packages:

```stata
net install pte, from("https://raw.githubusercontent.com/gorgeousfish/pte/main") replace
net install pte_more, from("https://raw.githubusercontent.com/gorgeousfish/pte/main") replace
net install pte_more2, from("https://raw.githubusercontent.com/gorgeousfish/pte/main") replace
```

**Note for users in China:** If you experience connection timeouts, configure
Stata's HTTP proxy or use a GitHub mirror:

```stata
* Option A: HTTP proxy
set httpproxy on
set httpproxyhost "127.0.0.1"
set httpproxyport YOUR_PROXY_PORT

* Option B: GitHub mirror
net install pte, from("https://ghfast.top/https://raw.githubusercontent.com/gorgeousfish/pte/main") replace
net install pte_more, from("https://ghfast.top/https://raw.githubusercontent.com/gorgeousfish/pte/main") replace
net install pte_more2, from("https://ghfast.top/https://raw.githubusercontent.com/gorgeousfish/pte/main") replace
```

#### Verifying Installation

```stata
pte_version
```

### 3.2 Command Reference

#### Core Estimation

| Command | Description | When to Use |
|---------|-------------|-------------|
| `pte` | Main estimation: production function + ATT + bootstrap | Primary analysis |
| `pte_setup` | Panel validation and treatment-path diagnostics | Before estimation |
| `pte_diagnose` | Assumption tests (parallel trends, KS, CDF) | After estimation |

#### Post-Estimation and Reporting

| Command | Description | When to Use |
|---------|-------------|-------------|
| `pte_graph` | Visualization (ATT, evolution, diagnostics) | Visual inspection |
| `pte_compare` | Method comparison (CLK vs TWFE vs endogenous) | Robustness checks |
| `pte_heterogeneity` | Heterogeneity analysis (CATT by subgroup) | Effect variation |
| `pte_export` | Export to LaTeX/CSV/Excel | Publication tables |
| `pte_esttab_att` | Formatted ATT table output | Standardized reporting |
| `pte_p` | Postestimation predictions (ω, fitted, residuals) | Predict interface |

#### Utilities

| Command | Description | When to Use |
|---------|-------------|-------------|
| `pte_check_deps` | Verify optional package dependencies | Before advanced workflows |
| `pte_version` | Display version information | Check installed version |
| `pte_example` | Load bundled example dataset | Quick start, testing |

### 3.3 Main Syntax

```stata
pte depvar, free(varname) state(varname) proxy(varname) treatment(varname) [options]
```

**Required options:**

| Option | Description |
|--------|-------------|
| `free(varname)` | Free input variable (e.g., log labor) |
| `state(varname)` | State variable (e.g., log capital) |
| `proxy(varname)` | Proxy variable (e.g., log materials) |
| `treatment(varname)` | Binary treatment indicator (0/1, absorbing) |

**Key estimation options:**

| Option | Default | Description |
|--------|---------|-------------|
| `pfunc(string)` | `translog` | Production function: `cd` or `translog` |
| `omegapoly(#)` | 3 | Productivity evolution polynomial order (1–4) |
| `attperiods(#)` | 4 | Maximum post-treatment event-time horizon |
| `nsim(#)` | 100 | Number of Monte Carlo simulation paths |
| `bootstrap(#)` | 0 | Bootstrap replications (0 = point only) |
| `by(varname)` | — | Group-by variable (e.g., industry) |
| `control(varlist)` | — | Controls for first-stage regression |
| `seed(#)` | 123456 | Seed for reproducibility |
| `level(#)` | `c(level)` | Confidence level for bootstrap CIs |
| `treatdependent` | — | Treatment-dependent production function |
| `verbose` | — | Full diagnostic output |
| `nolog` | — | Suppress all progress output |

For complete syntax including all advanced options, see `help pte` after
installation.

**Requirements:**

- **Stata 14.0** or later
- No additional dependencies for baseline estimation

| Optional Package | Required For | Install |
|-----------------|-------------|---------|
| `reghdfe` | `pte_compare` (TWFE comparison) | `ssc install reghdfe` |
| `prodest` / `endopolyprodest` | Treatment-dependent workflows | `ssc install prodest` |
| `parallel` | Parallel bootstrap acceleration | `ssc install parallel` |

Run `pte_check_deps` to verify all dependencies before advanced workflows.

### 3.4 Quick Start

The simplest use case estimates a Cobb-Douglas production function with the CLK
correction and computes the ATT over a default 4-period horizon.

```stata
* Load bundled example dataset
pte_example, clear
xtset firm year

* Estimate productivity treatment effects
pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) pfunc(cd)
```

**Expected output:**

```
----------------------------------------------------------------------
 Productivity Treatment Effects (PTE) - Cobb-Douglas
----------------------------------------------------------------------
  Step 1/4: Production function estimation... done (fval =  3.3e-07)
  Step 2/4: Productivity recovery... done
  Step 3/4: ATT estimation... done
  Step 4/4: Complete
----------------------------------------------------------------------

----------------------------------------------------------------------
Production Function Estimates               Number of obs   =     4,350
  Method: ACF with CLK correction           GMM sample      =     4,350
  Trim eps0: 1%-99%                         Firms           =       500
----------------------------------------------------------------------
    beta_l         =  0.597035
    beta_k         =  0.409394
    GMM obj        =  3.34e-07
----------------------------------------------------------------------
ATT Results (event time 0..4)               Sim. paths      =       100
----------------------------------------------------------------------
 Period |        ATT   Std.Dev.        N
 -------+-----------------------------------
      0 |     0.0004      0.0239       150
      1 |    -0.0001      0.0190       150
      2 |    -0.0002      0.0159       150
      3 |     0.0018      0.0198       150
      4 |     0.0069      0.0334       116
 -------+-----------------------------------
    avg |     0.0015
----------------------------------------------------------------------
```

**Interpreting the output:**

| Field | Meaning |
|-------|---------|
| `beta_l` | Labor output elasticity: 1% more labor → ~0.60% more output |
| `beta_k` | Capital output elasticity: 1% more capital → ~0.41% more output |
| `GMM obj` | Objective value at convergence (< 1e-5 indicates good fit) |
| `Period` | Event time relative to treatment adoption (0 = year of treatment) |
| `ATT` | Estimated causal effect on log productivity at that horizon |
| `N` | Number of treated firms observed at that event time |
| `avg` | Simple average ATT across all post-treatment periods |

- ATT > 0 means treatment *raised* productivity; ATT < 0 means it *lowered* it
- Values are in log points; multiply by 100 for approximate percentage change
- For statistical significance, add `bootstrap(200)` to obtain SEs and CIs

### 3.5 Stored Results

After estimation, `pte` stores results in `e()`. Key entries:

| Name | Type | Description |
|------|------|-------------|
| `e(N)` | scalar | Number of observations |
| `e(N_g)` | scalar | Number of firms |
| `e(ATT_avg)` | scalar | Average ATT across post-treatment periods |
| `e(att_0)`...`e(att_k)` | scalar | ATT at each event-time horizon |
| `e(att)` | matrix | Full ATT vector: [nt0, ..., ntK, avg] |
| `e(att_se)` | matrix | Bootstrap standard errors |
| `e(att_ci_lower)` | matrix | Lower confidence bound |
| `e(att_ci_upper)` | matrix | Upper confidence bound |
| `e(b_by)` | matrix | Production function coefficients by group |
| `e(cmd)` | macro | `"pte"` |
| `e(pfunc)` | macro | Production function type (`cd`/`translog`) |
| `e(predict)` | macro | Prediction program (`pte_p`) |

For the complete list, type `ereturn list` after estimation or see `help pte`.

### 3.6 Troubleshooting

#### GMM Convergence Failure

**Symptom:** `GMM did not converge` or very large objective function value.

1. Check that your proxy variable is genuinely correlated with productivity.
2. Verify that variables are in logs and have reasonable variation.
3. Try `omegapoly(2)` — lower polynomial orders are more stable with small
   samples.
4. Ensure sufficient time-series depth (≥ 5 periods recommended for Translog).

#### Sample Too Small for Bootstrap

**Symptom:** Bootstrap produces `missing` standard errors or unstable CIs.

1. You need at least ~50 treated firms for stable bootstrap inference.
2. Reduce `attperiods()` if later horizons have very few observations.
3. Consider pooled estimation if industry groups are too small.

#### ATT Results Seem Implausible

**Symptom:** ATT values are unreasonably large (|ATT| > 1 in logs).

1. Try switching between `cd` and `translog` to check robustness.
2. Check `verbose` output for outlier diagnostics.
3. Ensure sufficient pre-treatment periods for evolution estimation.
4. If firms switch back, use the non-absorbing extension.

#### Installation Issues

**`r(640)` error:** Install all three sub-packages (`pte`, `pte_more`,
`pte_more2`). Stata limits each package to 100 files.

**Connection timeout (China):** Configure HTTP proxy or use a mirror (see
Installation section).

**`pte_example` not found:** Verify with `which pte_example` and `pte_version`.

---

## 4. Empirical Application

This section demonstrates how to replicate the industry-level Translog results
from Chen, Liao & Schurter (2026) using the bundled **AI treatment dataset**
(`manuf_est_data.dta`). This publicly available dataset covers Chinese
manufacturing firms with an AI adoption treatment indicator.

> **Note:** The formal paper uses production digitalization treatment data with
> additional proprietary processing. The AI treatment dataset provided here is
> a publicly distributable version that produces qualitatively comparable
> results. Results match the authors' DO replication code to within < 1e-4.

### 4.1 Background

Chen, Liao & Schurter (2026) study how AI technology adoption affects firm-level
productivity in the Chinese manufacturing sector. Using a panel of manufacturing
firms over 2007–2019, the paper exploits staggered AI adoption timing across
firms to identify dynamic treatment effects on total factor productivity. The
`pte` package implements their CLK framework, enabling researchers to replicate
and extend these findings.

### 4.2 Data Preparation

The data preparation follows the authors' original DO code exactly:

```stata
* Load the bundled manufacturing estimation dataset
use "manuf_est_data.dta", clear

* Generate log wage and apply 1-99% trimming
gen w = log(wage_all / labor)
drop if w == .
foreach v of varlist lnk lny lnl w {
    quietly summarize `v', detail
    quietly replace `v' = . if `v' < r(p1) | `v' > r(p99)
}
drop if lnk == . | lny == . | lnl == .

* Industry classification (keep manufacturing sub-sectors 3-8)
gen Ind1_str = substr(IndcodeA, 2, 1)
destring Ind1_str, gen(Ind1_num)
drop if Ind1_num == 1 | Ind1_num == 2 | Ind1_num == 9

* Set up panel structure
gen t = year
egen firm = group(Scode)
xtset firm year

* Generate treatment and industry grouping
gen treat_post = treat
egen indid_adj = group(Ind1_num)
```

After preparation, the estimation sample contains **16,396 firm-year
observations** across **7 industry groups**.

### 4.3 Estimation

```stata
pte lny, treatment(treat_post) free(lnl) state(lnk) proxy(lnm) control(t) ///
    pfunc(translog) omegapoly(3) nsim(100) attperiods(3) ///
    industry(indid_adj) nolog
```

Key options:
- `pfunc(translog)`: Translog production function (non-constant returns to scale
  and input complementarities)
- `omegapoly(3)`: Third-order polynomial for productivity evolution
- `nsim(100)`: 100 Monte Carlo simulation paths per treated firm
- `attperiods(3)`: Compute ATT at event times 0, 1, 2, 3
- `industry(indid_adj)`: Separate estimation for each industry group

### 4.4 Results

**Estimation summary:**

```
------------------------------------------------------------------------------
Productivity Treatment Effects Estimation
------------------------------------------------------------------------------
Production function     = Translog
Method                  = ACF with CLK correction
Trim eps0               = on (1%-99%)
Evolution order         =   3
Confidence level        = 95%
------------------------------------------------------------------------------
Number of obs           =     13,107
Number of firms         =      1,970
Transition obs          =        611 (excluded from GMM)
Treated firms           =        756
Control firms           =      1,214
Obs per group:          min =  542  avg = 2342.3  max = 5846
```

**Production function parameters (by industry group):**

```
           beta_l      beta_k     beta_l2     beta_k2     beta_lk      beta_t
grp_1   1.0929103  -2.3280915  -.04273452    .0664468   .00512558   .03907583
grp_2   -1.515449  -1.3950415   .09524972   .02546215   .02777702   .01802732
grp_3    2.193069  -3.0618457   .09872855   .11497736  -.16539796           0
grp_4    1.445856  -2.6114523   .13169326   .09761308  -.14637569           0
grp_5  -.60279275  -.49478396   .12512838   .02667593  -.04246532           0
grp_6   1.3140991   -2.724878   .06305955   .08908596  -.08879547           0
grp_7   .92691682   -1.057757   .12654775   .05303502  -.11562746           0
```

**ATT results (by industry group and pooled):**

```
------------------------------------------------------------------------------
 Results by: indid_adj
------------------------------------------------------------------------------
indid_adj          ATT_0       ATT_1       ATT_2       ATT_3     ATT_avg
------------------------------------------------------------------------------
1      0.0224      0.0382      0.0959      0.1209      0.0433
2     -0.0266      0.0482      0.1056      0.0226      0.0297
3     -0.0109      0.0445      0.0867      0.1722      0.0307
4      0.0232      0.0496      0.0378      0.1543      0.0424
5      0.0404      0.1173      0.1014      0.0769      0.0612
6      0.0288      0.0353      0.0199      0.0542      0.0307
7      0.0741      0.0480     -0.0519           .      0.0471
------------------------------------------------------------------------------
Pooled      0.0248      0.0436      0.0350      0.0871      0.0361
------------------------------------------------------------------------------
```

### 4.5 Interpretation

**Production function:**

- The Translog specification captures industry-specific technologies. The
  squared terms (`beta_l2`, `beta_k2`) and interaction (`beta_lk`) allow
  non-constant returns and input complementarities that vary by sector.

**Treatment effects:**

- **Pooled ATT_avg = 0.036**: AI adoption raises firm productivity by
  approximately 3.6 log points (~3.7%) on average across post-treatment periods.
- **Growing dynamic effect**: The ATT increases from 2.5% at event time 0
  to 8.7% at event time 3, suggesting that AI treatment effects accumulate
  over time as firms learn to exploit the technology.
- **Industry heterogeneity**: Effects vary substantially across sectors.
  Industry 5 shows the strongest average effect (6.1%), while Industry 2
  shows the weakest (3.0%). This reflects differential AI applicability
  across manufacturing sub-sectors.
- **Immediate vs. gradual**: Most industries show positive effects from
  period 0, indicating that AI adoption generates productivity gains even
  in the year of adoption — consistent with the paper's finding that modern
  digital technologies have shorter learning curves than traditional capital
  investments.

**Comparison with paper:**

These results match the authors' replication DO code
(`att_estimation_industry_trlg_nonlinear.do`) to within numerical precision
(< 1e-4 on all parameters). The small differences arise from floating-point
ordering in Mata's matrix operations and do not affect economic conclusions.

---

## 5. Conclusion

### Citation

If you use `pte` in your research, please cite both the methodology paper and
the software:

**Methodology paper:**

> Chen, Z., Liao, M., & Schurter, K. (2026). Identifying Treatment Effects on
> Productivity: Theory with an Application to Production Digitalization.
> *RAND Journal of Economics*.

**Software:**

> Cai, X. & Xu, W. (2026). *pte: Stata module for Productivity Treatment
> Effects estimation* (Version 1.0.0) [Computer software].
> https://github.com/gorgeousfish/pte

**BibTeX:**

```bibtex
@article{chen2026pte,
  title   = {Identifying Treatment Effects on Productivity: Theory with an
             Application to Production Digitalization},
  author  = {Chen, Zhiyuan and Liao, Moyu and Schurter, Karl},
  journal = {RAND Journal of Economics},
  year    = {2026}
}

@software{pte2026stata,
  title   = {pte: Stata module for Productivity Treatment Effects estimation},
  author  = {Cai, Xuanyu and Xu, Wenli},
  year    = {2026},
  version = {1.0.0},
  url     = {https://github.com/gorgeousfish/pte}
}
```

### Authors

- **Xuanyu Cai**, City University of Macau
  — [xuanyuCAI@outlook.com](mailto:xuanyuCAI@outlook.com)
- **Wenli Xu**, City University of Macau
  — [wlxu@cityu.edu.mo](mailto:wlxu@cityu.edu.mo)
- **Zhiyuan Chen**, University of Zurich
- **Moyu Liao**, City University of Macau

### License

AGPL-3.0. See [LICENSE](LICENSE) for details.
