#### Mapping of U.S. National Drug Codes (NDC) to Anatomical Therapeutic Chemical (ATC) Level 4 classes
###### codename: ndc_map
  
This script reads a file called _NDC_MASTER_INFO.csv_ with the following columns:  
**"YEAR", "MONTH", "NDC"**  
and outputs a file called _ndc_atc_long_list.csv_ containing the following columns:  
**"YEAR", "MONTH", "NDC", "RXCUI", "ATC4"**  
as well as another file called atc_name.csv with the following columns:  
**"ATC4", "ATC4_NAME"**  

The script maps each NDC, according to the date it was used (year and month), to all its ATC-4 classes (if any is available) by querying the RxNav API at https://rxnav.nlm.nih.gov/. The algorithm uses parallelization and query caching to greatly improve efficiency. At my 8-cores desktop computer, I mapped 2.1 million YEAR-MONTH-NDC rows to 3.33 million YEAR-MONTH-NDC-RXCUI-ATC4 rows in 65 minutes.  

One same NDC can be recycled, i.e., represent different drugs at different points in time. This practice has diminished (if not abolished) in recent years but remains a problem in most situations. Moreover, RxNorm also gets updated over time. If you do not have the year and month that each NDC was truly used in the "real world" (e.g. the date the drug was dispensed), the "least wrong" way to use this script probably will be to assign to all NDCs the year and month you are executing this script. This will attribute to each NDC its most recent ATC-4 class mapping(s).  
  
All contents of this repository are under an Attribution-ShareAlike-NonCommercial 4.0 International license. Please see details at http://creativecommons.org/licenses/by-nc-sa/4.0/.  
  
Please feel free to contact me about this work! Reading and reusing code can be made so much easier after a quick voice talk with the original author.  

**--Fabrício Kury**  
