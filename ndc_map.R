# ndc_map.R ----------------------------------------------------------------------------------
#' Mapping U.S. Food and Drug Administration (FDA) National Drug Codes (NDC) to Drug Classes and
#' Terminologies by querying the RxNorm API at https://rxnav.nlm.nih.gov.
#' 
#' By Fabrício Kury: https://github.com/fabkury
#' Coding start: 2019/3/26 14:04
#' Margin column at 100 characters.
##

#' HOW TO RUN THIS SCRIPT:
#' First, make sure the code_master_file variable is pointing to the input file containing NDCs. That
#' file can be either:
#'   - the package.txt from the FDA (https://www.fda.gov/Drugs/InformationOnDrugs/ucm142438.htm),
#'   - a CSV file containing a column called "NDC",
#'   - a flat list of NDCs, one per line.
#' Then, see the do_* variables. Define as TRUE only the codes you want. You can request more than
#' one at the same time, but I don't recommend it, because it will generate duplicate rows. For
#' example, if one NDC has 3 ATC codes and 2 VA codes, you will get 6 rows for that NDC alone (all
#' possible combinations of the NDC-ATC-VA codes).
#' Finally, define exec_label to whatever you want. That variable is just to isolate multiple runs
#' of the code. Then you should be good to go. Just source the script and watch the progress on the
#' console.

#' TODO: Collect mapping errors, report at the end alongside their NDCs.
#' TODO: Create the is_generic column from the tty.
#'   https://www.nlm.nih.gov/research/umls/rxnorm/docs/2012/appendix3.html
#' TODO: Each specialized mapping function, eg. get_atc5(), should receive clear arguments. The
#' work of joining or column-binding their return values with the rest of the NDC information should
#' be performed by get_code_classes().
#' TODO: Make the query caching happen at the level of the web request call, not anywhere higher up.
#' TODO: Report to the final map whether the RxCUI is active or not.


# Packages ------------------------------------------------------------------------------------
library(data.table)
library(tidyverse)
library(xml2)
library(hash)
library(ratelimitr)

# Backbone functions --------------------------------------------------------------------------
timeformat <- function(ts) format(ts, "%Y_%m_%d %H_%M")
curtime <- function() timeformat(Sys.time())
ensureDir <- function(...) {
  dir_path <- paste0(...)
  if(!dir.exists(dir_path))
    dir.create(dir_path, recursive = T)
  dir_path
}
chop_tbl <- function(tbl, n_chops = 0, size = 0) {
  if(!(n_chops > 0 | size > 0))
    stop('Error in chop_tbl(): either n_chops or size must be specified.')
  if(n_chops > 0)
    # Chop by number of pieces.
    return(split(tbl, cut(1:nrow(tbl), n_chops, labels = FALSE)))
  # Chop by size of the chop
  split(tbl, cut(1:nrow(tbl), ceiling(nrow(tbl)/size), labels = FALSE))
}
ifzero <- function(o) {
  if(length(o))
    o
  else
    NA
}
beginProgressReport <- function(job_size, frequency = 0.005, iteration_name = 'iterations') {
  assign('progress_report_iterator', 0, envir = .GlobalEnv)
  assign('progress_report_job_size', job_size, envir = .GlobalEnv)
  assign('progress_report_frequency', frequency, envir = .GlobalEnv)
  assign('progress_report_precision', 1, envir = .GlobalEnv)
  message('Will begin processing ', job_size, ' ', iteration_name, '.')
  message('This can take a long time! Progress report will happen at ',
    100*progress_report_frequency, '% rate.')
}
iterateProgress <- function(housekeep_function = NULL) {
  if(!((progress_report_iterator <<- progress_report_iterator+1)%%max(floor(
    progress_report_job_size*progress_report_frequency), 1))) {
    message(round(100*progress_report_iterator/progress_report_job_size,
      progress_report_precision), '%')
    
    if(!is.null(housekeep_function))
      housekeep_function()
  }
}
console <- function(...) {
  cat(paste0(..., '\n'))
}
wrapRDS <- function(var, exprs, by_name = F, with_exec_label = F, pass_val = F, assign_val = T,
  rds_dir = def_rds_dir, override = global_rds_override, ignore_rds = global_rds_ignore) {
  #' This is a handy function to store variables between runs of the code and skip recreating them.
  #' It checks if an RDS file for var already exists in rds_dir. If it does, read it from there. If
  #' it does not, evaluates exprs and saves it to such RDS file.
  #' var: The object itself, unquoted, or a character vector containing its name.
  #' exprs: Expression to be evaluated if the RDS file doesn't already exist.
  #' by_name: If true, var is interpreted as a character vector with the object name.
  #' with_exec_label: If true, exec_label (a global) is added to the RDS name. Used to isolate
  #'   multiple runs of the code.
  #' pass_val: If true, will return the object at the end.
  #' assign_val: If true, will assign the value of the object to its name in the calling envirmt.
  #' rds_dir: Directory to contain RDS files.
  #' override: If true, will ignore existing RDS files and evaluate exprs.
  if(by_name)
    varname <- var
  else
    varname <- deparse(substitute(var))
  rds_file <- paste0(rds_dir, varname,
    ifelse(with_exec_label, paste0(' (', exec_label, ')'), ''), '.rds')
  if(!ignore_rds && !override && file.exists(rds_file)) {
    console("Reading '", varname, "' from file '", rds_file, "'.")
    var_val <- readRDS(rds_file)
  } else {
    var_val <- eval.parent(substitute(exprs), 1)
    if(!ignore_rds) {
      console("Saving '", varname, "' to file '", rds_file, "'.")
      if(!dir.exists(rds_dir))
        dir.create(rds_dir, recursive = T)
      saveRDS(var_val, rds_file)
    }
  }
  if(assign_val)
    assign(varname, var_val, envir = parent.frame(n = 1))
  if(pass_val | !assign_val)
    var_val
}
keepRDS <- function(var, by_name = F, with_exec_label = F,
  rds_dir = def_rds_dir, verbose = F, ignore_rds = global_rds_ignore) {
  #' Helper function to create new RDS files, or update existing ones, with calling syntax and file
  #' name compatibles with wrapRDS.
  if(by_name) {
    varname <- var
    var <- eval(parse(text=varname))
  } else
    varname <- deparse(substitute(var))
  
  if(!ignore_rds) {
    rds_file <- paste0(rds_dir, varname,
      ifelse(with_exec_label, paste0(' (', exec_label, ')'), ''), '.rds')
    if(verbose)
      console("Saving '", varname, "' to file '", rds_file, "'.")
    tryCatch(saveRDS(var, rds_file),
      error = function(e) {
        message('Error saving ', rds_file, ':', e)
      })
  }
}
scope <- function(expr) { 
  # Evaluates expression within a temporary scope/environment.
  prev_expressions <- getOption('expressions')
  options(expressions = 10000)
  retval <- eval(substitute(expr))
  options(expressions = prev_expressions)
  retval
}
tbl_by_row <- function(data, fun) {
  as_tibble(pmap_dfr(data, function(...) { fun(tibble(...)) } ))
}


