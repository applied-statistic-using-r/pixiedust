#' @importFrom dplyr bind_rows
#' @importFrom dplyr mutate_
#' @importFrom dplyr select_
#' @importFrom knitr asis_output
#' @importFrom knitr kable
#' @importFrom tidyr spread

print_dust_markdown <- function(x, ..., asis=TRUE)
{
  
  if (!is.null(x$caption)) increment_pixie_count()
  
  #* Determine the number of divisions
  #* It looks more complicated than it is, but the gist of it is
  #* total number of divisions: ceiling(total_rows / longtable_rows)
  #* The insane looking data frame is just to make a reference of what rows 
  #*   go in what division.
  if (!is.numeric(x$longtable) & x$longtable) longtable_rows <- 25L
  else if (!is.numeric(x$longtable) & !x$longtable) longtable_rows <- as.integer(max(x$body$row))
  else longtable_rows <- as.integer(x$longtable)
  
  Divisions <- data.frame(div_num = rep(1:ceiling(max(x$body$row) / longtable_rows),
                                        each = longtable_rows)[1:max(x$body$row)],
                          row_num = 1:max(x$body$row))
  total_div <- max(Divisions$div_num)
  
  #* If the table is not being run interactively (ie, in an rmarkdown script)
  #* detect the type of output.  The spacing between tables is output-specific
  if (!interactive()){
    output_type <- knitr::opts_knit$get('rmarkdown.pandoc.to')
    linebreak <- if (is.null(output_type)) "  "
    else if (output_type == "html") "<br>"
    else if (output_type == "latex") "\\ \\linebreak"
    else "  "
  }
  else linebreak <- "  "
  

  
  #* Format the table divisions
  head <- part_prep_markdown(x$head)
  body <- part_prep_markdown(x$body)
  foot <- if (!is.null(x$foot)) part_prep_markdown(x$foot) else NULL
  interfoot <- if (!is.null(x$interfoot)) part_prep_markdown(x$interfoot) else NULL
  
  names(body) <- names(head) <- head[1, ]
  
  if (!is.null(foot)) names(foot) <- names(head)
  if (!is.null(interfoot)) names(interfoot) <- names(head)
  
  subhead <- head[-1, ]
  subhead <- lapply(subhead, function(v) paste0("**", v, "**")) %>%
    as.data.frame(stringsAsFactors=FALSE)

  numeric_classes <- c("numeric", "double", "int")
  
  #* Determine the alignments.  Alignments in 'knitr::kable' are assigned
  #* by the first letter of the HTML alignment.  If no alignment is 
  #* assigned, a default is chosen based on the variable type.  Numerics
  #* are aligned right, characters are aligned left.
  alignments <- dplyr::filter_(x$head, "row == 1") %>%
    dplyr::select_("row", "col", "halign", "col_class") %>%
    dplyr::mutate_(halign = ~ifelse(halign == "",
                                    ifelse(col_class %in% numeric_classes, 
                                           "r",
                                           "l"),
                                    substr(halign, 1, 1)))

  #* Run a for loop to generate all the code.
  #* Not the most efficient way to do this, probably, but 
  #* it's easy to read and understand.
  tbl_code <- ""
  for (i in 1:total_div){
    tbl <- dplyr::bind_rows(if (nrow(head) > 1) subhead else NULL, 
                            body[Divisions$row_num[Divisions$div_num == i], ], 
                            if (i == total_div) foot else interfoot)
  
    tbl_code <- paste0(tbl_code,
                       paste(c("", "", 
                               knitr::kable(tbl,
                                            format = "markdown",
                                            align = alignments$halign),
                               "\n", linebreak, "\n", linebreak, "\n"), 
                             collapse = "\n"))
    
    if (!is.null(x$caption)) 
      tbl_code <- paste0("Table ", get_pixie_count(), ": ", x$caption, "\n", tbl_code)
  }
  if (asis) knitr::asis_output(tbl_code)
  else tbl_code
  
}

#**** Helper functions

part_prep_markdown <- function(part)
{
  numeric_classes <- c("double", "numeric")
  
  part <- perform_function(part)
  
  #* Perform any rounding
  logic <- part$round == "" & part$col_class %in% numeric_classes
  part$round[logic] <- getOption("digits")
  
  logic <- part$col_class %in% numeric_classes
  if (any(logic))
    part$value[logic] <-
    as.character(roundSafe(part$value[logic], as.numeric(part$round[logic])))
  
  #* Replacement
  logic <- !is.na(part[["replace"]])
  part[["value"]][logic] <- part[["replace"]][logic]
  
  #* Bold text
  logic <- part$bold
  part$value[logic] <- 
    with(part, paste0("**", value[logic], "**"))
  
  #* Italic text
  logic <- part$italic
  part$value[logic] <- 
    with(part, paste0("_", value[logic], "_"))
  
  part$value[part$rowspan == 0] <- ""
  part$value[part$colspan == 0] <- ""
  
  #* Set NA (missing) values to na_string
  logic <- is.na(part$value) & !is.na(part$na_string)
  part$value[logic] <- 
    part$na_string[logic]


  #* Spread to wide format for printing
  dplyr::select_(part, "row", "col", "value") %>%
    tidyr::spread_("col", "value") %>%
    dplyr::select_("-row")
}