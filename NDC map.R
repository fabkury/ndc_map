## You must update these two lines below to run the script yourself.
setwd('C:/Users/kuryfs/Documents/NLM/Projects/Medicare/NDC map') # Should point to the directory of the R script.
ndc_info_file <- './Data/NDC_MASTER_INFO - Geetanjoli.csv' # Must point to the CSV file with YEAR-MONTH-NDC.

# This script requires the following libraries: stringr, doParallel, XML, RCurl, RJSONIO, hash

library(stringr)
library(doParallel)
options(scipen=999) # Disable scientific notation
debug_mode <- F # Turn on debug mode to do quickly test the script in a small sample of the input file.
skip_queries <- F # If true, will not query the only RxNorm API, only try to assemble the files from the partial files.
print_stats <- T # If true, will print some basic statistics of the map at the end.
threads_per_core <- 2 # Set to 1 if you are running out of RAM when running this script.
make.n.chunks <- function(x, n) split(x, cut(seq_along(x), n, labels = FALSE))
curtime <- function() format(Sys.time(), "%Y_%m_%d %H_%M")
exec_start_time <- curtime()
output_dir <- paste0('Output/', exec_start_time)

p_length <- detectCores()*threads_per_core

if(!dir.exists(paste0(output_dir, '/Logs')))
  dir.create(paste0(output_dir, '/Logs'), recursive = T)

if(!dir.exists(paste0(output_dir, '/Partial')))
  dir.create(paste0(output_dir, '/Partial'), recursive = T)

message('## NDC map.R: NDC mapping to ATC-4 classes')
message('## By Fabricio Kury, March, 2016.')
message('## github.com/fabkury/ndc_map -- fabricio.kury@nih.gov')
message('# This script maps National Drug Codes (NDCs) to Anatomical Therapeutic Chemical (ATC) Level 4 classes by ',
  'querying RxNav at https://rxnav.nlm.nih.gov/.\nEach NDC must be accompanied by the year and month it was used.\n')

message('Script execution started at ', curtime(), '.')
message('Reading file "', ndc_info_file , '"...')
full_NDCS_info <- read.csv(ndc_info_file)
message('File "', ndc_info_file, '" read successfully.')
if(!('NDC' %in% colnames(full_NDCS_info)))
  stop('Unable to find NDC column in input file.')
if(!('MONTH' %in% colnames(full_NDCS_info))) { 
  message('Unable to find MONTH column in input file. Will assign December/2012 as execution date.')
  full_NDCS_info$YEAR <- 2012
  full_NDCS_info$MONTH <- 12
}
original_master_ndc <- full_NDCS_info
full_NDCS_info <- full_NDCS_info[,c('YEAR', 'MONTH', 'NDC')]
# Order the chunks by NDC because each core will have its own NDC and RxCUI hash tables. Therefore, if each core
# receives different NDCs, we maximize the use of the hash tables, i.e. minimize the (lengthy) queries to RxNav.
full_NDCS_info <- full_NDCS_info[order(full_NDCS_info[['NDC']]),]

if(debug_mode) {
    full_NDCS_info <- full_NDCS_info[1:1233,] # Run only the first 1233 NDCs. A non-rounded number is good for testing.
    full_NDCS_info[3, 'NDC'] <- 1 # Make one NDC be an error.
}

