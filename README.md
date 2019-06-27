#### Mapping of U.S. Food and Drug Administration (FDA) National Drug Codes (NDC) to Drug Classes  
###### codename: ndc_map
*_Mapping NDCs to Anatomical Therapeutic Chemical (ATC) Level 5, Veterans' Affairs Drug Classes, MESH Pharmacological Actions, SNOMED Clinical Terms, and other Drug Classification Systems and Terminologies_*
  
This script provides the drug class or classes from a given drug classification system (e.g. ATC -- https://whocc.no/atc_ddd_index/) of each FDA National Drug Code (NDC), if any is available from querying the online RxNorm API at https://rxnav.nlm.nih.gov/. The program can read the input NDCs from a flat list (e.g. TXT file, one NDC per line) or from one column in a CSV file.  
  
This work is an **update** from what was presented as a poster at the 2017 Annual Symposium of the American Medical Informatics Association (AMIA). Still, if you are going to use this script or these NDC-ATC maps, please take time to understand the numbers contained in the poster (PDFs are in this repository), because they CAN affect data analyses. I have also published a deeper analysis and comparison of drug classification systems in a paper (https://mor.nlm.nih.gov/pubs/pdf/2016-dmmi-fk.pdf) but tl;dr: unless your use case is particularly specialized, ATC is the best drug classification for most cases of large dataset analyses. The Veterans' Affairs Drug Classes attain the same high level of coverage of NDCs, but they don't provide the accessible hierarchy that ATC provides.  
  
**There are still pending tasks in this new script (as compared to the older version in folder "Old script"), but it should work "out-of-the-box" if you follow the instructions in the .R  file under heading "How to execute this script."**
  
All contents of this repository are under an Attribution-ShareAlike-NonCommercial 4.0 International license. Please see details at http://creativecommons.org/licenses/by-nc-sa/4.0/. Please feel free to contact me about this work! Reading and reusing code can be made so much easier after a quick talk with the original author.  
  
**_If you do not know the R programming language or are unable to run the code yourself for any reason, and just need a NDC-to-ATC map for your project, see the folder "FDA NDC Database File with ATC4". It contains all NDCs from the FDA database with their available mappings. Otherwise, if you can send me your list of NDCs, I can run the script for you. Contact me at 627@kury.dev.**  
**--Fabrício Kury**  
  
Search tags: thesaurus drug class map equivalence correspondance classification
  
#### Do I need the year and month the NDC was used?  
One same NDC can have been reused, i.e. represented different drugs at different points in time: https://www.accessdata.fda.gov/scripts/cdrh/cfdocs/cfcfr/CFRSearch.cfm?fr=207.35, paragraph 4.ii; regulation changed in 2017: https://www.fda.gov/Drugs/GuidanceComplianceRegulatoryInformation/DrugRegistrationandListing/ucm2007058.htm. However, as far as I have witnessed such situation is exceedingly rare.  
From the perspective of RxNorm, each NDC has a history of zero or any number of RxCUIs that correspond or have corresponded to them during some period. Over time RxCUIs are also updated and re-structured, with some containing mappings to drug classes and some not.  
This means that most NDCs correspond, conceptually, to the same drug product (active ingredients and packaging) during its entire presence in the databaset, even if that "conceptual" drug product might have had different RxCUIs over time. So, if your intent is to find RxCUIs holding mappings to a given terminology or drug classification system, you probably want to make your choice of RxCUI for each NDC contingent on whether it has your desidred mapping(s).   
  