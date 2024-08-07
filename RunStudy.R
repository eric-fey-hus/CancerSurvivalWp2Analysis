# calculating the number of years of extrapolation for your database ----
# amount of followup in your database plus 10 years
timeinyrs <- 20

#Create folder for the results
if (!file.exists(output.folder)){
  dir.create(output.folder, recursive = TRUE)}

#start the clock
start<-Sys.time()

# start log ----
log_file <- paste0(output.folder, "/", db.name, "_log.txt")
logger <- create.logger()
logfile(logger) <- log_file
level(logger) <- "INFO"

# create study cohorts ----

# get concept sets from cohorts----
cancer_concepts <- CodelistGenerator::codesFromCohort(
  path = here::here("1_InstantiateCohorts", "Cohorts" ) ,
  cdm = cdm,
  withConceptDetails = FALSE)

# instantiate the cohorts with no prior history 
cdm <- CDMConnector::generateConceptCohortSet(
  cdm,
  conceptSet = cancer_concepts,
  name = "outcome",
  limit = "first",
  requiredObservation = c(0, 0),
  end = "observation_period_end_date",
  overwrite = TRUE )


if(priorhistory == TRUE){
  
  # add in prior history
  cdm$outcome <- cdm$outcome %>% 
    PatientProfiles::addPriorObservation(
      cdm = cdm,
      indexDate = "cohort_start_date")
  
  #for those with prior history remove those with less than 365 days of prior history
  cdm$outcome <- cdm$outcome %>% 
    filter(prior_observation >= 365) %>% 
    select(-c(prior_observation))
  
}

cdm$outcome <- CDMConnector::recordCohortAttrition(cohort = cdm$outcome,
                                                   reason="Excluded patients with less than 365 prior history" )


info(logger, "SUBSETTING CDM")
cdm <- CDMConnector::cdmSubsetCohort(cdm, "outcome")
info(logger, "SUBSETTED CDM")

# instantiate exclusion any prior history of malignancy
info(logger, "INSTANTIATE EXCLUSION ANY MALIGNANT NEOPLASTIC DISEASE (EX SKIN CANCER)")

codelistExclusion <- CodelistGenerator::codesFromConceptSet(here::here("1_InstantiateCohorts", "Exclusion"), cdm)
# add cancer concepts to exclusion concepts to make sure we capture all exclusions
codelistExclusion <- list(unique(Reduce(union_all, c(cancer_concepts, codelistExclusion))))

#rename list of concepts
names(codelistExclusion) <- "anymalignancy"

cdm <- CDMConnector::generateConceptCohortSet(cdm = cdm,
                                              conceptSet = codelistExclusion,
                                              name = "exclusion",
                                              overwrite = TRUE)

info(logger, "INSTANTIATED EXCLUSION ANY MALIGNANT NEOPLASTIC DISEASE (EX SKIN CANCER)")

# create a flag of anyone with MALIGNANT NEOPLASTIC DISEASE (excluding skin cancer) prior to cancer diagnoses in our cohorts
cdm$outcome <- cdm$outcome %>%
  PatientProfiles::addCohortIntersect(
    cdm = cdm,
    targetCohortTable = "exclusion",
    targetStartDate = "cohort_start_date",
    targetEndDate = "cohort_end_date",
    flag = TRUE,
    count = FALSE,
    date = FALSE,
    days = FALSE,
    window = list(c(-Inf, -1))
  )

# remove any patients with other cancers on same date not in our list of cancers
# get the any malignancy codelist
codelistExclusion1 <- CodelistGenerator::codesFromConceptSet(here::here("1_InstantiateCohorts", "Exclusion"), cdm)

# merge all concepts for all cancers together
codes2remove <- list(unique(Reduce(union_all, c(cancer_concepts))))
names(codes2remove) <- "allmalignancy"

# remove lists from our cancers of interest from the any malignancy list
codes2remove <- list(codelistExclusion1$cancerexcludnonmelaskincancer[!codelistExclusion1$cancerexcludnonmelaskincancer %in% codes2remove$allmalignancy])
names(codes2remove) <- "allmalignancy"

#instantiate any malignancy codes minus our cancers of interest
cdm <- CDMConnector::generateConceptCohortSet(cdm = cdm,
                                              conceptSet = codes2remove ,
                                              name = "allmalignancy",
                                              overwrite = TRUE)

# create a flag of anyone with MALIGNANT NEOPLASTIC DISEASE (excluding skin cancer) ON cancer diagnosis date but removing our codes of interest
# in doing so we are capturing people with other cancers on the same day and wont exclude everyone
cdm$outcome <- cdm$outcome %>%
  PatientProfiles::addCohortIntersect(
    cdm = cdm,
    targetCohortTable = "allmalignancy",
    targetStartDate = "cohort_start_date",
    targetEndDate = "cohort_end_date",
    flag = TRUE,
    count = FALSE,
    date = FALSE,
    days = FALSE,
    window = list(c(0, 0))
  )


