# Manage project dependencies ------
# the following will prompt you to install the various packages used in the study 
# install.packages("renv")

# EF. HUS dependent installs:
# .libPaths() should contain as first:
# "C:/Users/HUS72904793/Documents/GitHub/EHDEN/THISSTUDY/renv/library/R-4.2/x86_64-w64-mingw32"
# remotes::install_local("c:/Users/HUS72904793/Documents/GitHub/SqlRender", force = TRUE)

renv::activate()
renv::restore()

# Load packages ------
library(CirceR)
library(here)
library(DBI)
library(dbplyr)
library(dplyr)
library(readr)
library(log4r)
library(tidyr)
library(stringr)
library(CDMConnector)
library(ggplot2)
library(broom)
library(survival)
library(bshazard)
library(flexsurv)
library(tictoc)
library(tibble)
library(RPostgres)
library(purrr)
library(PatientProfiles)
library(CodelistGenerator)
library(SqlRender)
library(DrugUtilisation)

# Set the short name/acronym for your database (to be used in the titles of reports, etc) -----
# Please do not use omop, cdm for db.name
db.name <-"HUS"

# Set output folder locations -----
# the path to a folder where the results from this analysis will be saved
output.folder <- here::here("Results", db.name)

# database connection details
source("C:/Users/HUS72904793/Documents/GitHub/EHDEN/.0_setUserDetails.R")
connectionString <- Sys.getenv("HUSOMOPCONSTR")
server     <- Sys.getenv("HUSSERVER")
database   <- Sys.getenv("HUSDB")
server_dbi <- "..."
user       <- Sys.getenv("HUSOMOPUSER")
password   <- Sys.getenv("HUSOMOPPWD")
port       <- "..." 
host       <- "..." 

# Specify cdm_reference via DBI connection details -----
# In this study we also use the DBI package to connect to the database
# set up the dbConnect details below (see https://dbi.r-dbi.org/articles/dbi for more details)
# you may need to install another package for this (although RPostgres is included with renv in case you are using postgres)

# OPTION 1: odbc

library("odbc")
#db <- DBI::dbConnect(odbc::odbc(),
#                dbname = server_dbi,
#                port = port,
#                host = host, 
#                user = user, 
#                password = password)
db <- dbConnect(odbc::odbc(),
                Driver = "{ODBC DRIVER 18 for SQL Server}",
                Server = server,  
                Database = database,
                UID = user, 
                PWD = password,
                dbname = "HUS"
                #dbms.name = "synapse"
                #TrustServerCertificate="yes",
                #Encrypt="True",
                #Port = 1433
)
#odbc lead to error message, see github
#Thus, lets try DatabaseConnector, from Pasi's post https://teams.microsoft.com/l/message/19:34d73d6b-4a4f-4ba3-a3bf-dbcc461af9d2_36d30150-5097-40f8-b279-317b1e37467a@unq.gbl.spaces/1701152773741?context=%7B%22contextType%22%3A%22chat%22%7D

# OPTION 2: 

# Connection worked after installing 
# renv:install("DatabaseConnector")
# renv:install("Andromeda")
# Warning message:
#   Not all functionality is supported when DatabaseConnector as your database driver! Some issues may occur.

jarpath <- "C:/Users/HUS72904793/Documents/jars" 
Sys.setenv("DATABASECONNECTOR_JAR_FOLDER" = jarpath)
source("../.0_setUserDetails.R")
library("DatabaseConnector")
connectionDetails <- DatabaseConnector::createConnectionDetails(dbms = "synapse",
                                             user = Sys.getenv("HUSOMOPUSER"),
                                             password = Sys.getenv("HUSOMOPPWD"),
                                             connectionString = Sys.getenv("HUSOMOPCONSTR"),
)
db = DatabaseConnector::connect(connectionDetails)



# Set database details -----
# The name of the schema that contains the OMOP CDM with patient-level data
cdm_database_schema <- "omop54"

# The name of the schema that contains the vocabularies 
# (often this will be the same as cdm_database_schema)
vocabulary_database_schema <- "omop54"

# The name of the schema where results tables will be created 
results_database_schema <- "ohdsieric"

# stem table description use something short and informative such as ehdenwp2 or your initials
# Note, if there is an existing table in your results schema with the same names it will be overwritten 
# needs to be in lower case and NOT more than 10 characters
table_stem <- "ehdenwp2_dc"

# create cdm reference ---- DO NOT REMOVE "PREFIX" ARGUMENT IN THIS CODE
cdm <- CDMConnector::cdm_from_con(con = db, 
                                  cdm_schema = cdm_database_schema,
                                  write_schema = c("schema" = results_database_schema, 
                                                   "prefix" = table_stem),
                                  cdm_name = db.name)

# to check whether the DBI connection is correct, 
# running the next line should give you a count of your person table

cdm <- CDMConnector::cdm_from_con(con = db, 
                                  cdm_schema = cdm_database_schema,
                                  write_schema = c("schema" = results_database_schema, 
                                                   "prefix" = table_stem),
                                  cdm_name = db.name)

# to check whether the DBI connection is correct, 
# running the next line should give you a count of your person table
cdm$person %>% dplyr::tally()
# This one only workes if usgin OPTION2 DatabaseConnector:
cdm$person %>% dplyr::tally() %>% 
  CDMConnector::computeQuery()

# Set study details -----
# if you do not have suitable data from 2000-01-01 
# please put year of useable data starting from 1st jan 
# must be in format YYYY-MM-DD ie. 20XX-01-01
startdate <- "2000-01-01" 

# Prior history -----
# if you have a database where the observation period start date for each patient is the date of cancer diagnosis (ie. some cancer registries)
# set this value to FALSE. If your database has linkage or data where you can look in prior history before cancer diagnosis (e.g. primary care)
# set as TRUE.
priorhistory <- TRUE

# Truncated time analysis ------
# By setting this to TRUE this will perform an additional analysis where extrapolation methods will extrapolate on the observed data truncated at 2 years NOT on the full observed data. 
# If FALSE this additional analysis will not be run.
PerformTruncatedAnalysis <- TRUE

#Set output folder again (just because!)
output.folder <- "results"

# Run the study ------
source(here::here("RunStudy.R"))
# after the study is run you should have a zip folder in your output folder to share

# drop the permanent tables from the study 
# YOU MUST HAVE TABLE STEM SET ABOVE WITH A NAME ABOVE OTHERWISE IT WILL DELETE EVERYTHING!
#CDMConnector::dropTable(cdm, dplyr::everything())

# Disconnect from database
#dbDisconnect(db)
