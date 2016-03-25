
setwd('C:/Users/kuryfs/Documents/NLM/Projects/Medicare/NDC map')

debug_mode <- FALSE # Turn on debug mode to do quickly test the script in a small sample of the input file.
i_step <- 1000 # Report progress to the log file every this number of rows processed.
make.n.chunks <- function(x, n) split(x, cut(seq_along(x), n, labels = FALSE))
curtime <- function() format(Sys.time(), "%Y_%m_%d %H_%M")
exec_start_time <- curtime()

if(!dir.exists(paste0('Output/', exec_start_time, '/Logs')))
  dir.create(paste0('Output/', exec_start_time, '/Logs'), recursive = T)

library(doParallel)
no_cores <- detectCores()
cl <- makeCluster(no_cores)
registerDoParallel(cl)

message('## NDC map.R: NDC mapping to ATC-4 classes')
message('## By Fabricio Kury, March, 2016.')
message('## github.com/fabkury/ndc_map -- fabricio.kury@nih.gov')
message('# This script maps National Drug Codes (NDCs) to Anatomical Therapeutic Chemical (ATC) Level 4 classes by ',
  'querying RxNav at https://rxnav.nlm.nih.gov/. Each NDC must be accompanied by the year and month it was used.\n')

message('Script execution started at ', curtime(), '.')
message('Reading file "./Resources/MASTER_NDC_INFO.csv"...')
full_NDCS_info <- read.csv('Resources/MASTER_NDC_INFO.csv')[,c('YEAR', 'MONTH', 'NDC')]
message('File "Resources/MASTER_NDC_INFO.csv" read successfully.')
# Order the chunks by NDC because each core will have its own NDC and RxCUI hash tables. Therefore, if each core
# receives different NDCs, we maximize the use of the hash tables, i.e. minimize the (lengthy) queries to RxNav.
full_NDCS_info <- full_NDCS_info[order(full_NDCS_info[['NDC']]),]

if(debug_mode) {
    full_NDCS_info <- full_NDCS_info[1:1233,] # Run only the first 1233 NDCs. A non-rounded number is good for testing.
    full_NDCS_info[3, 'NDC'] <- 1 # Make one NDC be an error.
}

# Create one chunk of rows for each core. Because the chunks are based on rows, not actually on NDCs, some NDCs might
# happen to be present in more than one core, but that will be minimal.
NDCS_info_chunks <- make.n.chunks(1:nrow(full_NDCS_info), no_cores)
no_chunks <- length(NDCS_info_chunks)