# get data variables
cdm$outcome <- cdm$outcome %>%
  # this section uses patient profiles to add in age and age groups as well as
  # sex and prior history
  PatientProfiles::addDemographics(
    age = TRUE,
    ageName = "age",
    ageGroup =  list(
      "age_gr" =
        list(
          "18 to 39" = c(18, 39),
          "40 to 49" = c(40, 49),
          "50 to 59" = c(50, 59),
          "60 to 69" = c(60, 69),
          "70 to 79" = c(70, 79),
          "80 +" = c(80, 150)
        )
    )
  ) %>%
  
  # this section adds in date of death, removes those with a diagnosis outside the study period and
  # date.
  # Also code sets the end date 31 dec 19 for those with observation period past this date
  # and removes death date for people with death past dec 2019 (end of study period)
  
  dplyr::left_join(cdm$death %>%
                     select("person_id",  "death_date") %>%
                     distinct(),
                   by = c("subject_id"= "person_id")) %>%
  dplyr::left_join(cdm$observation_period %>%
                     select("person_id",  "observation_period_end_date") %>%
                     distinct(),
                   by = c("subject_id"= "person_id")) %>%
  CDMConnector::computeQuery() %>%
  dplyr::filter(cohort_start_date >= startdate) %>%
  dplyr::filter(cohort_start_date <= '2019-12-31') %>%
  dplyr::mutate(observation_period_end_date_2019 = ifelse(observation_period_end_date >= '2019-12-31', '2019-12-31', NA)) %>%
  dplyr::mutate(observation_period_end_date_2019 = as.Date(observation_period_end_date_2019) ) %>%
  dplyr::mutate(observation_period_end_date_2019 = ifelse(is.na(observation_period_end_date_2019), observation_period_end_date, observation_period_end_date_2019 )) %>%
  dplyr::mutate(status = death_date) %>%
  dplyr::mutate(status = ifelse(death_date > '2019-12-31', NA, status)) %>%
  dplyr::mutate(status = ifelse(death_date > observation_period_end_date_2019, NA, status)) %>%
  dplyr::mutate(status = ifelse(is.na(status), 1, 2 )) %>%
  dplyr::mutate(time_days = observation_period_end_date_2019 - cohort_start_date ) %>%
  dplyr::mutate(time_years = time_days / 365) %>%
  dplyr::filter(age_gr != "None") %>%
  dplyr::mutate(sex_age_gp = str_c(age_gr, sex, sep = "_" ),
                future_observation = time_days) %>%
  dplyr::rename(anymalignancy = flag_anymalignancy_minf_to_m1 ) %>%
  CDMConnector::computeQuery()

# # see if there is prostate cancer in database then run this code and put in both if statements
# # remove females from prostate cancer cohort (misdiagnosis)
# # get cohort definition id for prostate cancer
if( "Prostate" %in% names(cancer_concepts) == TRUE){
  
  prostateID <- CDMConnector::cohortSet(cdm$outcome) %>%
    dplyr::filter(cohort_name == "Prostate") %>%
    dplyr::pull("cohort_definition_id") %>%
    as.numeric()
  
  # remove females from prostate cancer cohort (misdiagnosis)
  cdm$outcome <- cdm$outcome %>%
    dplyr::filter(!(sex == "Female" & cohort_definition_id == prostateID))
}

#update the attrition after those outside the study period are removed
cdm$outcome <- CDMConnector::recordCohortAttrition(cohort = cdm$outcome,
                                                   reason="Exclude patients outside study period" )

# remove those with any a prior malignancy (apart from skin cancer in prior history)
cdm$outcome <- cdm$outcome %>%
  dplyr::filter(anymalignancy != 1)

#update the attrition
cdm$outcome <- CDMConnector::recordCohortAttrition(cohort = cdm$outcome,
                                                   reason="Exclude patients with any prior history of maglinancy (ex skin cancer)" )


# remove those with date of death and cancer diagnosis on same date
cdm$outcome <- cdm$outcome %>% 
  dplyr::filter(time_days > 0)

cdm$outcome <- CDMConnector::recordCohortAttrition(cohort = cdm$outcome,
                                                    reason="Exclude patients with death date same as cancer diagnosis date" )

# removes any patients with multiple cancers on same date (just the cancers of interest at the moment)
cdm$outcome <- cdm$outcome %>%
  dplyr::distinct(subject_id, .keep_all = TRUE)

