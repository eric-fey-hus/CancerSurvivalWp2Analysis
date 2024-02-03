# Log file to keep track of study progress at HUS

## 2024-01-04

 4. Used local instance of SqlRender to resolve below error. 
    => same result (not resolved)

 3. Error in instantiate the cohorts with no prior history  
    ```R
    > # instantiate the cohorts with no prior history 
    > cdm <- CDMConnector::generateConceptCohortSet(
    +   cdm,
    +   conceptSet = cancer_concepts,
    +   name = "outcome",
    +   limit = "first",
    +   requiredObservation = c(0, 0),
    +   end = "observation_period_end_date",
    +   overwrite = TRUE )
      |============================================================================================================================| 100%
    Executing SQL took 1.06 secs
      |============================================================================================================================| 100%
    Executing SQL took 0.656 secs
    Error in .jcall("RJavaTools", "Ljava/lang/Object;", "invokeMethod", cl,  : 
      java.util.EmptyStackException
    In addition: Warning messages:
    1: Column 'include_descendants' is of type 'logical', but this is not supported by many DBMSs. Converting to numeric (1 = TRUE, 0 = FALSE) 
    2: Column 'is_excluded' is of type 'logical', but this is not supported by many DBMSs. Converting to numeric (1 = TRUE, 0 = FALSE) 
    3: limit is a reserved keyword in SQL and should not be used as a table or field name.
    • end is a reserved keyword in SQL and should not be used as a table or field name.  
    ```
    
 2. Ignored the below

 1. Warning in "get concept sets from cohorts" 
    ```R
    > # get concept sets from cohorts----
    > cancer_concepts <- CodelistGenerator::codesFromCohort(
    +   path = here::here("1_InstantiateCohorts", "Cohorts" ) ,
    +   cdm = cdm,
    +   withConceptDetails = FALSE)
    Created a temporary table named #dbplyr_005
    Inserting data took 0.00794 secs
      |============================================================================================================================| 100%
    Executing SQL took 1.27 secs
    Warning messages:
    1: Column 'include_descendants' is of type 'logical', but this is not supported by many DBMSs. Converting to numeric (1 = TRUE, 0 = FALSE) 
    2: Column 'is_excluded' is of type 'logical', but this is not supported by many DBMSs. Converting to numeric (1 = TRUE, 0 = FALSE) 
    ```