message('Mapping will be executed in parallel across ', no_cores, ' cores.')
message('Attention: progress messages will not be visible in this R console. Please watch to the log files instead.')
foreach(c=1:no_chunks, .packages=c('XML', 'RCurl', 'stringr', 'RJSONIO', 'hash')) %dopar% {
  exec_label <- paste0(exec_start_time, ' (', c, ' of ', no_chunks, ')')
  logfile <- paste0('Output/', exec_start_time, '/Logs/', exec_label, ' Log.txt')
  no_rxcui_logfile <- paste0('Output/', exec_start_time, '/Logs/', exec_label, ' No RxCUI Log.csv')
  no_atc_logfile <- paste0('Output/', exec_start_time, '/Logs/', exec_label, ' No ATC Log.csv')
  other_error_logfile <- paste0('Output/', exec_start_time, '/Logs/', exec_label, ' Other Errors Log.csv')
  early_ndc_logfile <- paste0('Output/', exec_start_time, '/Logs/', exec_label, ' Early NDC Log.csv')
  ndc_atc_file <- paste0('Output/', exec_start_time, '/', exec_label, ' long_list_ndc_atc.csv')
  atc_name_file <- paste0('Output/', exec_start_time, '/', exec_label, ' atc_name.csv')
  
  message.and.log <- function(...) {
    cat(paste0('Log @ ', curtime(), ': ', ...), file=logfile, sep="\n", append=TRUE)
    message(...)
  }
  
  log.no.rxcui.error <- function(YEAR, MONTH, NDC)
    cat(paste0('"', NDC, '",', YEAR, ',', MONTH), file=no_rxcui_logfile, sep="\n", append=TRUE)
  log.no.rxcui.error('"YEAR"', '"MONTH"', 'NDC') # Add the column names to the CSV file.
  
  log.no.atc.error <- function(YEAR, MONTH, NDC, RXCUI)
    cat(paste0(RXCUI, ',"', NDC, '",', YEAR, ',', MONTH), file=no_atc_logfile, sep="\n", append=TRUE)
  log.no.atc.error('"YEAR"', '"MONTH"', 'NDC', '"RXCUI"') # Add the column names to the CSV file.
  
  log.other.error <- function(YEAR, MONTH, NDC)
    cat(paste0('"', NDC, '",', YEAR, ',', MONTH), file=other_error_logfile, sep="\n", append=TRUE)
  log.other.error('"YEAR"', '"MONTH"', 'NDC') # Add the column names to the CSV file.
  
  log.early.ndc <- function(YEAR, MONTH, NDC)
    cat(paste0('"', NDC, '",', YEAR, ',', MONTH), file=early_ndc_logfile, sep="\n", append=TRUE)
  log.early.ndc('"YEAR"', '"MONTH"', 'NDC') # Add the column names to the CSV file.
  
  add.To.NDC.ATC.CSV <- function(YEAR, MONTH, NDC, RXCUI, ATC)
    cat(paste0(YEAR, ',', MONTH, ',"', NDC, '",', RXCUI, ',"', ATC, '"'), file=ndc_atc_file, sep="\n", append=TRUE)
  add.To.NDC.ATC.CSV('"YEAR"', '"MONTH"', 'NDC', '"RXCUI"', 'ATC') # Add the column names to the CSV file.
  
  add.To.ATC.ATCName.CSV <- function(ATC, ATCName)
    cat(paste0('"', ATC, '","', ATCName, '"'), file=atc_name_file, sep="\n", append=TRUE)
  add.To.ATC.ATCName.CSV('ATC4', 'ATC4_NAME') # Add the column names to the CSV file.
  
  getATCClassByNDCInfo <- function(NDC_info, attempts=0) {
    getIt <- function(NDC_info) {
      if(!has.key(NDC_info[['NDC']], ndc.hash))
        .set(ndc.hash, keys = NDC_info[['NDC']], values = getNodeSet(xmlRoot(xmlParse(RCurl::getURL(paste0(
          'https://rxnav.nlm.nih.gov/REST/ndcstatus?ndc=', NDC_info[['NDC']])), useInternalNode=TRUE)),
          "/rxnormdata/ndcStatus/ndcHistory"))
      ns <- ndc.hash[[NDC_info[['NDC']]]]
      if(!length(ns)) {
        log.no.rxcui.error(NDC_info[['YEAR']], NDC_info[['MONTH']], NDC_info[['NDC']])
        return(NA)
      }
      
      ndc_history <- xmlToDataFrame(nodes=ns)
      ndc_history$startDate <- as.numeric(as.POSIXct(as.Date(paste0(ndc_history$startDate, '01'), '%Y%m%d')))
      ndc_history$endDate <- as.numeric(as.POSIXct(as.Date(paste0(ndc_history$endDate, '01'), '%Y%m%d')))
      ndc_date <- as.numeric(as.POSIXct(as.Date(paste0(NDC_info[['YEAR']], NDC_info[['MONTH']], '01'), '%Y%m%d')))
      if(ndc_date < min(ndc_history$startDate)) {
        log.early.ndc(NDC_info[['YEAR']], NDC_info[['MONTH']], NDC_info[['NDC']])
        # Pick the earliest RxCUI. If more than one with the same start date, pick the latest end date.
        ndc_history <- ndc_history[order(ndc_history$startDate, -ndc_history$endDate),]
      }
      else {
        if(nrow(subset(ndc_history, (startDate <= ndc_date) & (endDate >= ndc_date))) > 0)
          ndc_history <- subset(ndc_history, (startDate <= ndc_date) & (endDate >= ndc_date))
        # Pick the latest RxCUI. If more than one with the same start date, pick the latest end date.
        ndc_history <- ndc_history[order(-ndc_history$startDate, -ndc_history$endDate),]
      }
      
      rxcui <- as.character(if(nchar(as.character(ndc_history[[1, 'activeRxcui']])) > 3)
          ndc_history[[1, 'activeRxcui']] else ndc_history[[1, 'originalRxcui']])

      if(!has.key(rxcui, rxcui.hash))
        .set(rxcui.hash, keys = rxcui, values = getNodeSet(xmlRoot(xmlParse(RCurl::getURL(paste0(
          'https://rxnav.nlm.nih.gov/REST/rxclass/class/byRxcui?rxcui=', rxcui, '&relaSource=ATC')),
          useInternalNode=TRUE)), "/rxclassdata/rxclassDrugInfoList/rxclassDrugInfo/rxclassMinConceptItem/classId"))

      ns <- rxcui.hash[[rxcui]]
      if(!length(ns)) {
        log.no.atc.error(NDC_info[['YEAR']], NDC_info[['MONTH']], NDC_info[['NDC']], rxcui)
        return(NA)
      }

      retval <- as.character(xmlToDataFrame(nodes=ns)$text)
      # Print results to file in a long list.
      for(ATC in retval)
        add.To.NDC.ATC.CSV(NDC_info[['YEAR']], NDC_info[['MONTH']], NDC_info[['NDC']], rxcui, ATC)
      retval
    }
    
    res <- try(getIt(NDC_info))
    if(inherits(res, 'try-error')) {
      message.and.log('Error trying to process NDC ', NDC_info[['NDC']], '.')
      if(attempts < 3) {
        Sys.sleep(2) # Maybe the query failed due to network issues. Wait 2 seconds and try again.
        return(getATCClassByNDCInfo(NDC_info, attempts + 1))
      }
      else {
        log.other.error(NDC_info[['YEAR']], NDC_info[['MONTH']], NDC_info[['NDC']])
        return(NA)
      }
    }
    else
      return(res)
  }
  
  getATC4ClassName <- function(ATC4)
    RJSONIO::fromJSON(RCurl::getURL(paste0('https://rxnav.nlm.nih.gov/REST/rxclass/class/byId.json?classId=', ATC4)),
      useInternalNode=TRUE)$rxclassMinConceptList$rxclassMinConcept[[1]][['className']]
  
  ## Execution starts here
  #
  
  message.and.log('Cluster node execution started at ', curtime(), '.')
  NDCS_info <- full_NDCS_info[NDCS_info_chunks[[c]],]
  message.and.log('full_NDCS_info subsetted to chunk ', c, ' of ', no_chunks, '.')
  
  NDCS_info[,'NDC'] <- str_pad(NDCS_info[,'NDC'], 11, side = 'left', pad = '0')
  NDCS_info[,'MONTH'] <- str_pad(NDCS_info[,'MONTH'], 2, side = 'left', pad = '0')
  
  rxcui.hash <- hash()
  ndc.hash <- hash()
  
  # The i variables are just for tracking progress while the script runs.
  i_max <- nrow(NDCS_info)
  
  # Use a for loop instead of apply because we don't care about the results (the function prints them to a file by
  # itself) and we want to avoid running out of memory when executing big lists.
  for(r in 1:nrow(NDCS_info)) {
    getATCClassByNDCInfo(NDCS_info[r,])
    if(!(r%%i_step))
      message.and.log('## Progress: ', r, '/', i_max, ' (', round(r*100/i_max, 2), '%).')
  }
  
  ATCS <- unique(read.csv(ndc_atc_file)[,'ATC'])
  for(ATC in ATCS)
    add.To.ATC.ATCName.CSV(ATC, getATC4ClassName(ATC))
  
  message.and.log('Cluster node execution completed at ', curtime(), '.')
  return(NA)
}
stopCluster(cl)