# Globals -------------------------------------------------------------------------------------
# Set working directory to the .R script directory.
options(stringsAsFactors = F)
tryCatch(setwd(dirname(sys.frame(1)$ofile)),
  error = function(e) {
    library(rstudioapi)
    setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
  })

# Source data with NDCs:
ndc_master_file <- paste0('../Dados/NDC2017.csv')
# Character used to separate columns in the code_master_file:
ndc_master_file_separator <- ','

# Request codes by making the do_* variables TRUE.
do_atc5 <- FALSE # If true, will request Anatomical-Therapeutic-Chemical (ATC) level 5 from RxNorm.
do_atc4 <- TRUE # If true, will request Anatomical-Therapeutic-Chemical (ATC) level 4 from RxClass.
do_va <- FALSE # If true, will request Veterans' Affairs Drug Classes from RxNorm.
do_attributes <- FALSE # If true, will request the drug's attributes (brand/generic, strength).
do_snomedct <- FALSE # If true, will request SNOMED CT from RxNorm.
do_meshpa <- FALSE # If true, will request MESH Pharmacological Actions from RxNorm.
do_ingredients <- FALSE # If true, will request the drug's ingredients from RxNorm.

# Ingredients are required for the classes below, so let's make sure do_ingredients is on.
do_ingredients <- do_ingredients | do_atc5 | do_snomedct | do_meshpa

# exec_label can be anything. It serves to isolate multiple runs of the script.
exec_label <- 'atc5'

# The documentation (https://rxnav.nlm.nih.gov/TermOfService.html) allows no more than 20/sec. Let
# us do 19/sec to be sure.
RxNorm_query_rate_limit <- 19

error_retry_limit <- 5 # Number of times to retry after error before aborting the whole script.
error_sleep_seconds <- 10 # Number of seconds to sleep between retries after error.

out_base_dir <- ensureDir('Output/')
out_dir <- ensureDir(out_base_dir, exec_label, '/')
def_rds_dir <- ensureDir(out_base_dir, 'rds/')
ndc_field <- 'ndc' # ndc field (column)
ndc_map_random_seed <- 511 # Magic number, intentionally so.


# Debug mode ----------------------------------------------------------------------------------
debug_mode <- F # If true, will use only a small portion of input data.
debug_limit <- 250 # Number of entries to use in debug mode.
if(debug_mode)
  exec_label <- paste0(exec_label, '_d')
