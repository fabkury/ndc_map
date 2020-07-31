### Mapping U.S. Food and Drug Administration (FDA) National Drug Codes (NDC) to Drug Classes and Codes  
###### codename: ndc_map
*_Mapping NDCs to Anatomical Therapeutic Chemical (ATC) Level 5, Veterans' Affairs Drug Classes, MESH Pharmacological Actions, SNOMED Clinical Terms, and other Drug Classification Systems and Terminologies_*
  
This script provides the drug class or classes from a given drug classification system (e.g. ATC) of each FDA National Drug Code (NDC), if any is available from querying the online RxNorm API at https://rxnav.nlm.nih.gov/. The program can read the input NDCs from a flat list (e.g. TXT file, one NDC per line) or from one column in a CSV file.  
  
If ATC level 5 is requested, the script will additionally scrape each code's Administration Route, Defined Daily Dose (DDD), and Note (if any) from the official ATC index at https://whocc.no/atc_ddd_index/.  
  
It is also possible to request:  
- the generic active ingredients of the NDC, which are independent of drug classification systems,  
- whether the NDC is a brand name or a generic,  
- the strength of the drug product (as an unstructured text string),  
- the SNOMED CT (Clinical Terms) code corresponding to the NDC,  
- the MESH Pharmacological Actions code corresponding to the NDC,  
- the Veterans' Affairs Drug Class code corresponding to the NDC.
  
This work is an update from what was presented as a poster at the 2017 Annual Symposium of the American Medical Informatics Association (AMIA). Still, if you are going to use this script or its NDC <-> drug class maps, please take time to understand the numbers contained in the poster (PDFs are in this repository), because they CAN affect data analyses.  
  
I have also published a deeper analysis and comparison of drug classification systems in a paper (https://mor.nlm.nih.gov/pubs/pdf/2016-dmmi-fk.pdf). **_TL;DR_**: unless your use case is particularly specific, ATC is the best drug classification for most cases of large dataset analyses. The Veterans' Affairs Drug Classes attain the same high level of coverage of NDCs as ATC, but they don't provide the accessible hierarchy that ATC does.  
  
#### How to run the script
This script should work out of the box if you follow the instructions in the .R  file under the heading "How to execute this script."   
  
#### Contributing to this script
There are still some extra features to implement. See the TODOs in the .R file.  
  
#### About performance
The RxNav API Terms of Service requires users to make no more than 20 requests per second per IP address (https://rxnav.nlm.nih.gov/TermOfService.html). This script will cache its internet calls, so it works faster towards the end as more NDCs map to RxCUIs that have already appeared before. From my experience on a laptop over reliable wi-fi, one should expect 12 to 18 hours of execution time per 100,000 unique NDCs, which means about 1.5 to 2.3 NDCs per second. If execution is interrupted (intentionally or not), next time you run the script it will start from zero again, but the queries will still be cached (stored in RDS files), so it will progress blazingly fast until it reaches entries requiring novel online queries at the exact point it had been interrupted.  
  
This script allows you to query for ATC codes, and other coding systems such as VA Drug Classes, in the same run. However, because of the caching, and the limit of queries per second, I do not advise requesting more than one coding system at each time because it is unlikely to be faster than doing separate full runs. In fact, it could even be slower, because rows will get duplicated whenever one NDC maps to multiple codes, and the duplications due to one coding system will multiply the duplications from other coding systems. For example, if one NDC maps to 3 ATC codes and 2 VA Drug Class codes, there will be 2 * 3 = 6 rows in the results, corresponding to each combination of ATC and VA.  
  
#### License
All contents of this repository are under an Attribution-ShareAlike-NonCommercial 4.0 International license. Please see details at http://creativecommons.org/licenses/by-nc-sa/4.0/. Please feel free to contact me about this work! Reading and reusing code can be made so much easier after a quick talk with the original author.  
  
#### Pre-made NDC-to-drug class maps
If you do not know the R programming language or are unable to run the code yourself for any reason, and just need a NDC-to-drug class map for your project, see the folder "FDA NDC Database File with ATC4". The CSV files in there contain all NDCs from the FDA database (https://www.fda.gov/drugs/drug-approvals-and-databases/national-drug-code-directory) with their classes as indicated by the folder and file names. If that doesn't work, and you can send me your list of NDCs, I can run the script for you. Contact me at 627@kury.dev. **_--Fabrício Kury_**  
  
Search tags: thesaurus drug class map equivalence correspondance classification
  
#### Do I need the year and month the NDC was used?  
You do not. The script does not consider dates, only NDCs. Although one same NDC can have been recycled, i.e. represented different drugs at different points in time (https://www.accessdata.fda.gov/scripts/cdrh/cfdocs/cfcfr/CFRSearch.cfm?fr=207.35, paragraph 4.ii; regulation changed in 2017: https://www.fda.gov/Drugs/GuidanceComplianceRegulatoryInformation/DrugRegistrationandListing/ucm2007058.htm), as far as I have witnessed such situation is exceedingly rare, to the point of being negligible even in nation-wide datasets with over one billion records spanning 10 years of filled prescriptions in U.S. pharmacies.  
  
#### Do I need to convert the codes between NDC-10, NDC-11, XXXXX-XXX-XX (5-3-2), XXXX-XXXX-XX (4-4-2), XXXXX-XXXX-X (5-4-1)?
This is not necessary because RxNorm natively supports any valid NDC format. If for some other reason you need to convert NDC formats yourself, here is a guide to the equivalencies: https://phpa.health.maryland.gov/OIDEOR/IMMUN/Shared%20Documents/Handout%203%20-%20NDC%20conversion%20to%2011%20digits.pdf