if(!skip_queries) {
  # Create one chunk of rows for each core. Because the chunks are based on rows, not actually on NDCs, some NDCs might
  # happen to be present in more than one core, but that will be minimal.
  NDCS_info_chunks <- make.n.chunks(1:nrow(full_NDCS_info), p_length)
  # Report progress to the log file every 5% of rows processed per chunk.
  i_step <- as.integer(nrow(full_NDCS_info)/(p_length/0.05))
  message('Mapping will be executed in parallel across ', p_length, ' cores.')
  message('Attention: progress messages will not be visible in this R console. Please watch the log files instead.')
  cl <- makeCluster(p_length)
  registerDoParallel(cl)
  
  foreach(c=1:p_length, .packages=c('XML', 'RCurl', 'stringr', 'RJSONIO', 'hash')) %dopar% {
    exec_label <- paste0(exec_start_time, ' (', c, ' of ', p_length, ')')
    logfile <- paste0(output_dir, '/Logs/', exec_label, ' Log.txt')
    no_rxcui_logfile <- paste0(output_dir, '/Logs/', exec_label, ' No RxCUI Log.csv')
    no_atc4_logfile <- paste0(output_dir, '/Logs/', exec_label, ' No ATC4 Log.csv')
    other_error_logfile <- paste0(output_dir, '/Logs/', exec_label, ' Other Errors Log.csv')
    early_ndc_logfile <- paste0(output_dir, '/Logs/', exec_label, ' Early NDC Log.csv')
    ndc_atc4_file <- paste0(output_dir, '/Partial/', exec_label, ' year_month_ndc_atc4.csv')
    atc4_name_file <- paste0(output_dir, '/Partial/', exec_label, ' atc4_name.csv')
    
    message.and.log <- function(...) {
      cat(paste0('Log @ ', curtime(), ': ', ...), file=logfile, sep="\n", append=TRUE)
      message(...)
    }
    
    log.no.rxcui.error <- function(YEAR, MONTH, NDC)
      cat(paste0('"', NDC, '",', YEAR, ',', MONTH), file=no_rxcui_logfile, sep="\n", append=TRUE)
    log.no.rxcui.error('"YEAR"', '"MONTH"', 'NDC') # Add the column names to the CSV file.
    
    log.no.atc4.error <- function(YEAR, MONTH, NDC, RXCUI)
      cat(paste0(RXCUI, ',"', NDC, '",', YEAR, ',', MONTH), file=no_atc4_logfile, sep="\n", append=TRUE)
    log.no.atc4.error('"YEAR"', '"MONTH"', 'NDC', '"RXCUI"') # Add the column names to the CSV file.
    
    log.other.error <- function(YEAR, MONTH, NDC)
      cat(paste0('"', NDC, '",', YEAR, ',', MONTH), file=other_error_logfile, sep="\n", append=TRUE)
    log.other.error('"YEAR"', '"MONTH"', 'NDC') # Add the column names to the CSV file.
    
    log.early.ndc <- function(YEAR, MONTH, NDC)
      cat(paste0('"', NDC, '",', YEAR, ',', MONTH), file=early_ndc_logfile, sep="\n", append=TRUE)
    log.early.ndc('"YEAR"', '"MONTH"', 'NDC') # Add the column names to the CSV file.
    
    add.To.NDC.ATC4.CSV <- function(YEAR, MONTH, NDC, RXCUI, ATC4)
      cat(paste0(YEAR, ',', MONTH, ',"', NDC, '",', RXCUI, ',"', ATC4, '"'), file=ndc_atc4_file, sep="\n", append=TRUE)
    add.To.NDC.ATC4.CSV('"YEAR"', '"MONTH"', 'NDC', '"RXCUI"', 'ATC4') # Add the column names to the CSV file.
    
    add.To.ATC4.ATC4Name.CSV <- function(ATC4, ATC4Name)
      cat(paste0('"', ATC4, '","', ATC4Name, '"'), file=atc4_name_file, sep="\n", append=TRUE)
    add.To.ATC4.ATC4Name.CSV('ATC4', 'ATC4_NAME') # Add the column names to the CSV file.
    
    getATC4ClassByNDCInfo <- function(NDC_info, attempts=0) {
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
          log.no.atc4.error(NDC_info[['YEAR']], NDC_info[['MONTH']], NDC_info[['NDC']], rxcui)
          return(NA)
        }
        retval <- as.character(xmlToDataFrame(nodes=ns)$text)
        # Print results to file in a long list.
        for(ATC4 in retval)
          add.To.NDC.ATC4.CSV(NDC_info[['YEAR']], NDC_info[['MONTH']], NDC_info[['NDC']], rxcui, ATC4)
        retval
      }
      
      res <- try(getIt(NDC_info))
      if(inherits(res, 'try-error')) {
        message.and.log('Error trying to process NDC ', NDC_info[['NDC']], '.')
        if(attempts < 3) {
          Sys.sleep(2) # Maybe the query failed due to network issues. Wait 2 seconds and try again.
          return(getATC4ClassByNDCInfo(NDC_info, attempts + 1))
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
    
    options(scipen=999) # Disable scientific notation to avoid NDCs being converted to scientific notation.
    message.and.log('Cluster node execution started at ', curtime(), '.')
    NDCS_info <- full_NDCS_info[NDCS_info_chunks[[c]],]
    message.and.log('full_NDCS_info subsetted to chunk ', c, ' of ', p_length, '.')
    
    NDCS_info[,'NDC'] <- str_pad(NDCS_info[,'NDC'], 11, side = 'left', pad = '0')
    NDCS_info[,'MONTH'] <- str_pad(NDCS_info[,'MONTH'], 2, side = 'left', pad = '0')
    
    rxcui.hash <- hash()
    ndc.hash <- hash()
    
    # The i variables are just for tracking progress while the script runs.
    i_max <- nrow(NDCS_info)
    
    # Use a for loop instead of apply because we don't care about the results (the function prints them to a file by
    # itself) and we want to avoid running out of memory when executing big lists.
    for(r in 1:nrow(NDCS_info)) {
      getATC4ClassByNDCInfo(NDCS_info[r,])
      #if(!(r%%i_step))
      #  message.and.log('## Progress: ', r, '/', i_max, ' (', round(r*100/i_max, 2), '%).')
    }
    
    ATC4S <- unique(read.csv(ndc_atc4_file)[,'ATC4'])
    for(ATC4 in ATC4S)
      add.To.ATC4.ATC4Name.CSV(ATC4, getATC4ClassName(ATC4))
    message.and.log('Cluster node execution completed at ', curtime(), '.')
    return(NA)
  }
  
  stopCluster(cl)
  
  message('Mapping of ', nrow(full_NDCS_info),' rows complete.')
}

message('Will now merge the ', p_length, ' chunks together.')

merge.files <- function(d, stem, n, unique_table = F, log_file = F) {
  file_out <- paste0(d, '/', exec_start_time, ' ', stem, '.csv')
  filein_list <- paste0(d, '/',
      ifelse(log_file, 'Logs/', 'Partial/'),
      exec_start_time, ' (', 1:n, ' of ', n, ') ', stem, '.csv')
  message('Writing file "', file_out, '"...')
  con_out <- file(file_out, 'w+')
  
  if(unique_table)
    write.csv(unique(do.call(rbind, lapply(filein_list, read.csv))), con_out, row.names = F)
  else {
    writeLines(readLines(filein_list[1], 1), con_out)
    for(c in 1:n) {
      con_in <- file(paste0(output_dir, '/', 
        ifelse(log_file, 'Logs/', 'Partial/'),
        exec_start_time, ' (', c, ' of ', n, ') ', stem, '.csv'), 'r', blocking = FALSE)
      readLines(con_in, n=1) # Skip first line, which contains the header.
      while(length(lines <- readLines(con_in, n=50000)))
        writeLines(lines, con_out)
      close(con_in)
    }
  }
  
  close(con_out)
  message('File "', file_out, '" written successfully.')
}

merge.files(output_dir, 'year_month_ndc_atc4', p_length)
merge.files(output_dir, 'atc4_name', p_length, unique_table = T)
merge.files(output_dir, 'No ATC4 Log', p_length, unique_table = T, log_file = T)
merge.files(output_dir, 'No RxCUI Log', p_length, unique_table = T, log_file = T)
merge.files(output_dir, 'Early NDC Log', p_length, unique_table = T, log_file = T)

message('File writing completed. Will now perform large join with full original data.')
early_ndc <- read.csv(paste0(output_dir, '/', exec_start_time, ' Early NDC Log.csv'))
early_ndc$EARLY_NDC <- 'Y'
big_join <- merge(original_master_ndc, early_ndc, by = c('YEAR', 'MONTH', 'NDC'), all.x = T, all.y = T)
big_join$EARLY_NDC <- !is.na(big_join$EARLY_NDC)

big_join <- merge(big_join,
  read.csv(paste0(output_dir, '/', exec_start_time, ' No ATC4 Log.csv')),
  by = c('YEAR', 'MONTH', 'NDC'), all.x = T, all.y = T)

big_join <- merge(big_join,
  read.csv(paste0(output_dir, '/', exec_start_time, ' year_month_ndc_atc4.csv')),
  by = c('YEAR', 'MONTH', 'NDC'), all.x = T, all.y = T)

big_join$EARLY_NDC[is.na(big_join$EARLY_NDC)] <- F
big_join$RXCUI.y[is.na(big_join$RXCUI.y)] <- big_join$RXCUI.x[is.na(big_join$RXCUI.y)]
big_join$RXCUI <- big_join$RXCUI.y
big_join$RXCUI.y <- NULL
big_join$RXCUI.x <- NULL
big_join$NDC <- str_pad(big_join$NDC, 11, pad = '0') # 11-digit National Drug Codes (NDCs)

message('Join completed. Will now write large file.')
write.csv(big_join, paste0(output_dir, '/', exec_start_time, ' ndc_rxcui_atc4.csv'),
  row.names = F)

message('Script execution completed at ', curtime(), '.')

if(print_stats) {
  print_no <- function(label, no, pr = 2)
    message(label, no, ' (', round(100*no/unique_ndcs, pr), '%)')
  
  unique_ndcs <- length(unique(big_join$NDC))
  print_no('Total NDCs: ', length(unique(big_join$NDC)))
  print_no('Early NDCs: ', length(unique(big_join$NDC[big_join$EARLY_NDC])))
  print_no('Early NDCs with ATC4: ', length(unique(big_join$NDC[big_join$EARLY_NDC[!is.na(big_join$ATC4)]])))
  print_no('No ATC-4: ', length(unique(big_join$NDC[is.na(big_join$ATC4)])))
  print_no('With ATC-4: ', length(unique(big_join$NDC[!is.na(big_join$ATC4)])))
  print_no('NA NDCs: ', sum(is.na(big_join$NDC)))
  print_no('NA RxCUIs: ', length(unique(big_join$NDC[is.na(big_join$RXCUI)])))
  print_no('With RxCUIs: ', length(unique(big_join$NDC[!is.na(big_join$RXCUI)])))
  message('Unique YEAR-MONTH-NDCs: ', nrow(unique(big_join[, c('YEAR', 'MONTH', 'NDC')])))
  print(summary(big_join))
}
