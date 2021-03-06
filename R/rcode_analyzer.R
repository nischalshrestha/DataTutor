
#' Given a quoted dplyr chain code, return a list of intermediate expressions, including
#' the dataframe name expression.
#'
#' @param dplyr_tree quoted dplyr code
#' @param outputs list
#'
#' @return [`language`]
#'
#' @examples
#' recurse_dplyr(rlang::parse_expr("mtcars %>% select(cyl)"))
recurse_dplyr <- function(dplyr_tree, outputs = list()) {
  if (inherits(dplyr_tree, "name")) {
    return(list(dplyr_tree))
  }
  # get the output of the quoted expression so far
  base <- append(list(dplyr_tree), outputs)
  if (length(dplyr_tree) < 2) {
    stop("Error: Detected a verb in pipeline that is not a function call for:<br><pre><code>", rlang::expr_deparse(dplyr_tree), "</code></pre>")
  }
  return(
    append(recurse_dplyr(dplyr_tree[[2]]), base)
  )
}

#' Based on the type of tidyr/dplyr function used return whether or not
#' the type of change was internal (no visible change), visible, or none.
#'
#' @param verb_name
#'
#' @return a character
#' @export
#'
#' @examples
#' get_change_type("group_by")
get_change_type <- function(verb_name) {
  # rn this is just a fail-safe if we for some reason have not supported the correct
  # change type based on actual data; remove it in the future when we are confident of support.
  internal_verbs <- c(
    "group_by", "rowwise"
  )
  visible_verbs <- c(
    "select", "filter", "mutate", "transmute", "summarise", "summarize", "arrange", "rename", "rename_with", "distinct",
    "spread", "gather", "pivot_wider", "pivot_longer",  "distinct", "nest", "unnest"," hoist", "unnest_longer", "unnest_wider",
    "drop_na"
  )
  if (verb_name %in% internal_verbs) {
    return("internal")
  } else if (verb_name %in% visible_verbs) {
    return("visible")
  } else {
    return("none")
  }
}

# helper function to get the type of change from previous and current dataframe
get_data_change_type <- function(verb_name, prev_output, cur_output) {
  # set the change type for summary box
  change_type <- "none"
  data_same <- identical(prev_output, cur_output)
  prev_rowwise <- inherits(prev_output, "rowwise_df")
  cur_rowwise <- inherits(cur_output, "rowwise_df")
  prev_grouped <- is_grouped_df(prev_output)
  cur_grouped <- is_grouped_df(cur_output)
  if (data_same) {
    change_type <- "none"
  } else {
    change_type <- "visible"
    if(!verb_name %in% c("summarize", "summarise")) {
      # rowwise case
      if ((!prev_rowwise && cur_rowwise) || (prev_rowwise && !cur_rowwise)) {
        change_type <- "internal"
      } else if(
        (verb_name %in% c("group_by", "ungroup")) &&
        # grouped vs ungrouped or grouped vs grouped case
        ((!prev_grouped && cur_grouped) || (prev_grouped && !cur_grouped) ||
        (prev_grouped && cur_grouped && !identical(group_vars(prev_output), group_vars(cur_output))))
      ) {
        change_type <- "internal"
      }
    }
  }
  return(change_type)
}

