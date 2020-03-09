/*******************************************************************************

Project				: Escaping Poverty - Northern Belt Endline Survey
Author				: Sarina Jain
Date Created		: 1/19/2020
Date Last Modified	: 1/20/2020
Purpose				: Merges missing respondent data with survey data, then compares 
					against master dataset to determine outstanding list of households
					and adults left to survey (for mop up planning)
					
Notes:				Code is modified from do file called 05a_tracking_summary

*******************************************************************************/

// ADDING ADDITIONAL COMMENT

clear all
set more off
version 15.1

/*******************************************************************************
								SET GLOBALS
*******************************************************************************/

** Set current directory & run globals do file

cd "$dir" // defined in Master do file
qui do "02_dofiles\0_globals.do"

/*******************************************************************************
					APPEND MISSING RESPONDENT FORM & SURVEY DATA
*******************************************************************************/

use "${dta_survey_adult}_prepped_checked.dta", clear

gen survey_count = 1

collapse (sum) survey_count, by(hhid)

merge 1:1 hhid using "${dta_survey_household}_prepped_checked.dta", assert(2 3) nogen

replace survey_count = 0 if mi(survey_count)

gen adult_count = 0
replace adult_count = 1 if !mi(as_male_available) | !mi(as_female_available)
replace adult_count = 2 if !mi(as_male_available) & !mi(as_female_available)

assert survey_count <= adult_count
gen status_adult = 1 if adult_count == survey_count & !mi(adult_count)
replace status_adult = 2 if adult_count != survey_count & !mi(adult_count)

order survey_count, after(adult_count)

lab def status_adult 1 "Surveyed" 2 "Incomplete surveys/tracked but not yet surveyed"
lab val status_adult status_adult

keep hhid enum_id enum_name submissiondate status_adult adult_count survey_count

tempfile survey_data
save 	`survey_data'

/*******************************************************************************
					APPEND MISSING RESPONDENT FORM & SURVEY DATA
*******************************************************************************/

use "${dir_survey}/EP Endline Missing Respondent Form_prepped.dta", clear

keep if missing == 1 // missing HHs only

gen relocate = temp_relocate if !mi(temp_relocate)
replace relocate = perm_relocate if !mi(perm_relocate)

tempfile mrf_data
save 	`mrf_data'

use `survey_data', clear

merge 1:1 hhid using `mrf_data', keepusing(missing_why relocate)

gen status = 1 if _merge == 1 | _merge == 3
replace status = 2 if _merge == 2

replace missing_why = . if _merge == 3 // if a HH was initially reported missing but then later surveyed, don't count it as missing

drop _merge

tempfile merged_data
save 	`merged_data'

/*******************************************************************************
						MERGE AGAINST MASTER DATASET
*******************************************************************************/

use "${dir_preloads}/ep_endline_preloads.dta", clear

merge 1:1 hhid using `merged_data'

drop if _merge == 2 // false launch households
drop false_launch_yn

replace status = 3 if _merge == 1

lab def status 1 "Surveyed" 2 "Tracked but not surveyed" 3 "Not yet tracked"
lab val status status

drop _merge

bysort hhidvillage: egen min_id = min(enum_id)
replace enum_id = min_id if mi(enum_id) // will just be used to determine the correct team assignment for each HH
drop min_id

save `merged_data', replace

import excel using "${dir_document}/Field Staff Roster & Contact Info.xlsx", firstrow clear

keep if Position == "Surveyor" | UniqueID == 170642 // one enumerator was later promoted to auditor
replace TeamLeader = "Ayikna" if UniqueID == 170642 // originally part of the Talensi team

rename (UniqueID FullName TeamLeader) (enum_id enum_name tl_name)
keep enum_id enum_name tl_name

merge 1:m enum_id using `merged_data', assert(2 3) nogen

/*******************************************************************************
						FLAG PROBLEMATIC HOUSEHOLDS
*******************************************************************************/

