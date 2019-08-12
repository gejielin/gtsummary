#' Display regression model results in table
#'
#' This function uses [broom::tidy] and [broom.mixed::tidy]
#' to perform the initial model formatting. Review the
#' \href{http://www.danieldsjoberg.com/gtsummary/articles/tbl_regression.html}{tbl_regression vignette}
#' for detailed examples.
#'
#' @section Setting Defaults:
#' If you prefer to consistently use a different function to format p-values or
#' estimates, you can set options in the script or in the user- or
#' project-level startup file, '.Rprofile'.  The default confidence level can
#' also be set.
#' \itemize{
#'   \item `options(gtsummary.pvalue_fun = new_function)`
#'   \item `options(gtsummary.tbl_regression.estimate_fun = new_function)`
#'   \item `options(gtsummary.conf.level = 0.90)`
#' }
#'
#' @section Note:
#' The N reported in the `tbl_regression()` output is the number of observations
#' in the data frame `model.frame(x)`. Depending on the model input, this N
#' may represent different quantities. In most cases, it is the total number of
#' observations in your model; however, the precise definition of an observation,
#' or unit of analysis, may differ across models. Here are some common examples.
#' 1. Survival regression models including time dependent covariates.
#' 2. Random- or mixed-effects regression models with clustered data.
#' 3. GEE regression models with clustered data.
#'
#' This list is not exhaustive, and care should be taken for each number reported.
#'
#' @param x Regression model object
#' @param exponentiate Logical indicating whether to exponentiate the
#' coefficient estimates. Default is `FALSE`.
#' @param label List of formulas specifying variables labels,
#' e.g. `list("age" ~ "Age, yrs", "ptstage" ~ "Path T Stage")`
#' @param include Names of variables to include in output.
#' @param exclude Names of variables to exclude from output.
#' @param conf.level Must be strictly greater than 0 and less than 1.
#' Defaults to 0.95, which corresponds to a 95 percent confidence interval.
#' @param intercept Logical argument indicating whether to include the intercept
#' in the output.  Default is `FALSE`
#' @param show_yesno By default yes/no categorical variables are printed on a
#' single row, when the 'No' category is the reference group.  To print both
#' levels in the output table, include the variable name in the show_yesno
#' vector, e.g. `show_yesno = c("var1", "var2")``
#' @param estimate_fun Function to round and format coefficient estimates.
#' Default is [style_sigfig] when the coefficients are not transformed, and
#' [style_ratio] when the coefficients have been exponentiated.
#' @param pvalue_fun Function to round and format p-values.
#' Default is [style_pvalue].
#' The function must have a numeric vector input (the numeric, exact p-value),
#' and return a string that is the rounded/formatted p-value (e.g.
#' `pvalue_fun = function(x) style_pvalue(x, digits = 2)` or equivalently,
#'  `purrr::partial(style_pvalue, digits = 2)`).
#' @author Daniel D. Sjoberg
#' @seealso See tbl_regression \href{http://www.danieldsjoberg.com/gtsummary/articles/tbl_regression.html}{vignette} for detailed examples
#' @family tbl_regression tools
#' @export
#' @return A `tbl_regression` object
#' @examples
#' library(survival)
#' tbl_regression_ex1 <-
#'   coxph(Surv(ttdeath, death) ~ age + marker, trial) %>%
#'   tbl_regression(exponentiate = TRUE)
#'
#' tbl_regression_ex2 <-
#'   glm(response ~ age + grade, trial, family = binomial(link = "logit")) %>%
#'   tbl_regression(exponentiate = TRUE)
#'
#' library(lme4)
#' tbl_regression_ex3 <-
#'   glmer(am ~ hp + (1 | gear), mtcars, family = binomial) %>%
#'   tbl_regression(exponentiate = TRUE)
#' @section Example Output:
#' \if{html}{Example 1}
#'
#' \if{html}{\figure{tbl_regression_ex1.png}{options: width=64\%}}
#'
#' \if{html}{Example 2}
#'
#' \if{html}{\figure{tbl_regression_ex2.png}{options: width=50\%}}
#'
#' \if{html}{Example 3}
#'
#' \if{html}{\figure{tbl_regression_ex3.png}{options: width=50\%}}
#'
tbl_regression <- function(x, label = NULL, exponentiate = FALSE,
                           include = NULL, exclude = NULL,
                           show_yesno = NULL, conf.level = NULL, intercept = FALSE,
                           estimate_fun = NULL, pvalue_fun = NULL) {
  # setting defaults -----------------------------------------------------------
  pvalue_fun <-
    pvalue_fun %||%
    getOption("gtsummary.pvalue_fun", default = style_pvalue)
  estimate_fun <-
    estimate_fun %||%
    getOption(
      "gtsummary.tbl_regression.estimate_fun",
      default = ifelse(exponentiate == TRUE, style_ratio, style_sigfig)
    )
  conf.level <-
    conf.level %||%
    getOption("gtsummary.conf.level", default = 0.95)

  # checking estimate_fun and pvalue_fun are functions
  if (!is.function(estimate_fun) | !is.function(pvalue_fun)) {
    stop("Inputs 'estimate_fun' and 'pvalue_fun' must be functions.")
  }

  # label ----------------------------------------------------------------------
  if (!is.null(label) & is.null(names(label))) { # checking names for deprecated named list input

    # checking input type: must be a list of formulas, or one formula
    if (!class(label) %in% c("list", "formula")) {
      stop(glue(
        "'label' argument must be a list of formulas. ",
        "LHS of the formula is the variable specification, ",
        "and the RHS is the label specification: ",
        "list(vars(stage) ~ \"T Stage\")"
      ))
    }
    if ("list" %in% class(label)) {
      if (purrr::some(label, negate(rlang::is_bare_formula))) {
        stop(glue(
          "'label' argument must be a list of formulas. ",
          "LHS of the formula is the variable specification, ",
          "and the RHS is the label specification: ",
          "list(vars(stage) ~ \"T Stage\")"
        ))
      }
    }

    # all sepcifed labels must be a string of length 1
    if ("formula" %in% class(label)) label <- list(label)
    if (!every(label, ~ rlang::is_string(eval(rlang::f_rhs(.x))))) {
      stop(glue(
        "The RHS of the formula in the 'label' argument must be a string."
      ))
    }
  }

  # converting tidyselect formula lists to named lists
  label <- tidyselect_to_list(stats::model.frame(x), label, input_type = "label")

  # will return call, and all object passed to in tbl_regression call
  # the object func_inputs is a list of every object passed to the function
  func_inputs <- as.list(environment())

  # using broom and broom.mixed to tidy up regression results, and
  # then reversing order of data frame
  tidy_model <-
    tidy_wrap(x, exponentiate, conf.level)

  # parsing the terms from model and variable names
  # outputing a tibble of the parsed model with
  # rows for reference groups, and headers for
  # categorical variables
  table_body <- parse_fit(x, tidy_model, label, show_yesno)

  # including and excluding variables/intercept indicated
  # Note, include = names(stats::model.frame(mod_nlme))
  # has an error for nlme because it is "reStruct"
  if (!is.null(include)) {
    include_err <- include %>% setdiff(table_body$variable %>% unique())
    if (length(include_err) > 0) {
      stop(glue(
        "'include' must be be a subset of '{paste(table_body$variable %>% unique(), collapse = ', ')}'"
      ))
    }
  }
  if (is.null(include)) include <- table_body$variable %>% unique()
  if (intercept == FALSE) include <- include %>% setdiff("(Intercept)")
  include <- include %>% setdiff(exclude)

  # keeping variables indicated in `include`
  table_body <-
    table_body %>%
    filter(.data$variable %in% include)

  # model N
  n <- stats::model.frame(x) %>% nrow()

  # table of column headers
  table_header <-
    tibble(column = names(table_body)) %>%
    table_header_fill_missing() %>%
    table_header_fmt(
      p.value = "x$inputs$pvalue_fun",
      estimate = "x$inputs$estimate_fun",
      conf.low = "x$inputs$estimate_fun",
      conf.high = "x$inputs$estimate_fun"
    )

  # footnote abbreviation details
  footnote_abbr <-
    estimate_header(x, exponentiate) %>%
    attr("footnote") %>%
    c("CI = Confidence Interval") %>%
    paste(collapse = ", ")
  footnote_location <- ifelse(
    is.null(attr(estimate_header(x, exponentiate), "footnote")),
    "vars(conf.low)",
    "vars(estimate, conf.low)"
  )

  results <- list(
    table_body = table_body,
    table_header = table_header,
    n = n,
    model_obj = x,
    inputs = func_inputs,
    call_list = list(tbl_regression = match.call()),
    gt_calls = eval(gt_tbl_regression),
    kable_calls = eval(kable_tbl_regression)
  )

  # setting column headers
  results <- modify_header_internal(
    results,
    label = "**N = {n}**",
    estimate = glue("**{estimate_header(x, exponentiate)}**"),
    conf.low = glue("**{style_percent(conf.level, symbol = TRUE)} CI**"),
    p.value = "**p-value**"
  )

  # writing additional gt and kable calls with data from table_header
  results <- update_calls_from_table_header(results)

  # assigning a class of tbl_regression (for special printing in Rmarkdown)
  class(results) <- "tbl_regression"

  results
}