cdm$outcome <- cdm$outcome %>%
  dplyr::filter(flag_allmalignancy_0_to_0 != 1)

cdm$outcome <- CDMConnector::recordCohortAttrition(cohort = cdm$outcome,
                                                    reason="Exclude patients with multiple cancers on different sites diagnosed on same day" )

# remove those with no sex
cdm$outcome <- cdm$outcome %>%
  dplyr::filter(!(sex == "None" | sex == "none"))

cdm$outcome <- CDMConnector::recordCohortAttrition(cohort = cdm$outcome,
                                                   reason="Exclude patients with no sex defined" )

# only run analysis where we have counts more than 200 ----
cancer_cohorts <- CDMConnector::cohortSet(cdm$outcome) %>%
  dplyr::inner_join(CDMConnector::cohortCount(cdm$outcome), by = "cohort_definition_id") %>%
  dplyr::arrange(cohort_definition_id) %>% 
  dplyr::filter(number_subjects >= 200)

# filter the data to cohorts that have more than 200 patients
id <- cohortCount(cdm$outcome) %>% dplyr::filter(number_subjects >= 200) %>% dplyr::pull("cohort_definition_id")
cdm$outcome <- cdm$outcome %>% filter(cohort_definition_id %in% id)

#update the attrition
cdm$outcome <- CDMConnector::recordCohortAttrition(cohort = cdm$outcome,
                                                   reason="Removing cancer cohorts from analysis with less than 200 patients" )


# add bespoke code for ECI (Edinburgh cancer registry) to remove males from breast cancer cohort due to ethical approval
if(db.name == "ECI"){
  
breastID <- CDMConnector::cohortSet(cdm$outcome) %>%
  dplyr::filter(cohort_name == "Breast") %>%
  dplyr::pull("cohort_definition_id") %>%
  as.numeric()

# remove males from breast cancer cohort
cdm$outcome <- cdm$outcome %>% 
  dplyr::filter(sex == "Female" & cohort_definition_id == breastID)


cdm$outcome <- CDMConnector::recordCohortAttrition(cohort = cdm$outcome,
                                                   reason="Removing male breast cancer patients" )
}

# collect to use for analysis
Pop <- cdm$outcome %>% dplyr::collect()

info(logger, 'SNAPSHOT CDM')
print(paste0("SNAPSHOT CDM")) 

# snapshot the cdm
if(db.name != "CRN"){ 
  snapshotcdm <- CDMConnector::snapshot(cdm) %>% 
    mutate(Database = CDMConnector::cdm_name(cdm)) %>% 
    mutate(StudyPeriodStartDate = startdate)
  
} else {
  
  print(paste0("SNAPSHOT CDM for CRN")) 
  
  npersons <- cdm$person %>% 
    dplyr::tally() %>% 
    dplyr::collect()
  
  early_obs <- cdm$observation_period %>%
    summarise(earliest_start_date = min(observation_period_start_date, na.rm = TRUE)) %>%
    collect()
  
  latest_obs <- cdm$observation_period %>%
    summarise(latest_start_date = max(observation_period_end_date, na.rm = TRUE)) %>%
    collect()
  
  observation_per_count <- cdm$observation_period %>% 
    count() %>% collect()
  
  snapshotcdm1 <- cdm$cdm_source %>%  dplyr::collect()
  snapshotcdm1 <- snapshotcdm1 %>% 
    mutate(cdm_name = db.name,
           Database = db.name,
           person_count = npersons,
           StudyPeriodStartDate = startdate,
           snapshot_date = Sys.Date(),
           earliest_observation_period_start_date = early_obs,
           latest_observation_period_end_date = latest_obs ,
           observation_period_count = observation_per_count
    ) %>% 
    select(-c(cdm_source_abbreviation,
              cdm_etl_reference,
              source_release_date )) %>% 
    rename(cdm_description = source_description,
           cdm_documentation_reference = source_documentation_reference
    )
  
  
}

info(logger, 'GETTING COHORT ATTRITION')
print(paste0("GETTING COHORT ATTRITION")) 
#get attrition for the cohorts and add cohort identification
attritioncdm <- CDMConnector::cohort_attrition(cdm$outcome) %>% 
  dplyr::left_join(
    cohortSet(cdm$outcome) %>% select(c("cohort_definition_id", "cohort_name")),
    by = join_by(cohort_definition_id),
    relationship = "many-to-many",
    keep = FALSE
  ) %>% 
  dplyr::relocate(cohort_name) %>% 
  dplyr::mutate(Database = cdm_name(cdm)) %>% 
  dplyr::rename(Cancer = cohort_name)

info(logger, 'GOT COHORT ATTRITION')
print(paste0("GOT COHORT ATTRITION")) 