global_rds_override <- F
global_rds_ignore <- F


# Application-specific functions --------------------------------------------------------------
get_labeler_product_from_ndc <- function(ndc) {
  #' This function requires the ndc to be formatted with dashes ('-'). Otherwise it will merely
  #' return the original NDC provided as input.
  # As per https://open.fda.gov/data/ndc/: 
  # "The ndc will be in one of the following configurations: 4-4-2, 5-3-2, or 5-4-1."
  # First segment: labeler: firm that manufactures or distributes the drug.
  # Second segment: product: strength, dosage form, and formulation of a drug for a particular firm.
  # Third segment: package: package sizes and types.
  # Therefore we want the labeler and the product, because the package won't alter a product's
  # drug classes.
  ndc <- unlist(ndc, use.names = F) # This is in case ndc is a 1-column tibble.
  has_dash <- grepl('-', ndc, fixed = T)
  last_dash <- gregexpr('-', ndc[has_dash])
  last_dash <- do.call(rbind, last_dash)
  last_dash <- last_dash[,-1] # Pick only the second '-'
  ndc[has_dash] <- substr(ndc[has_dash], 1, last_dash-1)
  ndc
}

get_RxCUI_from_ndcproperties <- function(ndc) {
  rxcui <- NA
  if(!is.na(ndc)) {
    if(has.key(ndc, ndcproperties_hash))
      rxcui <- ndcproperties_hash[[ndc]]
    else {
      query_address <- paste0RxNormQuery('ndcproperties?id=', ndc)
      api_response <- read_xml(query_address)
      rxcui <- as.integer(xml_text(xml_find_all(api_response, '//rxcui')))
      rxcui <- unique(rxcui)
      .set(ndcproperties_hash, keys = ndc, values = rxcui)
    }
  }
  tibble(ndc = rep(ndc, length(ifzero(rxcui))), rxcui = ifzero(rxcui))
}

get_RxCUI_from_ndcstatus <- function(ndc, ndc_path = list()) {
  if(is.na(ndc))
    rxcui <- NA
  else if(has.key(ndc, ndcstatus_hash))
    rxcui <- ndcstatus_hash[[ndc]]
  else {
    # Get all entries in the NDC history.
    ndcStatus <-
      paste0RxNormQuery('ndcstatus?ndc=', ndc) %>%
      read_xml() %>%
      xml_find_all('//ndcStatus')
    
    ndc_comment <- xml_text(xml_find_all(ndcStatus, '//comment'))
    if(grepl('\\d{11}', ndc_comment)) { # Found an NDC11 in the comments. Probably a replacement!
      new_ndc <- str_extract(ndc_comment, '\\d{11}')
      if(new_ndc == ndc || new_ndc %in% ndc_path)
        message('Error: found a loop in the NDC redirects as per /ndcstatus at NDC = ', ndc)
      else
        return(get_RxCUI_from_ndcstatus(new_ndc, c(ndc_path, ndc)))
    }
    
    # Alright, so if we're here we should have to best NDC for this case (no NDC redirects).
    ndcHistory <- ndcStatus %>%
      xml_find_all('//ndcHistory') %>%
      as_list() %>%
      lapply(lapply, function(e) ifelse(!length(e), NA, e)) %>% # Fill the lists elements.
      rbindlist() %>%
      lapply(FUN = unlist) %>%
      bind_rows()
    
    if(length(ndcHistory)) {
      if(any(!is.na(ndcHistory$activeRxcui)))
        # Give preference to active RxCUIs.
        ndcHistory <- ndcHistory[!is.na(ndcHistory$activeRxcui), ]
      
      #' Pick the most recent RxCUI as sorted by the end dates. If it ties, use the start date.
      ndcHistory <- ndcHistory[rev(with(ndcHistory, order(endDate, startDate))), ][1,]
      
      rxcui <- with(ndcHistory, ifelse(is.na(activeRxcui), originalRxcui, activeRxcui))
      rxcui <- as.integer(rxcui)
      # if(length(rxcui)>1)
      # This is never supposed to happen, and honestly I don't remember ever seeing it happen,
      # but since the code does assume that length(rxcui) == 1, for the sake of safety I should
      # implement this check and have it raise a non-halting error.
      #   browser()
    }
    else {
      # No NDC history. Try to use what was specified under ndcStatus directly.
      rxcui <- ndcStatus %>%
        xml_find_all('//rxcui') %>%
        xml_integer()
    }
    .set(ndcstatus_hash, keys = ndc, values = rxcui)
  }
  tibble(ndc = rep(ndc, length(ifzero(rxcui))), rxcui = ifzero(rxcui))
  
  # This is the old code for picking one RxCUI out of the possibly multiple options.
  # Good old times of naïvité! True begginner's luck.
  # ndc_history <- xmlToDataFrame(nodes=ns)
  # ndc_history$startDate <- as.numeric(as.POSIXct(as.Date(
  #   paste0(ndc_history$startDate, '01'), '%Y%m%d')))
  # ndc_history$endDate <- as.numeric(as.POSIXct(as.Date(
  #   paste0(ndc_history$endDate, '01'), '%Y%m%d')))
  # ndc_date <- as.numeric(as.POSIXct(as.Date(
  #   paste0(NDC_info[['YEAR']], NDC_info[['MONTH']], '01'), '%Y%m%d')))
  # if(ndc_date < min(ndc_history$startDate)) {
  #   log.early.ndc(NDC_info[['YEAR']], NDC_info[['MONTH']], NDC_info[['NDC']])
  #   # Pick the earliest RxCUI. If more than one with the same start date, pick the latest end date.
  #   ndc_history <- ndc_history[order(ndc_history$startDate, -ndc_history$endDate),]
  # }
  # else {
  #   if(nrow(subset(ndc_history, (startDate <= ndc_date) & (endDate >= ndc_date))) > 0)
  #     ndc_history <- subset(ndc_history, (startDate <= ndc_date) & (endDate >= ndc_date))
  #   # Pick the latest RxCUI. If more than one with the same start date, pick the latest end date.
  #   ndc_history <- ndc_history[order(-ndc_history$startDate, -ndc_history$endDate),]
  # }
  # rxcui <- as.character(if(nchar(as.character(ndc_history[[1, 'activeRxcui']])) > 3)
  #   ndc_history[[1, 'activeRxcui']] else ndc_history[[1, 'originalRxcui']])
}

