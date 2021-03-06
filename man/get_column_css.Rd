% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/callout_df.R
\name{get_column_css}
\alias{get_column_css}
\title{Helper function that reutnrs the column, css pairs for callout words given data}
\usage{
get_column_css(data, callout_words)
}
\arguments{
\item{data}{data.frame or tibble}

\item{callout_words}{A list of lists of callout word and change type
e.g., list(list(word = "carat", change = "internal-change"), list(word = "cut", change = "visible-change"))}
}
\value{
a list structure to supply for reactable(columns = ...)
}
\description{
Helper function that reutnrs the column, css pairs for callout words given data
}
\examples{
get_column_css(mtcars \%>\% group_by(cyl), list(word = "cyl", change = "internal-change"))
}