/*
gen mop_up = (status == 2 & missing_why == 3) | status == 3
lab def mop_up 1 "Yes" 0 "No"
lab val mop_up mop_up
*/

bysort hhidvillage: egen visited = min(status)

gen confirm = .

lab var region 			"Region"
lab var district		"District"
lab var village			"Community"
lab var hhid			"Household ID"
lab var enum_name		"Enumerator"
lab var submissiondate	"Submission date"
lab var status_adult	"Adult surveys"
lab var adult_count		"Adult survey count"
lab var survey_count	"Adult surveys submitted"
lab var missing_why		"Why not surveyed"
lab var status			"Status"
lab var confirm			"Confirmed status?"
lab var tl_name			"Team"
lab var relocate		"Relocation"

sort tl_name region district village

preserve

keep if status == 2 | status == 3
drop if visited == 3 // communities we have not yet entered
assert !mi(tl_name)

replace missing_why = 6 if mi(missing_why)
lab def missing_why 6 "N/A", modify

loc 	 export_vars tl_name region district village hhid status missing_why relocate confirm
keep 	`export_vars'
order 	`export_vars'

export excel using "${dir_tracking_out}/mop_up_roster.xlsx", firstrow(varl) sheet("Household") sheetreplace

restore

/*******************************************************************************
						FLAG PROBLEMATIC ADULTS
*******************************************************************************/

use "${dir_survey}/EP Endline Missing Respondent Form_prepped.dta", clear

keep if missing == 2 // missing adults only
isid hhid

gen relocate = temp_relocate if !mi(temp_relocate)
replace relocate = perm_relocate if !mi(perm_relocate)

tempfile mrf_data
save `mrf_data'

use `survey_data', clear

merge 1:1 hhid using `mrf_data', keepusing(missing_resp missing_why relocate) nogen

save `merged_data', replace

use "${dir_preloads}/ep_endline_preloads.dta", clear

merge 1:1 hhid using `merged_data'

drop if _merge == 2 // false launch households
drop false_launch_yn

replace status_adult = 3 if _merge == 1
lab def status_adult 3 "Household not yet surveyed", modify

bysort hhidvillage: egen min_id = min(enum_id)
replace enum_id = min_id if mi(enum_id)

drop hhidregion hhiddistrict hhidvillage _merge min_id

save `merged_data', replace

import excel using "${dir_document}/Field Staff Roster & Contact Info.xlsx", firstrow clear

keep if Position == "Surveyor" | UniqueID == 170642
replace TeamLeader = "Ayikna" if UniqueID == 170642

rename (UniqueID FullName TeamLeader) (enum_id enum_name tl_name)
keep enum_id enum_name tl_name

merge 1:m enum_id using `merged_data', assert(2 3) nogen

/*
gen mop_up = (status_adult == 2 & (mi(missing_why) | missing_why == 3)) | status_adult == 3
lab def mop_up 1 "Yes" 0 "No"
lab val mop_up mop_up
*/

bysort village: egen visited = min(status_adult)

gen confirm = .

lab var region 			"Region"
lab var district		"District"
lab var village			"Community"
lab var hhid			"Household ID"
lab var enum_name		"Enumerator"
lab var submissiondate	"Submission date"
lab var status_adult	"Status"
lab var adult_count		"Adult survey count"
lab var survey_count	"Adult surveys submitted"
lab var missing_resp	"Missing respondent(s)"
lab var missing_why		"Why not surveyed"
lab var confirm			"Confirmed status?"
lab var tl_name			"Team"
lab var relocate		"Relocation"

sort tl_name region district village

keep if status_adult == 2 | status_adult == 3
drop if visited == 3
assert !mi(tl_name)

replace missing_why = 6 if mi(missing_why)
lab def missing_why 6 "N/A", modify

loc 	 export_vars tl_name region district village hhid adult_count survey_count status_adult missing_resp missing_why relocate confirm
keep 	`export_vars'
order 	`export_vars'

export excel using "${dir_tracking_out}/mop_up_roster.xlsx", firstrow(varl) sheet("Adult") sheetreplace