# gt function calls ------------------------------------------------------------
# quoting returns an expression to be evaluated later
gt_tbl_regression <- quote(list(
  # first call to the gt function
  gt = "gt::gt(data = x$table_body)" %>%
    glue(),

  # label column indented and left just
  cols_align = glue(
    "gt::cols_align(align = 'center') %>% ",
    "gt::cols_align(align = 'left', columns = gt::vars(label))"
  ),

  # NAs do not show in table
  fmt_missing = "gt::fmt_missing(columns = gt::everything(), missing_text = '')" %>%
    glue(),

  # Show "---" for reference groups
  fmt_missing_ref =
    "gt::fmt_missing(columns = gt::vars(estimate, conf.low, conf.high), rows = row_ref == TRUE, missing_text = '---')" %>%
      glue(),

  # column headers abbreviations footnote
  footnote_abbreviation = glue(
    "gt::tab_footnote(",
    "footnote = '{footnote_abbr}', ",
    "locations = gt::cells_column_labels(",
    "columns = {footnote_location})",
    ")"
  ),

  # combining conf.low and conf.high to print confidence interval
  cols_merge_ci =
    "gt::cols_merge(col_1 = gt::vars(conf.low), col_2 = gt::vars(conf.high), pattern = '{1}, {2}')" %>%
      glue::as_glue(),

  # indenting levels and missing rows
  tab_style_text_indent = glue(
    "gt::tab_style(",
    "style = gt::cell_text(indent = gt::px(10), align = 'left'),",
    "locations = gt::cells_data(",
    "columns = gt::vars(label), ",
    "rows = row_type != 'label'",
    "))"
  )
))