get_attributes <- function(drug_product) {
  rxcui <- drug_product[['rxcui']]
  if(is.na(rxcui))
    rxcui_attributes <- tibble(tty = NA, available_strength = NA)
  else if(has.key(as.character(rxcui), attributes_hash))
    rxcui_attributes <- attributes_hash[[as.character(rxcui)]]
  else {
    query_address <- paste0RxNormQuery('rxcui/', rxcui, '/allProperties?prop=ATTRIBUTES')
    api_response <- read_xml(query_address)
    tty <- xml_text(xml_find_all(api_response, '//propConcept[propName=\'TTY\']/propValue'))
    available_strength <- xml_text(xml_find_all(api_response,
      '//propConcept[propName=\'AVAILABLE_STRENGTH\']/propValue'))
    rxcui_attributes <- tibble(tty = ifzero(tty), available_strength = ifzero(available_strength))
    # TODO: Some hashes have tibbles as attributes, while one other has a list. Normalize that.
    .set(attributes_hash, keys = rxcui, values = rxcui_attributes)
  }
  cbind(as.data.frame(as.list(drug_product)), rxcui_attributes)
}

get_va <- function(drug_product) {
  rxcui <- drug_product[['rxcui']]
  if(is.na(rxcui))
    va_drug_class <- tibble(va = NA)
  else if(has.key(as.character(rxcui), va_hash))
    va_drug_class <- va_hash[[as.character(rxcui)]]
  else {
    va <- paste0RxNormQuery('rxclass/class/byRxcui?', 'rxcui=', rxcui, '&relaSource=VA') %>%
      read_xml() %>%
      xml_find_all('//rxclassMinConceptItem[classType=\'VA\']/classId') %>%
      xml_text() %>%
      unique()
    va_drug_class <- tibble(va = ifzero(va))
    .set(va_hash, keys = rxcui, values = va_drug_class)
  }
  cbind(as.data.frame(as.list(drug_product)), va_drug_class)
}

get_ingredients <- function(drug_product) {
  rxcui <- drug_product[['rxcui']]
  ingredients <- list()
  if(!is.na(rxcui)) {
    if(has.key(as.character(rxcui), ingredient_hash))
      ingredients <- ingredient_hash[[as.character(rxcui)]]
    else {
      ingredients <-
        paste0RxNormQuery('rxcui/', rxcui, '/related?tty=IN+MIN') %>%
        read_xml() %>%
        xml_find_all('//conceptProperties')
      if(length(ingredients)) {
        ingredients <- ingredients %>%
          as_list() %>%
          lapply(lapply, function(e) ifelse(!length(e), NA, e)) %>% # Fill the lists elements.
          rbindlist() %>%
          lapply(FUN = unlist) %>%
          bind_rows() %>%
          select(in_rxcui = rxcui,
            in_tty = tty,
            in_name = name,
            in_synonym = synonym,
            in_umlscui = umlscui) %>%
          mutate(has_min = 'MIN' %in% in_tty)
      }
      .set(ingredient_hash, keys = rxcui, values = ingredients)
    }
  }
  ingredients <- tibble(
    in_rxcui = as.integer(ifzero(ingredients$in_rxcui)),
    has_min = as.logical(ifzero(ingredients$has_min)),
    in_tty = as.character(ifzero(ingredients$in_tty)),
    in_name = as.character(ifzero(ingredients$in_name)),
    in_synonym = as.character(ifzero(ingredients$in_synonym)),
    in_umlscui = as.character(ifzero(ingredients$in_umlscui)))
  cbind(as.data.frame(as.list(drug_product)), ingredients)
}