# Setting up information for extrapolation methods to be used ---
extrapolations <- c("gompertz", 
                    "weibullph" ,
                    "exp", 
                    "llogis", 
                    "lnorm",
                    "gengamma",
                    "spline1",
                    "spline3",
                    "spline1o",
                    "spline3o",
                    "spline1n",
                    "spline3n")

extrapolations_formatted <- c("Gompertz",
                              "Weibull" ,
                              "Exponential",
                              "Log-logistic",
                              "Log-normal",
                              "Generalised Gamma",
                              "Spline Hazard (1 knot)",
                              "Spline Hazard (3 knots)" ,
                              "Spline Odds (1 knot)",
                              "Spline Odds (3 knots)" ,
                              "Spline Normal (1 knot)",
                              "Spline Normal (3 knots)")

# setting up time for extrapolation ----
t <- seq(0, timeinyrs*365.25, by=40)

#Run analysis ----

#pick up functions
source(here::here("2_Analysis","Functions.R"))

if(PerformTruncatedAnalysis == TRUE){
#whole population
print(paste0("1 of 6: RUNNING ANALYSIS FOR WHOLE POPULATION")) 
info(logger, 'RUNNING ANALYSIS FOR WHOLE POPULATION')
source(here::here("2_Analysis","Analysis.R"))
info(logger, 'ANALYSIS RAN FOR WHOLE POPULATION')
print(paste0("1 of 6: FINISHED ANALYSIS FOR WHOLE POPULATION")) 

#sex analysis
print(paste0("2 of 6: RUNNING ANALYSIS FOR SEX")) 
info(logger, 'RUNNING ANALYSIS FOR SEX')
source(here::here("2_Analysis","AnalysisSex.R"))
info(logger, 'ANALYSIS RAN FOR SEX')
print(paste0("2 of 6: ANALYSIS RAN FOR SEX")) 

#age analysis
print(paste0("3 of 6: RUNNING ANALYSIS FOR AGE")) 
info(logger, 'RUNNING ANALYSIS FOR AGE')
source(here::here("2_Analysis","AnalysisAge.R"))
info(logger, 'ANALYSIS RAN FOR AGE')
print(paste0("3 of 6: ANALYSIS RAN FOR AGE")) 

# age*sex analysis KM only
print(paste0("4 of 6: RUNNING ANALYSIS FOR AGE*SEX ONLY KM")) 
info(logger, 'RUNNING ANALYSIS FOR AGE*SEX ONLY KM')
source(here::here("2_Analysis","AnalysisAgeSex.R"))
info(logger, 'ANALYSIS RAN FOR AGE*SEX ONLY KM')
print(paste0("4 of 6: ANALYSIS RAN FOR AGE*SEX ONLY KM")) 

#truncation analysis
print(paste0("5 of 6: RUNNING ANALYSIS FOR TRUNCATED FOLLOW UP")) 
info(logger, 'RUNNING ANALYSIS FOR TRUNCATED FOLLOW UP')
source(here::here("2_Analysis","Truncation_follow_up.R"))
info(logger, 'ANALYSIS RAN FOR FOR TRUNCATED FOLLOW UP')
print(paste0("5 of 6: ANALYSIS RAN FOR FOR TRUNCATED FOLLOW UP")) 

#running tableone characterisation
print(paste0("6 of 6: RUNNING TABLE ONE CHARACTERISATION")) 
info(logger, 'RUNNING TABLE ONE CHARACTERISATION')
source(here::here("2_Analysis","Tableone.R"))
info(logger, 'TABLE ONE CHARACTERISATION RAN')
print(paste0("6 of 6: TABLE ONE CHARACTERISATION RAN")) 

} else {
  
  #whole population
  print(paste0("1 of 5: RUNNING ANALYSIS FOR WHOLE POPULATION")) 
  info(logger, 'RUNNING ANALYSIS FOR WHOLE POPULATION')
  source(here::here("2_Analysis","Analysis.R"))
  info(logger, 'ANALYSIS RAN FOR WHOLE POPULATION')
  print(paste0("1 of 5: FINISHED ANALYSIS FOR WHOLE POPULATION")) 
  
  #sex analysis
  print(paste0("2 of 5: RUNNING ANALYSIS FOR SEX")) 
  info(logger, 'RUNNING ANALYSIS FOR SEX')
  source(here::here("2_Analysis","AnalysisSex.R"))
  info(logger, 'ANALYSIS RAN FOR SEX')
  print(paste0("2 of 5: ANALYSIS RAN FOR SEX")) 
  
  #age analysis
  print(paste0("3 of 5: RUNNING ANALYSIS FOR AGE")) 
  info(logger, 'RUNNING ANALYSIS FOR AGE')
  source(here::here("2_Analysis","AnalysisAge.R"))
  info(logger, 'ANALYSIS RAN FOR AGE')
  print(paste0("3 of 5: ANALYSIS RAN FOR AGE")) 
  
  # age*sex analysis KM only
  print(paste0("4 of 5: RUNNING ANALYSIS FOR AGE*SEX ONLY KM")) 
  info(logger, 'RUNNING ANALYSIS FOR AGE*SEX ONLY KM')
  source(here::here("2_Analysis","AnalysisAgeSex.R"))
  info(logger, 'ANALYSIS RAN FOR AGE*SEX ONLY KM')
  print(paste0("4 of 5: ANALYSIS RAN FOR AGE*SEX ONLY KM")) 
  
  #running tableone characterisation
  print(paste0("5 of 5: RUNNING TABLE ONE CHARACTERISATION")) 
  info(logger, 'RUNNING TABLE ONE CHARACTERISATION')
  source(here::here("2_Analysis","Tableone.R"))
  info(logger, 'TABLE ONE CHARACTERISATION RAN')
  print(paste0("5 of 5: TABLE ONE CHARACTERISATION RAN"))   
  
}


