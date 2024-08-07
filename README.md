### Mapping U.S. Food and Drug Administration (FDA) National Drug Codes (NDC) to Drug Classes and Codes  
###### codename: ndc_map
*_Mapping NDCs to Anatomical Therapeutic Chemical (ATC) Level 5, Veterans' Affairs Drug Classes, MESH Pharmacological Actions, SNOMED Clinical Terms, and other Drug Classification Systems and Terminologies_*

## **!!! THIS SCRIPT IS DEPRECATED. PLEASE SEE A MORE MODERN PYTHON SCRIPT AT https://github.com/fabkury/n2c !!!**
  
This script provides the drug class (or classes) from a given drug classification system (e.g. ATC) of each FDA National Drug Code (NDC), if any is available. It does that by querying the online RxNorm API at https://rxnav.nlm.nih.gov/. This script is just a helper to query the API in bulk and write the resposes to a convenient CSV file -- the mappings themselves are maintained and provided for free by RxNorm. The program can read the input NDCs from a flat list (text file, one NDC per line) or from one column in a CSV file.  
    
It is also possible to request:  
- the generic active ingredients of the NDC, which are independent of drug classification systems,  
- whether the NDC is a brand name or a generic,  
- the strength of the drug product (as an unstructured text string),  
- the SNOMED CT (Clinical Terms) code corresponding to the NDC,  
- the MESH Pharmacological Actions code corresponding to the NDC,  
- the Veterans' Affairs Drug Class code corresponding to the NDC,  
- if ATC level 5 is requested, the script will additionally scrape each code's Administration Route, Defined Daily Dose (DDD), and Note (if any) from the website of the official ATC index at https://whocc.no/atc_ddd_index/.  
  
This work is an update from what was presented as a poster at the 2017 Annual Symposium of the American Medical Informatics Association (AMIA). If you are going to use this script or its NDC <-> drug class maps, please take time to understand the numbers contained in the poster (PDFs are in this repository), because they CAN affect data analyses. At the very minimum, you need to understand the issues regarding coverage (missing codes) and ambiguity (duplication of codes).  
  
I have also published a deeper analysis and comparison of drug classification systems in a paper (_Desiderata for Drug Classification Systems for their Use in Analyzing Large Drug Prescription Datasets_ -- https://github.com/fabkury/ddcs/blob/master/2016-dmmi-fk.pdf). **_TL;DR_**: unless your use case is particularly specific, ATC is the best drug classification for most cases of large dataset analyses. The Veterans' Affairs Drug Classes attain the same high level of coverage of NDCs as ATC, but they don't provide a comprehensive and accessible hierarchy like ATC.  
  
### How to run
This script should work out of the box if you follow the instructions in the .R  file under the heading "How to execute this script."   
  
### But I just need the NDC-to-drug class map file! Do you have pre-made maps?
If you cannot run this script yourself for any reason, but need an NDC-to-drug class map for your project, I can offer you two options.  
 - One, see the folder "FDA NDC Database File with ATC4." The CSV files in there contain all NDCs from the FDA database (https://www.fda.gov/drugs/drug-approvals-and-databases/national-drug-code-directory) with their classes, as indicated by the folder and file names. **Notice, however, that this file does *not* contain all NDCs you may find in a given dataset, because the NDC Directory does _not_ contain all NDCs that ever existed.**  
 - Two, I can run the script for you if you are able to send me your list of NDCs. Over time many people have approached me with such request, as well as their questions about working with NDCs and drug classes. I am happy to help. Contact me at 191206@kury.dev.  
  
### Do I need the year and month the NDC was used?  
You do not. The script does not consider dates, only NDCs. Although in principle one same NDC can have been recycled, i.e. represented different drugs at different points in time (https://www.accessdata.fda.gov/scripts/cdrh/cfdocs/cfcfr/CFRSearch.cfm?fr=207.35, paragraph 4.ii), the combination of coincidences required for this to happen makes the probability vanishingly small. I have measured myself that NDC "collisions" are negligible even in nation-wide (USA) datasets with over one billion filled prescriptions across 10 years. Moreover, this regulation was changed in 2017 (https://www.fda.gov/Drugs/GuidanceComplianceRegulatoryInformation/DrugRegistrationandListing/ucm2007058.htm) and NDCs are no longer being recycled.  
  
### Do I need to convert the codes between NDC-10, NDC-11, XXXXX-XXX-XX (5-3-2), XXXX-XXXX-XX (4-4-2), XXXXX-XXXX-X (5-4-1)?
This is not necessary because RxNorm natively supports any valid NDC format. If for some other reason you need to convert NDC formats yourself, here is a guide to the equivalencies: https://phpa.health.maryland.gov/OIDEOR/IMMUN/Shared%20Documents/Handout%203%20-%20NDC%20conversion%20to%2011%20digits.pdf  

### Is it OK to mix NDC-10 and NDC-11 in the same run of the script?
That is not a problem, because RxNorm transparently supports any valid NDC format.    
  
  
### Contributing to this script
There are extra features that could be implemented. See the TODOs in the .R file.  
  
### About performance
The RxNav API Terms of Service requires users to make no more than 20 requests per second per IP address (https://rxnav.nlm.nih.gov/TermOfService.html). This script will respect this limit. It will also cache its internet calls in RDS files, so it won't ask the API for the same thing twice, unless you intentionally remove the cache files.  
The cache makes the script run faster the closer it gets to the end, because more NDCs map to RxCUIs that have already appeared before, which means it can skip the second online API call, asking the server for details about the RxCUI. Regardless of obeying or not the limit of 20 requests per second, from my experience on a laptop over gigabit wi-fi internet I have seen 12 to 18 hours of run time per 100,000 unique NDCs. That means about 1.5 to 2.3 different NDCs per second. If execution is interrupted, intentionally or not, next time you run the script will start from zero, but the prior work will be in the cache (stored in the RDS files), so the script will progress extremely fast in the beginning, until it reaches novel NDCs, which need online queries, very close to the exact point in the list where it was interrupted.     
  
This script allows you to query for multiple coding systems in the same run (e.g. ATC codes and VA Drug Classes). However, because of the caching, and the limit of queries per second, I do not advise you use that feature because it is unlikely to be faster than doing separate full runs. In fact, it could even be slower, because rows will get duplicated whenever one NDC maps to multiple codes, and the duplications of one coding system will multiply those from other coding systems. For example, if one NDC maps to 3 ATC codes and 2 VA Drug Class codes, there will be 2 * 3 = 6 rows in the results corresponding to all combinations of these codes.  
  
### License
All contents of this repository are under an Attribution-ShareAlike-NonCommercial 4.0 International license. Please see details at http://creativecommons.org/licenses/by-nc-sa/4.0/.  
  
### Contact the author
Please feel free to contact me about this work! Reading and using someone else's code can become so much easier after a quick conversation.  
Contact me at 191206@kury.dev. **_--Fabrício Kury_**  
  
Search tags: thesaurus drug class map equivalence correspondence classification
  