get_atc5_attributes <- function(atc5) {
  get_atc4_attributes <- function(atc4) {
    ddd_u_admr <- tibble(atc5 = NA, ddd = NA, u = NA, adm_r = NA, whocc_note = NA)
    if(is.na(atc4))
      return(ddd_u_admr)
    if(has.key(atc4, atc_attributes_hash))
      return(atc_attributes_hash[[atc4]])
    try({
      whocc_address <- paste0('https://www.whocc.no/atc_ddd_index/?code=', atc4) # No need to cap
        # the number of queries per second like with RxNorm.
      ddd_u_admr <- read_html(whocc_address) %>% html_node('table') %>%
        html_table(header = T, fill = TRUE)
      if(!is.null(ncol(ddd_u_admr)) && ncol(ddd_u_admr) == 6) {
        # Web scraping assumed to have been successful.
        names(ddd_u_admr) <- c('atc5', 'atc5_name', 'ddd', 'u', 'adm_r', 'whocc_note')
        ddd_u_admr$atc5_name <- NULL # Not needed.
        
        # Those '""' below seem to be due to an external bug -- maybe the website, maybe xml2.
        ddd_u_admr$u[ddd_u_admr$u == ""] <- NA 
        ddd_u_admr$adm_r[ddd_u_admr$adm_r == ""] <- NA
        ddd_u_admr$whocc_note[ddd_u_admr$whocc_note == ""] <- NA
        
        .set(atc_attributes_hash, keys = atc4, values = ddd_u_admr)
      }
    })
    ddd_u_admr
  }
  
  ddd_u_admr <- tibble(atc5 = atc5, ddd = NA, u = NA, adm_r = NA, whocc_note = NA)
  if(is.na(atc5))
    return(ddd_u_admr)
  if(has.key(atc5, atc_attributes_hash))
    return(atc_attributes_hash[[atc5]])
  try({
    # Get the DDD, unit of measure, and administration route from WHOCC's website. No need to
    # cap the number of queries per second like in RxNorm.
    if(nchar(atc5) != 7) # ATC-4 has 5 characters, ATC-5 has 7.
      stop('Unable to recognize ATC code ', atc5, '. The function get_atc5_attributes() must ',
        'receive either an ATC-5 or ATC-4 code.') # Just a bit of pointless error checking.
    atc4 <- substr(atc5, 1, 5)
    atc4_ddd_u_admr <- get_atc4_attributes(atc4)
    if(atc5 %in% atc4_ddd_u_admr$atc5)
      ddd_u_admr <- filter(atc4_ddd_u_admr, atc5 == (!! atc5))
  })
  
  ddd_u_admr
}

get_atc5 <- function(drug_product) {
  in_rxcui <- drug_product[['in_rxcui']]
  if(is.na(in_rxcui))
    atc5 <- tibble(atc5 = NA)
  else if(has.key(as.character(in_rxcui), atc5_hash))
    atc5 <- atc5_hash[[as.character(in_rxcui)]]
  else {
    query_address <- paste0RxNormQuery('rxcui/', in_rxcui, '/property?propName=ATC')
    rxnorm_response <- read_xml(query_address)
    # The "//propConcept[propName=\'ATC\']/" below is redundant, by why not, for safety.
    atc5 <- xml_text(xml_find_all(rxnorm_response, '//propConcept[propName=\'ATC\']/propValue'))
    atc5 <- tibble(atc5 = ifzero(atc5))
    if(any(!is.na(atc5$atc5))) {
      # Get the DDD, unit of measure, and administration route from WHOCC's website. No need to cap
      # the number of queries per second like in RxNorm.
      ddd_u_admr <- bind_rows(lapply(atc5$atc5, get_atc5_attributes))
      atc5 <- left_join(atc5, ddd_u_admr, by = 'atc5')
    }
    .set(atc5_hash, keys = in_rxcui, values = atc5)
  }
  cbind(as.data.frame(as.list(drug_product)), atc5)
}