info(logger, 'SAVING RESULTS')
print(paste0("SAVING RESULTS")) 
##################################################################
# Tidy up results and save ----

if(PerformTruncatedAnalysis == TRUE){
  
if(db.name != "ECI"){ 
# survival KM and extrapolated data -----
survivalResults <- dplyr::bind_rows(
  observedkmcombined ,  
  observedkmcombined_sex , 
  observedkmcombined_age , 
  observedkmcombined_age_sex,
  extrapolatedfinal,
  extrapolatedfinalsex,
  extrapolatedfinalsexS,
  extrapolatedfinalage,
  extrapolatedfinalageS,
  extrapolatedfinalt,
  extrapolatedfinalsext,
  extrapolatedfinalsexSt,
  extrapolatedfinalaget,
  extrapolatedfinalageSt) %>%
  dplyr::mutate(Database = db.name) %>% 
  dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) %>% 
  dplyr::select(!c(n.risk, n.event, n.censor, std.error)) 

#risk table ----
riskTableResults <- dplyr::bind_rows(
  risktableskm , 
  risktableskm_sex , 
  risktableskm_age ,
  risktableskm_age_sex
  ) %>%
  dplyr::mutate(Database = db.name) %>% 
  dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male"))

# KM median results, survival probabilities and predicted from extrapolations ----
medianResults <- dplyr::bind_rows( 
  medkmcombined ,
  medkmcombined_sex , 
  medkmcombined_age ,
  medkmcombined_age_sex,
  predmedmeanfinal,
  predmedmeanfinalsex,
  predmedmeanfinalsexS,
  predmedmeanfinalage,
  predmedmeanfinalageS,
  predmedmeanfinalt,
  predmedmeanfinalsext,
  predmedmeanfinalsexSt,
  predmedmeanfinalaget,
  predmedmeanfinalageSt) %>%
  dplyr::mutate(Database = db.name) %>% 
  dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) 

# hazard over time results -----
hazOverTimeResults <- dplyr::bind_rows( 
  hotkmcombined , 
  hotkmcombined_sex, 
  hotkmcombined_age, 
  hotkmcombined_age_sex,
  hazardotfinal, 
  hazardotfinalsex, 
  hazardotfinalsexS,
  hazardotfinalage,
  hazardotfinalageS,
  hazardotfinalt, 
  hazardotfinalsext, 
  hazardotfinalsexSt,
  hazardotfinalaget,
  hazardotfinalageSt) %>%
  dplyr::mutate(Database = db.name) %>% 
  dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex,  "Male"))


# GOF results for extrapolated results (adjusted and stratified)
GOFResults <- dplyr::bind_rows( 
  goffinal,
  goffinalsex, 
  goffinalsexS,
  goffinalage,
  goffinalageS,
  goffinalt,
  goffinalsext, 
  goffinalsexSt,
  goffinalaget,
  goffinalageSt
) %>%
  dplyr::mutate(Database = db.name) %>% 
  dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) %>% 
  dplyr::select(!c(N, events, censored)) 

