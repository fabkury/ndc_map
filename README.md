#### Mapping of U.S. Food and Drug Administration (FDA) National Drug Codes (NDC) to Anatomical Therapeutic Chemical (ATC) Level 4 classes
###### codename: ndc_map
  
This script reads a file called _NDC_MASTER_INFO.csv_ with the following columns:  
**"YEAR", "MONTH", "NDC"**  
and outputs a file called _ndc_atc_long_list.csv_ containing the following columns:  
**"YEAR", "MONTH", "NDC", "RXCUI", "ATC4"**  
as well as another file called atc_name.csv with the following columns:  
**"ATC4", "ATC4_NAME"**  

The script maps each NDC, according to the date it was used (year and month), to all its ATC-4 classes (if any is available) by querying the RxNav API at https://rxnav.nlm.nih.gov/. The algorithm uses parallelization and query caching to greatly improve efficiency. At my 8-cores desktop computer, I mapped 2.1 million YEAR-MONTH-NDC rows to 3.33 million YEAR-MONTH-NDC-RXCUI-ATC4 rows in 65 minutes.  
  
All contents of this repository are under an Attribution-ShareAlike-NonCommercial 4.0 International license. Please see details at http://creativecommons.org/licenses/by-nc-sa/4.0/.  
  
Please feel free to contact me about this work! Reading and reusing code can be made so much easier after a quick voice talk with the original author.  
  
*If you do not know the R programming language or are unable to run the code yourself for any reason, and just need a NDC-ATC4 map for your project, we should be able to do this for you (as long as you can e-mail us your list of NDCs). Contact me (see my GitHub profile).*  

**--Fabrício Kury, postdoc at the U.S. National Library of Medicine**  
  
Search tags: thesaurus drug class map equivalence correspondance
  
#### Why do I need the year and month the NDC was used?  
One same NDC can be reused, i.e. represent different drugs at different points in time (https://www.accessdata.fda.gov/scripts/cdrh/cfdocs/cfcfr/CFRSearch.cfm?fr=207.35, paragraph 4.ii). This regulation might be changed in 2017 (with tolerance period until 2019, see https://www.fda.gov/Drugs/GuidanceComplianceRegulatoryInformation/DrugRegistrationandListing/ucm2007058.htm), but old data will remain potentially ambiguous. If you do not have the year and month that each NDC was truly used (e.g. the date the drug was dispensed), the least wrong way to use this script might be to assign to all NDCs the year and month you are executing the script. This will attribute to each NDC its most recent ATC-4 class(es).
