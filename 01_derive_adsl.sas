/**************************************************************************
Purpose:     Derive ADTTE (Time-to-First Dermatologic Event) from ADAE & ADSL
Author:      Jezerca Hodaj
Environment: SAS OnDemand for Academics
**************************************************************************/

/*===============================================================
  STEP 1: Define library locations
================================================================*/
libname src      "/home/u61146376/CDISC/DATASETS";   /* Working library */
libname adae_xpt xport "/home/u61146376/CDISC/DATASETS/adae.xpt";
libname adsl_xpt xport "/home/u61146376/CDISC/DATASETS/adsl.xpt";
libname adtexpt  xport "/home/u61146376/CDISC/DATASETS/adtte.xpt";

/*===============================================================
  STEP 2: Import ADAE, ADSL, and official ADTTE
================================================================*/
proc copy in=adae_xpt out=src; run;
proc copy in=adsl_xpt out=src; run;
proc copy in=adtexpt out=src; run;

libname adae_xpt clear;
libname adsl_xpt clear;
libname adtexpt clear;

/*===============================================================
  STEP 3: Inspect imported datasets
================================================================*/
title "Structure of ADSL Dataset";   proc contents data=src.adsl varnum; run;
title "Structure of ADAE Dataset";   proc contents data=src.adae varnum; run;
title "Structure of Official ADTTE Dataset (CDISC)";
proc contents data=src.adtte varnum; run; title;


/*===============================================================
  STEP 4: Merge ADAE and ADSL by USUBJID (core vars)
===============================================================*/
proc sql;
  create table adae1 as
  select  a.usubjid,
          a.aeseq,
          a.trtemfl,
          a.aedecod,
          a.aebodsys,
          a.astdt,
          a.aendt,
          b.studyid,
          b.siteid,
          b.age,
          b.agegr1,
          b.agegr1n,
          b.race,
          b.racen,
          b.sex,
          b.saffl,
          b.trtsdt,
          b.trtedt,
          b.trt01p,
          b.trt01a,
          b.trt01an,
          b.rfstdtc,
          b.rfendtc
  from src.adae as a
  left join src.adsl as b
    on a.usubjid = b.usubjid;
quit;


/*===============================================================
  STEP 5: Flag dermatologic events (AE-based, TE only)
  NOTE: Do NOT filter by ASTDT > TRTSDT here. That comparison
        will be done later using ONLY the first AE per subject.
================================================================*/
data adae_derm;
  set adae1;  /* this already has ADAE + ADSL merged by USUBJID */

  /* Treatment-emergent only */
  if trtemfl = "Y";

  /* Dermatologic definition  */
  if 
        index(upcase(aebodsys),"DERMAT") > 0 or
        index(upcase(aebodsys),"SKIN") > 0 or
        index(upcase(aedecod),"APPLICATION SITE") > 0 or
        index(upcase(aedecod),"ERYTHEMA") > 0 or
        index(upcase(aedecod),"PRURITUS") > 0 or
        index(upcase(aedecod),"RASH") > 0 or
        index(upcase(aedecod),"URTICARIA") > 0 or
        index(upcase(aedecod),"DERMATITIS") > 0 or
        index(upcase(aedecod),"BLISTER") > 0 or
        index(upcase(aedecod),"ALOPECIA") > 0 or
        index(upcase(aedecod),"HYPERHIDROSIS") > 0 or
        index(upcase(aedecod),"SKIN IRRITATION") > 0 or
        index(upcase(aedecod),"SKIN EXFOLIATION") > 0 or
        index(upcase(aedecod),"SKIN ULCER") > 0 or
        index(upcase(aedecod),"ACTINIC KERATOSIS") > 0 or
        index(upcase(aedecod),"DRUG ERUPTION") > 0
    ;
run;
/*===============================================================
  STEP 6: Take FIRST dermatologic AE per subject
  Now we’ll have exactly one ADAE row per USUBJID.
================================================================*/
proc sort data=adae_derm;
  by usubjid astdt aeseq;
run;

data first_derm;
  set adae_derm;
  by usubjid;
  if first.usubjid;   /* this is “first dermatologic event” per subject */
run;