# parameters of the extrapolated models
ExtrpolationParameters <- dplyr::bind_rows(
  parametersfinal ,
  parametersfinalsex,
  parametersfinalsexS,
  parametersfinalage,
  parametersfinalageS,
  parametersfinalt ,
  parametersfinalsext,
  parametersfinalsexSt,
  parametersfinalaget,
  parametersfinalageSt
) %>%
  dplyr::mutate(Database = db.name) %>%
  dplyr::relocate(Cancer, Method, Stratification, Adjustment, Sex, Age, Database) %>% 
  dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male"))


} else {
  
  # survival KM and extrapolated data -----
  survivalResults <- dplyr::bind_rows(
    observedkmcombined ,  
    observedkmcombined_age , 
    extrapolatedfinal,
    extrapolatedfinalage,
    extrapolatedfinalageS,
    extrapolatedfinalt,
    extrapolatedfinalaget,
    extrapolatedfinalageSt) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) %>% 
    dplyr::select(!c(n.risk, n.event, n.censor, std.error)) 
  
  #risk table ----
  riskTableResults <- dplyr::bind_rows(
    risktableskm , 
    risktableskm_age 
  ) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male"))
  
  # KM median results, survival probabilities and predicted from extrapolations ----
  medianResults <- dplyr::bind_rows( 
    medkmcombined ,
    medkmcombined_age ,
    predmedmeanfinal,
    predmedmeanfinalage,
    predmedmeanfinalageS,
    predmedmeanfinalt,
    predmedmeanfinalaget,
    predmedmeanfinalageSt) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) 
  
  # hazard over time results -----
  hazOverTimeResults <- dplyr::bind_rows( 
    hotkmcombined , 
    hotkmcombined_age, 
    hazardotfinal, 
    hazardotfinalage,
    hazardotfinalageS,
    hazardotfinalt, 
    hazardotfinalaget,
    hazardotfinalageSt) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex,  "Male"))
  
  
  # GOF results for extrapolated results (adjusted and stratified)
  GOFResults <- dplyr::bind_rows( 
    goffinal,
    goffinalage,
    goffinalageS,
    goffinalt,
    goffinalaget,
    goffinalageSt
  ) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) %>% 
    dplyr::select(!c(N, events, censored)) 
  
  # parameters of the extrapolated models
  ExtrpolationParameters <- dplyr::bind_rows(
    parametersfinal ,
    parametersfinalage,
    parametersfinalageS,
    parametersfinalt ,
    parametersfinalaget,
    parametersfinalageSt
  ) %>%
    dplyr::mutate(Database = db.name) %>%
    dplyr::relocate(Cancer, Method, Stratification, Adjustment, Sex, Age, Database) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male"))
  
  
}

} else {
  
  if(db.name != "ECI"){ 
  survivalResults <- dplyr::bind_rows(
    observedkmcombined ,  
    observedkmcombined_sex , 
    observedkmcombined_age , 
    observedkmcombined_age_sex,
    extrapolatedfinal,
    extrapolatedfinalsex,
    extrapolatedfinalsexS,
    extrapolatedfinalage,
    extrapolatedfinalageS) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) %>% 
    dplyr::select(!c(n.risk, n.event, n.censor, std.error)) %>% 
    dplyr::filter(time != 0)
  
  #risk table ----
  riskTableResults <- dplyr::bind_rows(
    risktableskm , 
    risktableskm_sex , 
    risktableskm_age ,
    risktableskm_age_sex
  ) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male"))
  
  # KM median results, survival probabilites and predicted from extrapolations ----
  medianResults <- dplyr::bind_rows( 
    medkmcombined ,
    medkmcombined_sex , 
    medkmcombined_age ,
    medkmcombined_age_sex,
    predmedmeanfinal,
    predmedmeanfinalsex,
    predmedmeanfinalsexS,
    predmedmeanfinalage,
    predmedmeanfinalageS) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) 
  
  # hazard over time results -----
  hazOverTimeResults <- dplyr::bind_rows( 
    hotkmcombined , 
    hotkmcombined_sex, 
    hotkmcombined_age, 
    hotkmcombined_age_sex,
    hazardotfinal, 
    hazardotfinalsex, 
    hazardotfinalsexS,
    hazardotfinalage,
    hazardotfinalageS) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex,  "Male"))
  
  
  # GOF results for extrapolated results (adjusted and stratified)
  GOFResults <- dplyr::bind_rows( 
    goffinal,
    goffinalsex, 
    goffinalsexS,
    goffinalage,
    goffinalageS
  ) %>%
    dplyr::mutate(Database = db.name) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) %>% 
    dplyr::select(!c(N, events, censored)) 
  
  # parameters of the extrapolated models
  ExtrpolationParameters <- dplyr::bind_rows(
    parametersfinal ,
    parametersfinalsex,
    parametersfinalsexS,
    parametersfinalage,
    parametersfinalageS
  ) %>%
    dplyr::mutate(Database = db.name) %>%
    dplyr::relocate(Cancer, Method, Stratification, Adjustment, Sex, Age, Database) %>% 
    dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male"))  

  } else {
    
    survivalResults <- dplyr::bind_rows(
      observedkmcombined ,  
      observedkmcombined_age , 
      extrapolatedfinal,
      extrapolatedfinalage,
      extrapolatedfinalageS) %>%
      dplyr::mutate(Database = db.name) %>% 
      dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) %>% 
      dplyr::select(!c(n.risk, n.event, n.censor, std.error))
    
    #risk table ----
    riskTableResults <- dplyr::bind_rows(
      risktableskm , 
      risktableskm_age 
    ) %>%
      dplyr::mutate(Database = db.name) %>% 
      dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male"))
    
    # KM median results, survival probabilites and predicted from extrapolations ----
    medianResults <- dplyr::bind_rows( 
      medkmcombined ,
      medkmcombined_age ,
      predmedmeanfinal,
      predmedmeanfinalage,
      predmedmeanfinalageS) %>%
      dplyr::mutate(Database = db.name) %>% 
      dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) 
    
    # hazard over time results -----
    hazOverTimeResults <- dplyr::bind_rows( 
      hotkmcombined , 
      hotkmcombined_age, 
      hazardotfinal, 
      hazardotfinalage,
      hazardotfinalageS) %>%
      dplyr::mutate(Database = db.name) %>% 
      dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex,  "Male"))
    
    
    # GOF results for extrapolated results (adjusted and stratified)
    GOFResults <- dplyr::bind_rows( 
      goffinal,
      goffinalage,
      goffinalageS
    ) %>%
      dplyr::mutate(Database = db.name) %>% 
      dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male")) %>% 
      dplyr::select(!c(N, events, censored)) 
    
    # parameters of the extrapolated models
    ExtrpolationParameters <- dplyr::bind_rows(
      parametersfinal ,
      parametersfinalage,
      parametersfinalageS
    ) %>%
      dplyr::mutate(Database = db.name) %>%
      dplyr::relocate(Cancer, Method, Stratification, Adjustment, Sex, Age, Database) %>% 
      dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)), Sex, "Male"))  
    
    
  }
  
    
}