# kable function calls ------------------------------------------------------------
# quoting returns an expression to be evaluated later
kable_tbl_regression <- quote(list(
  # first call to the gt function
  kable = glue("x$table_body"),

  #  placeholder, so the formatting calls are performed other calls below
  fmt = NULL,

  # combining conf.low and conf.high to print confidence interval
  cols_merge_ci =
    "dplyr::mutate(conf.low = ifelse(is.na(estimate), NA, glue::glue('{conf.low}, {conf.high}') %>% as.character()))" %>% glue::as_glue(),

  # Show "---" for reference groups
  fmt_missing_ref = glue(
    "dplyr::mutate_at(dplyr::vars(estimate, conf.low), ",
    "~ dplyr::case_when(row_ref == TRUE ~ '---', TRUE ~ .))"
  )
))



# identifies headers for common models (logistic, poisson, and cox regression)
estimate_header <- function(x, exponentiate) {
  if (
    (class(x)[1] %in% c("glm", "geeglm")) | # generalized linear models, and GEE GLMs
      (class(x)[1] == "glmerMod" & attr(class(x), "package") %||% "NULL" == "lme4") # mixed effects models (from lme4 package)
  ) {
    if (class(x)[1] %in% c("glm", "geeglm")) {
      family <- x$family
    } else if (class(x)[1] == "glmerMod" & attr(class(x), "package") %||% "NULL" == "lme4") {
      family <- x@resp$family
    } else {
      stop("Error occured in 'estimate_header' function")
    }

    # logistic regression
    if (exponentiate == TRUE & family$family == "binomial" & family$link == "logit") {
      header <- "OR"
      attr(header, "footnote") <- "OR = Odds Ratio"
    }
    else if (exponentiate == FALSE & family$family == "binomial" & family$link == "logit") {
      header <- "log(OR)"
      attr(header, "footnote") <- "OR = Odds Ratio"
    }

    # poisson regression with log link
    else if (exponentiate == TRUE & family$family == "poisson" & family$link == "log") {
      header <- "IRR"
      attr(header, "footnote") <- "IRR = Incidence Rate Ratio"
    }
    else if (exponentiate == FALSE & family$family == "poisson" & family$link == "log") {
      header <- "log(IRR)"
      attr(header, "footnote") <- "IRR = Incidence Rate Ratio"
    }

    # Other models
    else if (exponentiate == TRUE) {
      header <- "exp(Coefficient)"
    } else {
      header <- "Coefficient"
    }
  }
  # Cox PH Regression
  else if (class(x)[1] == "coxph" & exponentiate == TRUE) {
    header <- "HR"
    attr(header, "footnote") <- "HR = Hazard Ratio"
  }
  else if (class(x)[1] == "coxph" & exponentiate == FALSE) {
    header <- "log(HR)"
    attr(header, "footnote") <- "HR = Hazard Ratio"
  }

  # Other models
  else if (exponentiate == TRUE) {
    header <- "exp(Coefficient)"
  } else {
    header <- "Coefficient"
  }

  header
}