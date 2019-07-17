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
- the MESH Pharmacological Actions code corresponding to the NDC.  
  
This work is an update from what was presented as a poster at the 2017 Annual Symposium of the American Medical Informatics Association (AMIA). Still, if you are going to use this script or its NDC <-> drug class maps, please take time to understand the numbers contained in the poster (PDFs are in this repository), because they CAN affect data analyses.  
  
I have also published a deeper analysis and comparison of drug classification systems in a paper (https://mor.nlm.nih.gov/pubs/pdf/2016-dmmi-fk.pdf). **_TL;DR_**: unless your use case is particularly specific, ATC is the best drug classification for most cases of large dataset analyses. The Veterans' Affairs Drug Classes attain the same high level of coverage of NDCs as ATC, but they don't provide the accessible hierarchy that ATC does.  
  
#### How to run the script
This script should work out of the box if you follow the instructions in the .R  file under the heading "How to execute this script." There is still extra code to write -- see the TODOs in the .R file.  
  
#### About performance
The RxNav API Terms of Service requires users to make no more than 20 requests per second per IP address (https://rxnav.nlm.nih.gov/TermOfService.html). The script will cache its internet calls, so it works faster towards the end as more NDCs map to RxCUIs that have already appeared before. But still, from my experience on a laptop over good wi-fi, one should expect 12 to 18 hours of execution time per 100,000 unique NDCs, which means about 1.5 to 2.3 NDCs per second. If execution is interrupted (intentionally or not), next time you run the script it will start from zero again, but the queries will still be cached (stored in RDS files) so it will progress quite fast from the beginning, until it reaches entries requiring novel online queries at the point it had been interrupted.  
Because of the automatic caching, and the limit web queries per second, requesting more than one code at once is unlikely to be any faster than requesting just one per run of the script. In fact, the risk of slowing it down is probably bigger than the chance of speeding it up, because of the duplication of the codes which lead to more lines to go through (explained in the header of the .R file).
  
#### License
All contents of this repository are under an Attribution-ShareAlike-NonCommercial 4.0 International license. Please see details at http://creativecommons.org/licenses/by-nc-sa/4.0/. Please feel free to contact me about this work! Reading and reusing code can be made so much easier after a quick talk with the original author.  
  
#### Pre-made NDC-to-drug class maps
If you do not know the R programming language or are unable to run the code yourself for any reason, and just need a NDC-to-drug class map for your project, see the folder "FDA NDC Database File with ATC4". It contains all NDCs from the FDA database (https://www.fda.gov/drugs/drug-approvals-and-databases/national-drug-code-directory) with pre-joined mappings.  
Otherwise, if you can send me your list of NDCs, I can run the script for you. Contact me at 627@kury.dev. **_--Fabrício Kury_**  
  
Search tags: thesaurus drug class map equivalence correspondance classification
  
#### Do I need the year and month the NDC was used?  
One same NDC can have been reused, i.e. represented different drugs at different points in time: https://www.accessdata.fda.gov/scripts/cdrh/cfdocs/cfcfr/CFRSearch.cfm?fr=207.35, paragraph 4.ii; regulation changed in 2017: https://www.fda.gov/Drugs/GuidanceComplianceRegulatoryInformation/DrugRegistrationandListing/ucm2007058.htm. However, as far as I have witnessed such situation is exceedingly rare, to the point of being negligible even in large longitudinal datasets.  
From the perspective of RxNorm, each NDC has a history of zero or any number of RxCUIs that correspond or have corresponded to them during some period. Over time RxCUIs are also updated and re-structured, with some containing mappings to drug classes and some not.  
This means that most NDCs correspond, conceptually, to the same drug product (active ingredients and packaging) during its entire presence in the databaset, even if that "conceptual" drug product might have had different RxCUIs over time. So, if your intent is to find RxCUIs holding mappings to a given terminology or drug classification system, you probably want to make your choice of RxCUI for each NDC contingent on whether it has your desidred mapping(s).   
  