#' Given a quoted dplyr chained code, return a list of intermediate outputs.
#'
#' If there is an error, \code{get_dplyr_intermediates} will return outputs up to that
#' line, with an error message for the subsequent line at fault.
#'
#' @param pipeline quoted dplyr code
#'
#' @return list(
#'   intermediates = list(`tibble`),
#'   error = character(),
#' )
#'
#' @export
#' @examples
#' require(tidyverse)
#' "diamonds %>%
#'   select(carat, cut, color, clarity, price) %>%
#'   group_by(color) %>%
#'   summarise(n = n(), price = mean(price)) %>%
#'   arrange(desc(color))" -> pipeline
#' quoted <- rlang::parse_expr(pipeline)
#' outputs <- get_dplyr_intermediates(quoted)
get_dplyr_intermediates <- function(pipeline) {
  clear_verb_summary()
  clear_callouts()
  old_verb_summary <- ""
  # only data line
  if (inherits(pipeline, "name")) {
    output <- eval(pipeline)
    return(list(
      list(
        line = 1,
        code = rlang::expr_deparse(pipeline),
        change = "none",
        output = output,
        row = dim(output)[[1]],
        col = dim(output)[[2]],
        summary = paste("<strong>Summary:</strong>", tidylog::get_data_summary(output))
      )
    ))
  }

  # if first part of ast is not a %>% just quit
  # or if only a verb by itself was supplied (via. data argument)
  if (!identical(pipeline[[1]], as.symbol("%>%"))) {
    # message("`pipeline` input is not a pipe call!")
    return(list(
      list(
        line = 1,
        code = rlang::expr_deparse(pipeline),
        change = "error",
        output = list(),
        row = "",
        col = "",
        summary = "<strong>Summary:</strong> Invalid line! Are you missing a .data parameter for this call?"
      )
    ))
  }

  lines <- NULL
  # first grab all of the lines as a list of of language objects
  # potentially we could error out when trying to recursive invalid pipelines (for e.g. bad order of lines)
  err <- NULL
  tryCatch({
      lines <- recurse_dplyr(pipeline)
    },
    error = function(e) {
      err <<- crayon::strip_style(e$message)
    }
  )
  # if so, just return with error message (currently not being used in front-end)
  if (!is.null(err)) {
    return(err)
  }

  results <- list()
  for (i in seq_len(length(lines))) {
    if (i != 1) {
      verb <- lines[[i]][[3]]
      verb_name <- rlang::expr_deparse(verb[[1]])
    } else {
      verb <- lines[[i]]
      verb_name <- ""
    }
    # get the deparsed character version
    # NOTE: rlang::expr_deparse breaks apart long strings into multiple character vector
    # we collapse it before further processing to avoid extra \t
    deparsed <- paste0(rlang::expr_deparse(verb), collapse = "")

    # TODO: try to autolink the verb to its doc in future iterations
    # if (length(verb) > 1) {
    #   link_verb <- downlit::autolink_url(paste0("dplyr::", verb[[1]]))
    #   url_deparsed <- paste0("dplyr::", deparsed)
    #   deparsed <- gsub(as.character(verb[[1]]), paste0("<a href=", link_verb, ">", verb[[1]], "</a>"), url_deparsed)
    #   deparsed <- gsub("dplyr::", "", deparsed)
    # }

    # append a pipe character %>% unless it's the last line
    if (i < length(lines)) {
      deparsed <- paste0(deparsed, " %>%")
    }
    # also append a tab character if not the first line
    if (i > 1) {
      deparsed <- paste0("\t", deparsed)
    }
    # TODO change should be more intelligent based on data properties that changed or not, and tying into internal changes
    intermediate <- list(line = i, code = deparsed, change = get_change_type(verb_name))
    err <- NULL
    tryCatch({
        intermediate["output"] <- list(eval(lines[[i]]))
        intermediate["row"] <- dim(intermediate["output"][[1]])[[1]]
        intermediate["col"] <- dim(intermediate["output"][[1]])[[2]]
        verb_summary <- get_verb_summary()
        # we would have the same summary when tidylog does not support a certain
        # verb, so let's set it to empty string if that's the case.
        verb_summary <- ifelse(is.null(verb_summary), "", verb_summary)
        # message("verb_summary: ", verb_summary)
        # message("old_verb_summary: ", old_verb_summary)
        # message("verb_callouts: ", get_line_callouts())
        intermediate["callouts"] <- list(get_line_callouts())
        if (i == 1) {
          verb_summary <- tidylog::get_data_summary(intermediate["output"][[1]])
        }
        intermediate["summary"] <-
          ifelse(is.null(verb_summary) || identical(verb_summary, old_verb_summary), "", paste("<strong>Summary:</strong>", verb_summary))
        # set the change type for summary box
        change_type <- "none"
        if (i > 1) {
          prev_output <- results[[i - 1]]["output"][[1]]
          cur_output <- intermediate["output"][[1]]
          change_type <- get_data_change_type(verb_name, prev_output, cur_output)
        }
        intermediate["change"] <- change_type
        old_verb_summary <- verb_summary
      },
      error = function(e) {
        err <<- e
      }
    )
    if (!is.null(err)) {
      # Thought: we could make even more readable messages
      # Error: Must group by variables found in `.data`.
      # * Column `colorr` is not found.
      # for e.g. we could replace the `.data` with the actual expression
      intermediate[["change"]] <- "error"
      msg <- ifelse(
        nzchar(err$message),
        crayon::strip_style(err$message),
        crayon::strip_style(paste0(err))
      )
      msg <- gsub("Error:", "<strong>Error:</strong>", msg)
      msg <- ifelse(!grepl("Error:", msg), paste("<strong>Error:</strong>", msg), msg)
      # style back the x's, i's, and *
      msg <- gsub("\nx", "<br><span style='color:red'>x</span>", msg)
      msg <- gsub("\n\u2139", "<br><span style='color:DodgerBlue'>\u2139</span>", msg)
      msg <- gsub("\n\\*", "<br>*", msg)
      intermediate[["err"]] <- msg
      # try to retain the format as much as possible by keeping it as HTML string
      results <- append(results, list(intermediate))
      return(results)
    }
    results <- append(results, list(intermediate))
  }

  return(results)
}

