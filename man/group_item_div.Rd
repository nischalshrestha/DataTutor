% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/datawhats.R
\name{group_item_div}
\alias{group_item_div}
\title{A helper function that creates a div for a group item for SortableJS}
\usage{
group_item_div(line, ns_id)
}
\arguments{
\item{ns_id}{the character for the Shiny module namespace id}

\item{id}{the character id for the particular group item}
}
\value{
a shiny::div
}
\description{
In particular, the unique identifiers make up each item:
- Item ID: <id> for group item: data, verb1, verb2, ... verbn.
"verbN" is better for uniquely identifying since you can have multiple of same verb
- Item Summary ID: <id>-summary-box, <id>-summary-box-row, <id>-summary-box-col
- Item Box Type ID: <change>-square
- Item Glyph ID: <id>-glyph
- Item Toggle ID: <id>-toggle
- Item CodeMirror ID: <id>-code_mirror
}
