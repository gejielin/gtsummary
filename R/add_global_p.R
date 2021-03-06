#' Add the global p-values
#'
#' This function uses `car::Anova(type = "III")` to calculate global p-values variables.
#' Output from `tbl_regression` and `tbl_uvregression` objects supported.
#'
#' @param x Object with class `tbl_regression` from the
#' [tbl_regression] function
#' @param keep Logical argument indicating whether to also retain the individual
#' p-values in the table output for each level of the categorical variable.
#' Default is `FALSE`
#' @param include Variables to calculate global p-value for. Input may be a vector of
#' quoted or unquoted variable names. Default is `everything()`
#' @param quiet Logical indicating whether to print messages in console. Default is
#' `FALSE`
#' @param terms DEPRECATED.  Use `include=` argument instead.
#' @param type Type argument passed to [car::Anova]. Default is `"III"`
#' @param ... Additional arguments to be passed to [car::Anova]
#' @author Daniel D. Sjoberg
#' @export
#' @examples
#' # Example 1 ----------------------------------
#' tbl_lm_global_ex1 <-
#'   lm(marker ~ age + grade, trial) %>%
#'   tbl_regression() %>%
#'   add_global_p()
#'
#' # Example 2 ----------------------------------
#' tbl_uv_global_ex2 <-
#'   trial[c("response", "trt", "age", "grade")] %>%
#'   tbl_uvregression(
#'     method = glm,
#'     y = response,
#'     method.args = list(family = binomial),
#'     exponentiate = TRUE
#'   ) %>%
#'   add_global_p()
#'
#' @family tbl_uvregression tools
#' @family tbl_regression tools
#' @section Example Output:
#' \if{html}{Example 1}
#'
#' \if{html}{\figure{tbl_lm_global_ex1.png}{options: width=45\%}}
#'
#' \if{html}{Example 2}
#'
#' \if{html}{\figure{tbl_uv_global_ex2.png}{options: width=50\%}}

add_global_p <- function(x, ...) {
  # must have car package installed to use this function
  assert_package("car", "add_global_p()")
  UseMethod("add_global_p")
}

#' @name add_global_p
#' @export
add_global_p.tbl_regression <- function(x, include = everything(), type = NULL,
                                        keep = FALSE, quiet = NULL, ..., terms = NULL) {
  # deprecated arguments -------------------------------------------------------
  if (!is.null(terms)) {
    lifecycle::deprecate_warn(
      "1.2.5", "gtsummary::add_global_p.tbl_regression(terms = )",
      "add_global_p.tbl_regression(include = )"
    )
    include <- terms
  }

  # setting defaults -----------------------------------------------------------
  quiet <- quiet %||% get_theme_element("pkgwide-lgl:quiet") %||% FALSE
  type <- type %||% get_theme_element("add_global_p-str:type", default = "III")

  # converting to character vector ---------------------------------------------
  include <-
    .select_to_varnames(
      select = {{ include }},
      var_info = x$table_body,
      arg_name = "include"
    )

  # if no terms are provided, stop and return x
  if (length(include) == 0) {
    if (quiet == FALSE)
      paste("No terms were selected, and no global p-values were added to the table.",
            "The default behaviour is to add global p-values for categorical and ",
            "interaction terms. To obtain p-values for other terms,",
            "update the `include=` argument.") %>%
      stringr::str_wrap() %>%
      message()
    return(x)
  }

  # vetted model geeglm not supported here.
  if (inherits(x$inputs$x, "geeglm")) {
    rlang::abort(paste(
      "Model class `geeglm` not supported by `car::Anova()`,",
      "and function could not calculate requested p-value."
    ))
  }

  # printing analysis performed
  if (quiet == FALSE) {
    expr_car <-
      rlang::expr(car::Anova(x$model_obj, type = !!type, !!!list(...))) %>%
      deparse()

    paste("add_global_p: Global p-values for variable(s)",
          glue("`add_global_p(include = {deparse(include) %>% paste(collapse = '')})`"),
          glue("were calculated with")) %>%
      stringr::str_wrap() %>%
      paste(glue("`{expr_car}`"), sep = "\n  ") %>%
      rlang::inform()
  }

  # calculating global pvalues
  tryCatch(
    {
      car_Anova <-
        x$model_obj %>%
        car::Anova(type = type, ...)
    },
    error = function(e) {
      ui_oops(paste0(
        "{ui_code('add_global_p()')} uses ",
        "{ui_code('car::Anova()')} to calculate the global p-value,\n",
        "and the function returned an error while calculating the p-values.\n",
        "Is your model type supported by {ui_code('car::Anova()')}?"
      ))
      stop(e)
    }
  )
  global_p <-
    car_Anova %>%
    as.data.frame() %>%
    tibble::rownames_to_column(var = "variable") %>%
    mutate(variable = broom.helpers::.clean_backticks(.data$variable)) %>%
    filter(.data$variable %in% !!include) %>%
    select(c("variable", starts_with("Pr(>"))) %>% # selecting the pvalue column
    set_names(c("variable", "p.value_global")) %>%
    mutate(row_type = "label")

  # merging in global pvalue ---------------------------------------------------
  # adding p-value column, if it is not already there
  if (!"p.value" %in% names(x$table_body)) {
    # adding p.value to table_body
    x$table_body <- mutate(x$table_body, p.value = NA_real_)
    # adding to table_header
    x$table_header <-
      tibble(column = names(x$table_body)) %>%
      left_join(x$table_header, by = "column") %>%
      table_header_fill_missing() %>%
      table_header_fmt_fun(
        p.value = x$inputs$pvalue_fun %||%
          getOption("gtsummary.pvalue_fun", default = style_pvalue)
      )
    x <- modify_header(x, p.value = "**p-value**")
  }
  # adding global p-values
  x$table_body <-
    x$table_body %>%
    left_join(
      global_p,
      by = c("row_type", "variable")
    ) %>%
    mutate(
      p.value = coalesce(.data$p.value_global, .data$p.value)
    ) %>%
    select(-c("p.value_global"))

  # if keep == FALSE, then deleting variable-level p-values
  if (keep == FALSE) {
    x$table_body <-
      x$table_body %>%
      mutate(
        p.value = if_else(.data$variable %in% !!include & .data$row_type == "level",
          NA_real_, .data$p.value
        )
      )
  }

  x$call_list <- c(x$call_list, list(add_global_p = match.call()))

  return(x)
}