/*===============================================================
  STEP 7: Derive ADTTE records from FIRST derm AE per subject
  Define logic (per define.xml):
    if ADAE.ASTDT not missing and ADAE.ASTDT > TRTSDT
        ADT  = ADAE.ASTDT
        CNSR = 0
    else
        ADT  = RFENDT (from ADSL.RFENDTC)
        CNSR = 1
================================================================*/
data adtte_events;
  merge first_derm(in=a)
        src.adsl(keep=usubjid studyid siteid age agegr1 agegr1n
                       race racen sex saffl
                       trtsdt trtedt
                       trt01p trt01a trt01an
                       rfstdtc rfendtc);
  by usubjid;
  if a;   /* only subjects with at least one derm AE */

  length rfstdt rfendt astdt_num startdt adt trtdur aval 8;
  format rfstdt rfendt startdt adt trtsdt trtedt date9.;

  /* Convert ISO dates */
  if not missing(rfstdtc) then rfstdt = input(substr(rfstdtc,1,10), yymmdd10.);
  if not missing(rfendtc) then rfendt = input(substr(rfendtc,1,10), yymmdd10.);

  /* ASTDT may be char */
  if vtype(astdt) = 'C' then astdt_num = input(substr(astdt,1,10), yymmdd10.);
  else astdt_num = astdt;

  /* Origin */
  startdt = rfstdt;
  trtdur  = trtedt - trtsdt + 1;

  /* Define logic applied to FIRST DERM AE: */
  if not missing(astdt_num) and astdt_num >= trtsdt then do;
    adt      = astdt_num;
    cnsr     = 0;
    evntdesc = "Dematologic Event Occured";  
    srcdom   = "ADAE";
    srcvar   = "ASTDT";
    srcseq   = aeseq;
  end;
  else do;
    adt      = rfendt;
    cnsr     = 1;
    evntdesc = "Study Completion Date";
    srcdom   = "ADSL";
    srcvar   = "RFENDT";
    srcseq   = .;
  end;

  /* AVAL = ADT – STARTDT + 1 */
  if not missing(adt) and not missing(startdt) then
    aval = adt - startdt + 1;
  else aval = .;

  /* Treatment + PARAM */
  trtp    = trt01p;
  trta    = trt01a;
  trtan   = trt01an;
  paramcd = "TTDE";
  param   = "Time to First Dermatologic Event";
run;
/*===============================================================
  STEP 8: Additional censored records for subjects with NO derm AE
  These are ADSL subjects whose USUBJID never appears in ADAE_DERM.
================================================================*/
proc sql;
  create table censored as
  select a.usubjid,
         a.studyid,
         a.siteid,
         a.age,
         a.agegr1,
         a.agegr1n,
         a.race,
         a.racen,
         a.sex,
         a.saffl,
         a.trtsdt,
         a.trtedt,
         a.trt01p,
         a.trt01a,
         a.trt01an,
         a.rfstdtc,
         a.rfendtc
  from src.adsl as a
  where a.usubjid not in (select distinct usubjid from adae_derm);
quit;

data censored2;
  set censored;

  length rfstdt rfendt startdt adt trtdur aval 8;
  format rfstdt rfendt startdt adt trtsdt trtedt date9.;

  /* Convert ISO character dates */
  if not missing(rfstdtc) then rfstdt = input(substr(rfstdtc,1,10), yymmdd10.);
  if not missing(rfendtc) then rfendt = input(substr(rfendtc,1,10), yymmdd10.);

  /* STARTDT / ADT per define.xml for censored-only subjects */
  startdt = rfstdt;
  adt     = rfendt;

  trtdur = trtedt - trtsdt + 1;
  aval   = adt - startdt + 1;

  cnsr    = 1;
  paramcd = "TTDE";
  param   = "Time to First Dermatologic Event";

  evntdesc = "Study Completion Date";
  srcdom   = "ADSL";
  srcvar   = "RFENDT";
  srcseq   = .;

  trtp  = trt01p;
  trta  = trt01a;
  trtan = trt01an;

  label
    startdt  = "Time to Event Origin Date for Subject"
    adt      = "Analysis Date"
    aval     = "Analysis Value"
    trtdur   = "Duration of treatment (days)"
    cnsr     = "Censor"
    evntdesc = "Event or Censoring Description"
    srcdom   = "Source Domain"
    srcvar   = "Source Variable"
    srcseq   = "Source Sequence Number";
run;

/*===============================================================
  STEP 9: Combine ADTTE records (events + censored)
================================================================*/
proc sort data=adtte_events; by usubjid; run;
proc sort data=censored2;    by usubjid; run;