message('Mapping of ', nrow(full_NDCS_info),' YEAR-MONTH-NDC combinations complete.')
message('Will now merge the ', no_chunks, ' chunks together.')

file_out <- paste0('Output/', exec_start_time, ' long_list_ndc_atc.csv')
con_out <- file(file_out, 'w+')
writeLines('"YEAR","MONTH","NDC","RXCUI","ATC"', con_out) # Add header with colum names.
for(c in 1:no_chunks) {
  con_in <- file(paste0('Output/', exec_start_time, '/', exec_start_time, ' (', c, ' of ', no_chunks,
    ') long_list_ndc_atc.csv'), 'r', blocking = FALSE)
  readLines(con_in, n=1) # Skip first line, which contains the header.
  while(length(lines <- readLines(con_in, n=5000)))
    writeLines(lines, con_out)
  close(con_in)
}
close(con_out)
message('File "', file_out, '" written successfully.')

for(c in 1:no_chunks) {
  file_in <- paste0('Output/', exec_start_time, '/', exec_start_time, ' (', c, ' of ', no_chunks, ') atc_name.csv')
  out_data <- if(exists('out_data'))
      unique(rbind(out_data, read.csv(file_in)))
    else
      read.csv(file_in)
}
file_out <- paste0('Output/', exec_start_time, ' atc_name.csv')
write.csv(out_data, file_out, row.names = F)
message('File "', file_out, '" written successfully.')

message('Script execution completed at ', curtime(), '.')

# Below is legacy code if you want to load the long list NDC-ATC (not YEAR-MONTH-NDC) in memory instead of having it
# printed to a file. I stopped using it before progressing the code to YEAR-MONTH-NDC instead of NDC-ATC. The code below
# requires doing ATCS <- sapply(NDCS, 1, getATCClassByNDCInfo) and it made the program run out of memory in my computer
# with 16 GB of RAM.
# library(reshape)
# unroll_ndc_atc <- function(x) data.frame(NDC=x[[1]], ATC=x[[2]])
# long_list_ndc_atc <- unique(merge_all(apply(matrix(c(NDCS_info[,'NDC'], ATCS), ncol=2), 1, unroll_ndc_atc)))