# add a render file for the shiny app for filtering ----
CancerStudied <- c("Breast" , "Colorectal"  , 
                   "Head_and_neck"  , "Liver" ,
                   "Lung", "Pancreatic"  ,
                   "Prostate", "Stomach" )
Method <- c("Kaplan-Meier", extrapolations_formatted)
SexStudied <- (rep(rep(c("Male", "Female"), each = length(Method)), length(CancerStudied)))
AgeStudied <- (rep(rep(c("80 +" , "18 to 39", "40 to 49", "50 to 59", "60 to 69", "70 to 79"), each = length(Method)), length(CancerStudied)))


# what has been run
runs <- survivalResults %>% 
  dplyr::select(c("Cancer",
            "Method" ,
            "Stratification",
            "Adjustment",
            "Sex",
            "Age" )) %>% 
  dplyr::distinct() %>% 
  dplyr::mutate(Run = "Yes") %>% 
  tidyr::unite(ID, c( Cancer, Method, Age, Sex, Adjustment, Stratification ), remove = FALSE) %>% 
  dplyr::select(c(ID, Run))

# ALL
AnalysisRunAll <- tibble(
  Cancer = rep(CancerStudied, each = length(Method)),
  Method = rep(Method, length(CancerStudied)),
  Age = rep("All", by = (length(CancerStudied)*length(Method))),
  Sex = rep("Both", by = (length(CancerStudied)*length(Method))),
  Adjustment = rep("None", by = (length(CancerStudied)*length(Method))),
  Stratification = rep("None", by = (length(CancerStudied)*length(Method))) ) %>% 
  dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)),Sex, "Male"))

# SEX STRATIFICATION
AnalysisRunSexS <- tibble(
  Cancer = rep(CancerStudied, each = (length(Method)*2)),
  Method = rep(Method, (length(CancerStudied)*2)),
  Age = rep("All", by = ((length(CancerStudied))*(length(Method))*2)),
  Sex = SexStudied,
  Adjustment = rep("None", by = ((length(CancerStudied))*(length(Method))*2)),
  Stratification = rep("Sex", by = ((length(CancerStudied))*(length(Method))*2))) %>% 
  dplyr::filter(Cancer != "Prostate")

# SEX ADJUSTED
AnalysisRunSexA <- tibble(
  Cancer = rep(CancerStudied, each = (length(Method)*2)),
  Method = rep(Method, (length(CancerStudied)*2)),
  Age = rep("All", by = ((length(CancerStudied))*(length(Method))*2)),
  Sex = SexStudied,
  Stratification = rep("None", by = ((length(CancerStudied))*(length(Method))*2)),
  Adjustment = rep("Sex", by = ((length(CancerStudied))*(length(Method))*2))) %>% 
  dplyr::filter(Cancer != "Prostate")