data src.adtte_derived;
  length evntdesc $25 srcdom $4 srcvar $6 param $100 paramcd $8;
  merge adtte_events(in=evt)
        censored2(in=cens);
  by usubjid;

  /* If an event/censor from step 7 exists, keep that; 
     else keep censored-only subject from step 8 */
  if evt then output;
  else if cens then output;

  label trtdur = "Duration of Treatment (Days)";
run;

/*===============================================================
  STEP 10: Create ADTTE_ALIGNED_FINAL in CDISC order (26 vars)
===============================================================*/
data src.adtte_aligned_final;
  length studyid $12 siteid $3 usubjid $11
         agegr1 $5 race $32 sex $1
         trtp $20 trta $20
         param $100 paramcd $8
         evntdesc $25 srcdom $4 srcvar $6 saffl $1;
  set src.adtte_derived
      (keep=studyid siteid usubjid
            age agegr1 agegr1n
            race racen sex
            trtsdt trtedt trtdur
            trtp trta trtan
            param paramcd
            aval startdt adt cnsr
            evntdesc srcdom srcvar srcseq saffl);
  retain studyid siteid usubjid
         age agegr1 agegr1n
         race racen sex
         trtsdt trtedt trtdur
         trtp trta trtan
         param paramcd
         aval startdt adt cnsr
         evntdesc srcdom srcvar srcseq saffl;

  label
    studyid = "Study Identifier"
    siteid  = "Study Site Identifier"
    usubjid = "Unique Subject Identifier"
    age     = "Age"
    agegr1  = "Pooled Age Group 1"
    agegr1n = "Pooled Age Group 1 (N)"
    race    = "Race"
    racen   = "Race (N)"
    sex     = "Sex"
    trtsdt  = "Date of First Exposure to Treatment"
    trtedt  = "Date of Last Exposure to Treatment"
    trtdur  = "Duration of Treatment (Days)"
    trtp    = "Planned Treatment"
    trta    = "Actual Treatment"
    trtan   = "Actual Treatment (N)"
    param   = "Parameter Description"
    paramcd = "Parameter Code"
    aval    = "Analysis Value"
    startdt = "Time to Event Origin Date for Subject"
    adt     = "Analysis Date"
    cnsr    = "Censor"
    evntdesc = "Event or Censoring Description"
    srcdom   = "Source Domain"
    srcvar   = "Source Variable"
    srcseq   = "Source Sequence Number"
    saffl    = "Safety Population Flag";
run;

/*===============================================================
  STEP 11: QC and final PROC COMPARE
===============================================================*/

proc freq data=src.adtte_aligned_final;
  tables cnsr / nocum;
  title "Censor Flag Distribution (0=Event, 1=Censored) in Derived ADTTE";
run;

proc freq data=src.adtte;
  tables cnsr / nocum;
  title "Censor Flag Distribution (0=Event, 1=Censored) in ADTTE (CDISC)";
run;


proc freq data=src.adtte_aligned_final;
  tables evntdesc / nocum;
  title "Event or Censoring Description Distribution in Derived ADTTE";
run;

proc freq data=src.adtte;
  tables evntdesc / nocum;
  title "Event or Censoring Description Distribution in ADTTE (CDISC)";
run;


proc freq data=src.adtte_aligned_final;
  tables srcdom / nocum;
  title "Source Domain Distribution in Derived ADTTE";
run;

proc freq data=src.adtte;
  tables srcdom / nocum;
  title "Source Domain Distribution in ADTTE (CDISC)";
run;


proc freq data=src.adtte_aligned_final;
  tables srcvar / nocum;
  title "Source Variable Distribution in Derived ADTTE";
run;

proc freq data=src.adtte;
  tables srcvar / nocum;
  title "Source Varable Distribution in ADTTE (CDISC)";
run;


proc freq data=src.adtte_aligned_final;
  tables srcseq / nocum;
  title "Source Sequence Number Distribution in Derived ADTTE";
run;

proc freq data=src.adtte;
  tables srcseq / nocum;
  title "Source Sequence Number Distribution in ADTTE (CDISC)";
run;


proc sort data=src.adtte;               by studyid usubjid paramcd; run;
proc sort data=src.adtte_aligned_final; by studyid usubjid paramcd; run;

proc compare base=src.adtte
             compare=src.adtte_aligned_final
             criterion=1E-8
             listall
             out=src.compare_final
             outbase outcomp outdiff;
  id studyid usubjid paramcd;
  title "Final Validation: Derived ADTTE vs Official ADTTE";
run;
title;