#' Given a quoted dplyr code, return a list of <expression, columns used> pairs.
#'
#' @param quoted dplyr code
#'
#' @return A list of "expr" (character) / "columns" (data.frame)
#'   $expr
#'   [1] "group_by(year, sex)"
#'   $columns
#'   text start_col end_col
#'   1 year        10      13
#'   2  sex        16      18
#'
#' @examples
#' require(babynames)
#' "babynames %>%
#'    group_by(year, sex) %>%
#'    summarise(total = sum(n)) %>%
#'    spread(sex, total) %>%
#'    mutate(percent_male = M / (M + F) * 100, ratio = M / F)" -> pipeline
#' quoted <- rlang::parse_expr(pipeline)
#' columns_in_verbs(quoted)
#' @noRd
columns_in_verbs <- function(quoted) {
  lines <- recurse_dplyr(quoted)
  outputs <- get_dplyr_intermediates(quoted)
  all_columns <- list()
  for (i in seq_len(length(lines))) {
    if (!inherits(lines[[i]], "name")) {
      verb <- lines[[i]][[3]]
      # get the deparsed character version
      deparsed <- rlang::expr_deparse(verb)
      # then feed it to parse which will parse and return an expression that getParseData likes
      # now we have a syntax parse tree with types of token labeled
      parsed_tree <- getParseData(parse(text = deparsed))
      # from the parse tree dataframe, only grab SYMBOL tokens to try and determine if the
      # SYMBOL is a valid column.
      symbols <- parsed_tree[parsed_tree$token == "SYMBOL", c("text", "col1", "col2")]
      valid_symbols <- Filter(
        function(s) {
          # we first try to see if the SYMBOL is a column in original dataframe
          tryCatch({
              out <- NULL
              if (i == 1) {
                # for first line, we just subset the first output line (dataframe)
                out <- outputs[[i]][[s]]
              } else {
                # for subsequent lines, we subset previous output line (dataframe)
                out <- outputs[[i - 1]][[s]]
              }
              !is.null(out)
            },
            error = function(e) FALSE
          )
        },
        symbols$text
      )
      # only retrieve rows for which symbols were valid columns, and rename col1 + col2
      # sometimes there are no valid columns (for e.g. if referring to another dataframe)
      # TODO it's good think what would you show in the case of both column or a dataframe referenced
      # TODO also, how does one even figure out that the SYMBOL is referring to a dataframe? eval it? probably.
      # but for now, set it to NULL by default
      valid_columns <- NULL
      # but on most cases there are valid columns mentioned so do the filtering/renaming
      if (length(valid_symbols) > 0) {
        valid_columns <- symbols %>%
          filter(text == valid_symbols) %>%
          rename(start_col = col1, end_col = col2)
      }
      all_columns <- append(all_columns, list(
          expr = deparsed,
          columns = valid_columns
      ))
    }
  }
  return(all_columns)
}