get_atc4 <- function(drug_product) {
  rxcui <- drug_product[['rxcui']]
  atc4 <- tibble(atc4 = NA, atc4_name = NA)
  if(!is.na(rxcui)) {
    if(has.key(as.character(rxcui), atc4_hash))
      atc4 <- atc4_hash[[as.character(rxcui)]]
    else {
      query_address <- paste0RxNormQuery('rxclass/class/byRxcui?rxcui=', rxcui, '&relaSource=ATC')
      rxnorm_response <- read_xml(query_address)
      rxnorm_response <- xml_find_all(rxnorm_response, '//rxclassMinConceptItem')
      if(length(rxnorm_response)) {
        atc4 <- lapply(rxnorm_response, function(i) {
          as.data.frame(t(unlist(as_list(i))[c('classId', 'className')])) })
        atc4 <- as_tibble(bind_rows(atc4))
        names(atc4) <- c('atc4', 'atc4_name')
      }
      .set(atc4_hash, keys = rxcui, values = atc4)
    }
  }
  cbind(as.data.frame(as.list(drug_product)), atc4)
}

get_meshpa <- function(drug_product) {
  in_rxcui <- drug_product[['in_rxcui']]
  if(is.na(in_rxcui))
    meshpa <- tibble(meshpa = NA)
  else if(has.key(as.character(in_rxcui), meshpa_hash))
    meshpa <- meshpa_hash[[as.character(in_rxcui)]]
  else {
    query_address <- paste0RxNormQuery('rxclass/class/byRxcui?',
      'rxcui=', in_rxcui, '&relaSource=MESH')
    rxnorm_response <- read_xml(query_address)
    # The "//propConcept[propName=\'MESHPA\']/" below is redundant, by why not, for safety.
    meshpa <- xml_text(xml_find_all(rxnorm_response,
      '//rxclassMinConceptItem[classType=\'MESHPA\']/classId'))
    meshpa <- tibble(meshpa = ifzero(meshpa))
    .set(meshpa_hash, keys = in_rxcui, values = meshpa)
  }
  cbind(as.data.frame(as.list(drug_product)), meshpa)
}

get_snomedct <- function(drug_product) {
  in_rxcui <- drug_product[['in_rxcui']]
  if(is.na(in_rxcui))
    snomedct <- tibble(snomedct = NA)
  else if(has.key(as.character(in_rxcui), snomedct_hash))
    snomedct <- snomedct_hash[[as.character(in_rxcui)]]
  else {
    query_address <- paste0RxNormQuery('rxcui/', in_rxcui, '/property?propName=SNOMEDCT')
    rxnorm_response <- read_xml(query_address)
    # The "//propConcept[propName=\'SNOMEDCT\']/" below is redundant, by why not, for safety.
    snomedct <- xml_text(xml_find_all(rxnorm_response,
      '//propConcept[propName=\'SNOMEDCT\']/propValue'))
    snomedct <- tibble(snomedct = ifzero(snomedct))
    .set(snomedct_hash, keys = in_rxcui, values = snomedct)
  }
  cbind(as.data.frame(as.list(drug_product)), snomedct)
}

get_code_classes <- function(ndc, attributes = do_attributes, va = do_va,
  ingredients = do_ingredients, atc5 = do_atc5, atc4 = do_atc4, snomedct = do_snomedct,
  meshpa = do_meshpa, ndc_to_rxcui_fun = get_RxCUI_from_ndcstatus) {
  # Get the ndc's RxCUI
  drug_products <- ndc_to_rxcui_fun(ndc)
  
  # Get the RxCUI's attributes: TTY and AVAILABLE_STRENGTH
  if(attributes)
    drug_products <- tbl_by_row(drug_products, get_attributes)
  
  # Get the RxCUI's Veterans' Affairs Drug Class(es) and/or ATC-4 code(s).
  # Notice that, unlike all others, VADC and ATC-4 come from the drug producr, not its ingredients.
  if(va)
    drug_products <- tbl_by_row(drug_products, get_va)
  
  if(atc4)
    drug_products <- tbl_by_row(drug_products, get_atc4)
  
  # Get the the drug's ingredients: RxCUI and name
  if(ingredients | atc5 | snomedct | meshpa)
    drug_products <- tbl_by_row(drug_products, get_ingredients)
  
  # Get the ingredients' SNOMEDCT code(s)
  if(snomedct)
    drug_products <- tbl_by_row(drug_products, get_snomedct)
  
  # Get the ingredients' ATC-5 code(s)
  if(atc5)
    drug_products <- tbl_by_row(drug_products, get_atc5)
  
  # Get the ingredients' MESHPA code(s)
  if(meshpa)
    drug_products <- tbl_by_row(drug_products, get_meshpa)
  
  drug_products
}