# AGE STRATIFICATION
AnalysisRunAgeS <- tibble(
  Cancer = rep(CancerStudied, each = (length(Method)*6)),
  Method = rep(Method, (length(CancerStudied)*6)),
  Sex = rep("Both", by = ((length(CancerStudied))*(length(Method))*6)),
  Age = AgeStudied,
  Adjustment = rep("None", by = ((length(CancerStudied))*(length(Method))*6)),
  Stratification = rep("Age", by = ((length(CancerStudied))*(length(Method))*6))) %>% 
  dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)),Sex, "Male"))

# AGE ADJUSTED
AnalysisRunAgeA <- tibble(
  Cancer = rep(CancerStudied, each = (length(Method)*6)),
  Method = rep(Method, (length(CancerStudied)*6)),
  Sex = rep("Both", by = ((length(CancerStudied))*(length(Method))*8)),
  Age = AgeStudied,
  Stratification = rep("None", by = ((length(CancerStudied))*(length(Method))*6)),
  Adjustment = rep("Age", by = ((length(CancerStudied))*(length(Method))*6))) %>% 
  dplyr::mutate(Sex = if_else(!(grepl("Prostate", Cancer, fixed = TRUE)),Sex, "Male"))

# combine results
AnalysisRunSummary <- dplyr::bind_rows(AnalysisRunAll,
                                AnalysisRunSexS ,
                                AnalysisRunSexA,
                                AnalysisRunAgeS,
                                AnalysisRunAgeA ) %>% 
  tidyr::unite(ID, c( Cancer, Method, Age, Sex, Adjustment, Stratification ), remove = FALSE)


# combine with what has been run to get a rendered file of results summary
AnalysisRunSummary <- 
  dplyr::left_join(AnalysisRunSummary , runs, by = "ID") %>% 
  dplyr::select(!c(ID)) %>% 
  dplyr::mutate(Database = cdm_name(cdm),
         Run = ifelse(is.na(Run), "No", Run))

# save results as csv for data partner can review
print(paste0("SAVING RESULTS"))
info(logger, "SAVING RESULTS")
readr::write_csv(survivalResults, paste0(here::here(output.folder),"/", cdm_name(cdm), "_survival_estimates.csv"))
readr::write_csv(riskTableResults, paste0(here::here(output.folder),"/", cdm_name(cdm), "_risk_table.csv"))
readr::write_csv(medianResults, paste0(here::here(output.folder),"/", cdm_name(cdm), "_median_mean_survprob_survival.csv"))
readr::write_csv(hazOverTimeResults, paste0(here::here(output.folder),"/", cdm_name(cdm), "_hazard_overtime.csv"))
readr::write_csv(GOFResults, paste0(here::here(output.folder),"/", cdm_name(cdm), "_goodness_of_fit.csv"))
readr::write_csv(ExtrpolationParameters, paste0(here::here(output.folder),"/", cdm_name(cdm), "_extrapolation_parameters.csv"))
readr::write_csv(AnalysisRunSummary, paste0(here::here(output.folder),"/", cdm_name(cdm), "_analyses_run_summary.csv"))
readr::write_csv(tableone_final, paste0(here::here(output.folder),"/", cdm_name(cdm), "_tableone_summary.csv"))
readr::write_csv(snapshotcdm, paste0(here::here(output.folder),"/", cdm_name(cdm), "_cdm_snapshot.csv"))
readr::write_csv(attritioncdm, paste0(here::here(output.folder),"/", cdm_name(cdm), "_cohort_attrition.csv"))


# # Time taken
x <- abs(as.numeric(Sys.time()-start, units="secs"))

info(logger, paste0("Study took: ",
                    sprintf("%02d:%02d:%02d:%02d",
                            x %/% 86400,  x %% 86400 %/% 3600, x %% 3600 %/%
                              60,  x %% 60 %/% 1)))

print(paste0("SAVED RESULTS")) 
info(logger, "SAVED RESULTS")
# zip results
print("Zipping results to output folder")

zip::zip(
zipfile = here::here(output.folder, paste0("Results_", cdmName(cdm), ".zip")),
files = list.files(output.folder),
root = output.folder)

print("Study done!")
print(paste0("Study took: ",
                         sprintf("%02d:%02d:%02d:%02d",
                                 x %/% 86400,  x %% 86400 %/% 3600, x %% 3600 %/%
                                   60,  x %% 60 %/% 1)))
print("-- If all has worked, there should now be a zip folder with your results in the Results folder to share")
print("-- Thank you for running the study! :)")

Sys.time()-start

readLines(log_file)