#' @name add_global_p
#' @export
add_global_p.tbl_uvregression <- function(x, type = NULL, include = everything(),
                                          keep = FALSE, quiet = NULL, ...) {
  # setting defaults -----------------------------------------------------------
  quiet <- quiet %||% get_theme_element("pkgwide-lgl:quiet") %||% FALSE
  type <- type %||% get_theme_element("add_global_p-str:type", default = "III")

  # converting to character vector ---------------------------------------------
  include <-
    .select_to_varnames(
      select = {{ include }},
      var_info = x$table_body,
      arg_name = "include"
    )

  # capturing dots in expression
  dots <- rlang::enexprs(...)

  # printing analysis performed
  if (quiet == FALSE) {
    expr_car <-
      rlang::expr(car::Anova(mod = x$model_obj, type = !!type, !!!list(...))) %>%
      deparse()

    paste("add_global_p: Global p-values for variable(s)",
          glue("`add_global_p(include = {deparse(include) %>% paste(collapse = '')})`"),
          glue("were calculated with")) %>%
      stringr::str_wrap() %>%
      paste(glue("`{expr_car}`"), sep = "\n  ") %>%
      rlang::inform()
  }

  # calculating global pvalues
  global_p <-
    imap_dfr(
      x$tbls[include],
      function(x, y) {
        tryCatch(
          {
            car_Anova <-
              rlang::call2(
                car::Anova, mod = x[["model_obj"]], type = type, !!!dots
              ) %>%
              rlang::eval_tidy()
          },
          error = function(e) {
            ui_oops(paste0(
              "{ui_code('add_global_p()')} uses ",
              "{ui_code('car::Anova()')} to calculate the global p-value,\n",
              "and the function returned an error while calculating the p-value ",
              "for {ui_value(y)}."
            ))
            stop(e)
          }
        )

        car_Anova %>%
          as.data.frame() %>%
          tibble::rownames_to_column(var = "variable") %>%
          mutate(variable = broom.helpers::.clean_backticks(.data$variable)) %>%
          filter(.data$variable == y) %>%
          select(c(
            "variable", starts_with("Pr(>")
          )) %>% # selecting the pvalue column
          set_names(c("variable", "p.value_global"))
      }
    ) %>%
    select(c("variable", "p.value_global"))

  # adding global p-value to meta_data object
  x$meta_data <-
    x$meta_data %>%
    left_join(
      global_p,
      by = "variable"
    )

  # merging in global pvalue ---------------------------------------------------
  # adding p-value column, if it is not already there
  if (!"p.value" %in% names(x$table_body)) {
    # adding p.value to table_body
    x$table_body <- mutate(x$table_body, p.value = NA_real_)
    # adding to table_header
    x$table_header <-
      tibble(column = names(x$table_body)) %>%
      left_join(x$table_header, by = "column") %>%
      table_header_fill_missing() %>%
      table_header_fmt_fun(p.value = x$inputs$pvalue_fun)
    x <- modify_header(x, p.value = "**p-value**")
  }
  # adding global p-values
  x$table_body <-
    x$table_body %>%
    left_join(
      global_p %>% mutate(row_type = "label"),
      by = c("row_type", "variable")
    ) %>%
    mutate(
      p.value = coalesce(.data$p.value_global, .data$p.value)
    ) %>%
    select(-c("p.value_global"))

  # if keep == FALSE, then deleting variable-level p-values
  if (keep == FALSE) {
    x$table_body <-
      x$table_body %>%
      mutate(
        p.value = if_else(.data$variable %in% !!include & .data$row_type == "level",
                          NA_real_, .data$p.value
        )
      )
  }

  x$call_list <- c(x$call_list, list(add_global_p = match.call()))

  return(x)
}
