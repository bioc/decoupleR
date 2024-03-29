#' Univariate Linear Model (ULM)
#'
#' @description
#' Calculates regulatory activities using ULM.
#'
#' @details
#' ULM fits a linear model for each sample and regulator, where the observed
#' molecular readouts in mat are the response variable and the regulator weights
#' in net are the explanatory one. Target features with no associated weight
#' are set to zero. The obtained t-value from the fitted model is the activity
#' `ulm` of a given regulator.
#'
#' @inheritParams .decoupler_mat_format
#' @inheritParams .decoupler_network_format
#' @param sparse Deprecated parameter.
#' @param center Logical value indicating if `mat` must be centered by
#' [base::rowMeans()].
#' @param na.rm Should missing values (including NaN) be omitted from the
#'  calculations of [base::rowMeans()]?
#' @param minsize Integer indicating the minimum number of targets per source.
#'
#' @return A long format tibble of the enrichment scores for each source
#'  across the samples. Resulting tibble contains the following columns:
#'  1. `statistic`: Indicates which method is associated with which score.
#'  2. `source`: Source nodes of `network`.
#'  3. `condition`: Condition representing each column of `mat`.
#'  4. `score`: Regulatory activity (enrichment score).
#' @family decoupleR statistics
#' @export
#'
#' @importFrom stats coef lm summary.lm
#' @importFrom magrittr %<>% %>%
#' @importFrom dplyr ungroup
#' @examples
#' inputs_dir <- system.file("testdata", "inputs", package = "decoupleR")
#'
#' mat <- readRDS(file.path(inputs_dir, "mat.rds"))
#' net <- readRDS(file.path(inputs_dir, "net.rds"))
#'
#' run_ulm(mat, net, minsize=0)
run_ulm <- function(mat,
                    network,
                    .source = source,
                    .target = target,
                    .mor = mor,
                    .likelihood = likelihood,
                    sparse = FALSE,
                    center = FALSE,
                    na.rm = FALSE,
                    minsize = 5L
                    ) {

    # NSE vs. R CMD check workaround
    condition <- likelihood <- mor <- p_value <- score <-
    source <- statistic <- target <- NULL

    # Check for NAs/Infs in mat
    mat %<>% check_nas_infs

    network %>%
    # Convert to standard tibble: source-target-mor.
    rename_net(
        {{ .source }},
        {{ .target }},
        {{ .mor }},
        {{ .likelihood }}
    ) %>%
    filt_minsize(rownames(mat), ., minsize) %>%
    # Preprocessing -------------------------------------------------------
    .fit_preprocessing(mat, center, na.rm, sparse) %>%
    # Model evaluation ----------------------------------------------------
    {.ulm_analysis(.$mat, .$mor_mat)} %>%
    ungroup()

}

#' Wrapper to execute run_ulm() logic on preprocessed data
#'
#' Fit a linear regression between the value of expression and
#' the profile of its targets.
#'
#' @inheritParams run_ulm
#' @param mor_mat
#'
#' @inherit run_ulm return
#' @keywords intern
#' @importFrom stats cor pt
#' @importFrom dplyr inner_join mutate select arrange
#' @importFrom tibble as_tibble
#' @importFrom tidyr pivot_longer
#' @importFrom magrittr %<>% %>%
#' @noRd
.ulm_analysis <- function(mat, mor_mat) {

    # Compute dfs
    df <- nrow(mor_mat) - 2L

    # Fit univariate lm
    r <- cor(mor_mat, mat)

    # Compute t-value
    scores <- r * sqrt(df / ((1.0 - r + 1.0e-20) * (1.0 + r + 1.0e-20)))

    # Compute pvals
    pvals <- pt(q = abs(scores), df = df, lower.tail = FALSE) * 2L

    pivot_mat <- function(mat, value_col) {

        mat %>% t %>%
        as_tibble(rownames = 'condition') %>%
        pivot_longer(-condition, names_to = 'source', values_to = value_col)

    }

    scores %>%
    pivot_mat('score') %>%
    inner_join(
        pvals %>% pivot_mat('p_value'),
        by = c('condition', 'source')
    ) %>%
    mutate(statistic = "ulm", .before = 1L) %>%
    select(statistic, source, condition, score, p_value) %>%
    arrange(source, condition)

}