tally_mapping_rates <- function(ndc_map, colname) {
  # TODO: Implement this function.
  
  # Rows missing colname
  console(sum(is.na(ndc_map[, colname])), ' (',
    round(100*sum(is.na(ndc_map[, colname]))/nrow(ndc_map), 1),
    '%) rows have no ', colname, ' value.')
  
  # NDCs partially and completely unmapped
  unique_ndc_count <- length(unique(ndc_map[[ndc_field]]))
  unmapped_ndcs <- unique(ndc_map[is.na(ndc_map[[colname]]), ndc_field])
  mapped_ndcs <- unique(ndc_map[!is.na(ndc_map[[colname]]), ndc_field])
  ndc_intersect_count <- length(intersect(unmapped_ndcs, mapped_ndcs))
  mapped_ndc_count <- length(mapped_ndcs[[ndc_field]]) - ndc_intersect_count
  unmapped_ndc_count <- length(unmapped_ndcs[[ndc_field]]) - ndc_intersect_count
  console('The original data contained ', unique_ndc_count, ' NDCs:')
  console(mapped_ndc_count, ' (', round(100*mapped_ndc_count/unique_ndc_count, 1), '%) ',
    'were fully mapped to ', colname, '.')
  console(unmapped_ndc_count, ' (', round(100*unmapped_ndc_count/unique_ndc_count, 1), '%) ',
    'remain fully unmapped to ', colname, '.')
  console(ndc_intersect_count, ' (', round(100*ndc_intersect_count/unique_ndc_count, 1), '%) ',
    'contain >=1 ingredient and >=1 was mapped while >=1 was not.')
}

# Execution start ---------------------------------------------------------------------------
exec_start_time <- Sys.time()
console('Script execution started at ', timeformat(exec_start_time),
  ' with label: ', exec_label, '.')
old_option_expressions <- getOption('expressions')
options(expressions = 5e5)

# Load and preprocess input -----------------------------------------------------------------
# Read the master list of ndcs
console('Will read ', ndc_master_file, ' file.')
wrapRDS(ndc_master, {
  ndc_master_line_1 <- read_lines(ndc_master_file, n_max = 1)
  # Assume the file is the package.txt file from the FDA NDC Directory.
  if(grepl('NDCPACKAGECODE', ndc_master_line_1, fixed = T)) {
    master_source <- read_delim(ndc_master_file, delim = '\t', col_names = TRUE,
      col_types = cols_only(NDCPACKAGECODE = "c"), n_max = ifelse(debug_mode, debug_limit, Inf))
  } else if(grepl('ndc', tolower(ndc_master_line_1), fixed = T)) {
    #' Assume the file is a character-delimited tabular file, with colum headers, containing a
    #' column called "NDC" (or some other name containing "NDC" such as "NDC_CODE").
    master_source <- read_delim(ndc_master_file, delim = ndc_master_file_separator,
      col_names = TRUE, n_max = ifelse(debug_mode, debug_limit, Inf))
  } else
    master_source <- tibble(read_lines(ndc_master_file)) # Assume the file is a flat list of NDCs.
    # If the first line contains "NDC" (case-insensitive), assume it is the header and skip it.
  remove(ndc_master_line_1)
  
  #' Rename to 'ndc', in lowercase, as is the standard chosen for this script.
  names(master_source) <- tolower(names(master_source))
  
  #' Pick the first occurrence of the NDC in the column names, in case there are multiple columns
  #' with 'NDC' in the name.
  master_source_ndc_column <- min(which(grepl('ndc', names(master_source), fixed = T)))
  ndc_master <- master_source[master_source_ndc_column]
  names(ndc_master) <- ndc_field
  ndc_master
})

# By now we should have a tibble with a single column.
if(is_tibble(ndc_master)) {
  console('Read ', nrow(ndc_master), ' rows from ', ndc_master_file, '.')
} else
  stop('Error: unable read input file. Please read the description of acceptable input.')

# Subset for debugging?
if(debug_mode) {
  message('Debugging mode is on. Will subset input file to ', debug_limit, ' rows.')
  set.seed(ndc_map_random_seed)
  input_sample <- sample(1:nrow(ndc_master), debug_limit)
  ndc_master <- ndc_master[input_sample,]
  message('Done.')
}

if(F) {
  selected_entries <- nchar(ndc_master[[ndc_field]]) < 7
  if(any(selected_entries)) {
    console('Found ', sum(selected_entries), ' NDC entries with less than 7 characters. ',
      'Considered as misformed input and removed from the data.')
    ndc_master <- ndc_master[!selected_entries, ]
    if(!nrow(ndc_master))
      stop('Error: no rows left to process.')
  }
  remove(selected_entries)
  
  #' If NDC11 with no hyphens, add hyphens. For the NDCs with 2 hyphens, cut the last part (the
  #' packaging) to create the "labeler-product" code, i.e. the first two segments of NDC.
  ndc_master$code <- vapply(ndc_master[[ndc_field]],
    function(ndc) {
      if(grepl('-', substr(ndc, nchar(ndc)-2, nchar(ndc)-1), fixed = T))
        substr(ndc, 1, max(unlist(gregexpr('-', ndc, fixed = T)))-1)
      else if(nchar(gsub('\\D', '', ndc)) == 11 && !grepl('-', ndc, fixed = T))
        paste0(substr(ndc, 1, 5), '-', substr(ndc, 6, 9))
      else
        ndc
    }, character(1))
}

#' Make code_master the one that will actually be used for mapping. The results get later joined to
#' the ndc_master.
code_master <- unique(ndc_master[[ndc_field]])
console('Found ', length(code_master), ' unique NDCs.')


# Produce the map -----------------------------------------------------------------------------
# Query RxNorm, that is, perform the mapping.
if(T) {
  wrapRDS(ndcproperties_hash, hash())
  wrapRDS(ndcstatus_hash, hash())
  if(do_attributes)
    wrapRDS(attributes_hash, hash())
  if(do_va)
    wrapRDS(va_hash, hash())
  if(do_ingredients)
    wrapRDS(ingredient_hash, hash())
  if(do_atc5) {
    require(rvest)
    wrapRDS(atc5_hash, hash())
    wrapRDS(atc_attributes_hash, hash())
  }
  if(do_atc4)
    wrapRDS(atc4_hash, hash())
  if(do_meshpa)
    wrapRDS(meshpa_hash, hash())
  if(do_snomedct)
    wrapRDS(snomedct_hash, hash())
  
  update_all_rds <- function() {
    keepRDS(ndcproperties_hash)
    keepRDS(ndcstatus_hash)
    if(do_attributes)
      keepRDS(attributes_hash)
    if(do_va)
      keepRDS(va_hash)
    if(do_ingredients)
      keepRDS(ingredient_hash)
    if(do_atc5) {
      keepRDS(atc5_hash)
      keepRDS(atc_attributes_hash)
    }
    if(do_atc4)
      keepRDS(atc4_hash)
    if(do_meshpa)
      keepRDS(meshpa_hash)
    if(do_snomedct)
      keepRDS(snomedct_hash)
  }
  
  #' This function wrapper below is used to cap the number of queries to RxNorm per second. The
  #' functions inside get_code_classes() use this paste0 instead of the standard one to assemble the
  #' query strings (web addresses). In addition, for convenience, it also adds the base address.
  paste0RxNormQuery <- limit_rate(function(...) {
      paste0('https://rxnav.nlm.nih.gov/REST/', ...)
    }, rate(n=RxNorm_query_rate_limit, period = 1))
  
  i <- as.integer(0)
  error_retry_count <- 0
  code_count <- length(code_master)
  code_map <- vector("list", code_count)
  beginProgressReport(code_count)
  while(i < code_count) {
    i <- i + 1
    iterateProgress(update_all_rds)
    code <- code_master[[i]]
    tryCatch({
      code_map[[i]] <- get_code_classes(code)
      error_retry_count <<- 0
      }, error = function(e) {
        error_retry_count <<- error_retry_count + 1
        if(error_retry_count < error_retry_limit) {
          message('Error: ', e)
          message('Will retry code ', code, '.')
          i <<- i - 1
        }
        else if(error_retry_count == error_retry_limit) {
          message('WARNING: Retry limit reached. Will move to the next code.')
          Sys.sleep(error_sleep_seconds)
          error_retry_count <- 0
        }
      }
    )
  }
  code_map <- bind_rows(code_map)
  remove(i)
  remove(paste0RxNormQuery)
  update_all_rds()
}

# Join the map to the original ndc master table
if(T) {
  ndc_map <- left_join(ndc_master, code_map, by = 'ndc')
  remove(ndc_master)
  ndc_map <- ndc_map[order(ndc_map[[ndc_field]]),]
}

# Write the final map to a CSV file.
if(T) {
  map_outfile <- paste0(out_dir, 'ndc_map ', curtime(), ' (', exec_label, ').csv')
  console('Writing NDC map to file ', map_outfile, '.')
  write.csv(ndc_map, map_outfile, row.names = F)
  remove(map_outfile)
  console('Completed.')
}


# Analyze the map -----------------------------------------------------------------------------
if(T) {
  console('The final map has ', nrow(ndc_map), ' rows.')
  invisible(lapply(c('atc5', 'atc4', 'va', 'meshpa', 'snomedct'),
    function(classname) {
      if(classname %in% names(ndc_map)) {
        message('\nTallying ', classname, ':')
        tally_mapping_rates(ndc_map, classname)
      }
    }))
}


# Execution end -------------------------------------------------------------------------------
options(expressions = old_option_expressions)
remove(old_option_expressions)
exec_end_time <- Sys.time()
console('Script execution completed at ', timeformat(exec_end_time), '. ')
print(round(exec_end_time-exec_start_time, 1))

