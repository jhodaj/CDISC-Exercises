/**************************************************************************
Program:     derive_adsl_from_sdtm.sas
Purpose:     Derive ADSL_DER from SDTM domains (CDISCPILOT01 style)
Author:      Jezerca Hodaj 
Environment: SAS OnDemand for Academics
Assumptions:
  - All SDTM XPTs have already been imported into library SRC:
      DM, EX, DS, SV, QS, VS, MH, SC (plus others, not all used here)
  - ADSL_DER will live in SRC.ADSL_DER
**************************************************************************/


/* DURDIS derivation note:
   Duration of disease (DURDIS) is calculated as the number of months
   between DISONSDT and VISIT1DT using INTCK('MONTH', ... , 'CONTINUOUS')
   and rounding to 1 decimal place. This mirrors the CDISCPILOT01 ADSL.
   Any potential ±0.1 month differences arise from month-length and
   rounding conventions.
*/


/*===============================================================
  STEP 1: Define library locations
================================================================*/
libname src      "/home/u61146376/CDISC/DATASETS";   /* Working library */

/* Official ADaM XPT (for comparison) */
libname adae_xpt xport "/home/u61146376/CDISC/DATASETS/adae.xpt";
libname adsl_xpt xport "/home/u61146376/CDISC/DATASETS/adsl.xpt";

/* SDTM XPT (for derivation) */
libname dm_xpt   xport "/home/u61146376/CDISC/DATASETS/dm.xpt";
libname ex_xpt   xport "/home/u61146376/CDISC/DATASETS/ex.xpt";
libname ae_xpt   xport "/home/u61146376/CDISC/DATASETS/ae.xpt";
libname ds_xpt   xport "/home/u61146376/CDISC/DATASETS/ds.xpt";
libname cm_xpt   xport "/home/u61146376/CDISC/DATASETS/cm.xpt";
libname lb_xpt   xport "/home/u61146376/CDISC/DATASETS/lb.xpt";
libname mh_xpt   xport "/home/u61146376/CDISC/DATASETS/mh.xpt";
libname qs_xpt   xport "/home/u61146376/CDISC/DATASETS/qs.xpt";
libname relr_xpt xport "/home/u61146376/CDISC/DATASETS/relrec.xpt";
libname sc_xpt   xport "/home/u61146376/CDISC/DATASETS/sc.xpt";
libname se_xpt   xport "/home/u61146376/CDISC/DATASETS/se.xpt";
libname supa_xpt xport "/home/u61146376/CDISC/DATASETS/suppae.xpt";
libname supd_xpt xport "/home/u61146376/CDISC/DATASETS/suppdm.xpt";
libname sups_xpt xport "/home/u61146376/CDISC/DATASETS/suppds.xpt";
libname supl_xpt xport "/home/u61146376/CDISC/DATASETS/supplb.xpt";
libname sv_xpt   xport "/home/u61146376/CDISC/DATASETS/sv.xpt";
libname ta_xpt   xport "/home/u61146376/CDISC/DATASETS/ta.xpt";
libname te_xpt   xport "/home/u61146376/CDISC/DATASETS/te.xpt";
libname ti_xpt   xport "/home/u61146376/CDISC/DATASETS/ti.xpt";
libname ts_xpt   xport "/home/u61146376/CDISC/DATASETS/ts.xpt";
libname tv_xpt   xport "/home/u61146376/CDISC/DATASETS/tv.xpt";
libname vs_xpt   xport "/home/u61146376/CDISC/DATASETS/vs.xpt";

/*===============================================================
  STEP 2: Import ADaM (ADSL/ADAE) and SDTM (DM/EX/AE/DS)
================================================================*/

/* Official ADaM datasets */
proc copy in=adsl_xpt out=src; run;    /* src.adsl  */
proc copy in=adae_xpt out=src; run;    /* src.adae  */

/* SDTM domains for derivation */
proc copy in=dm_xpt   out=src; run;    /* src.dm    */
proc copy in=ex_xpt   out=src; run;    /* src.ex    */
proc copy in=ae_xpt   out=src; run;    /* src.ae    */
proc copy in=ds_xpt   out=src; run;    /* src.ds    */
proc copy in=cm_xpt   out=src; run;    /* src.cm    */
proc copy in=lb_xpt   out=src; run;    /* src.lb    */
proc copy in=mh_xpt   out=src; run;    /* src.mh    */
proc copy in=qs_xpt   out=src; run;    /* src.qs    */
proc copy in=relr_xpt out=src; run;    /* src.relrec*/
proc copy in=sc_xpt   out=src; run;    /* src.sc    */
proc copy in=se_xpt   out=src; run;    /* src.se    */
proc copy in=supa_xpt out=src; run;    /* src.suppae*/
proc copy in=supd_xpt out=src; run;    /* src.suppdm*/
proc copy in=sups_xpt out=src; run;    /* src.suppds*/
proc copy in=supl_xpt out=src; run;    /* src.supplb*/
proc copy in=sv_xpt   out=src; run;    /* src.sv    */
proc copy in=ta_xpt   out=src; run;    /* src.ta    */
proc copy in=te_xpt   out=src; run;    /* src.te    */
proc copy in=ti_xpt   out=src; run;    /* src.ti    */
proc copy in=ts_xpt   out=src; run;    /* src.ts    */
proc copy in=tv_xpt   out=src; run;    /* src.tv    */
proc copy in=vs_xpt   out=src; run;    /* src.vs    */

/*===============================================================
  0. Helper macro: convert ISO8601 (possibly with time) to SAS date
     (simple version – assumes at least YYYY-MM-DD)
================================================================*/
%macro iso_to_date(invar, outvar);
  length &outvar 8;
  if not missing(&invar) then do;
    length __c $10;
    __c = substr(&invar,1,10);         /* take YYYY-MM-DD part */
    if length(__c) = 10 then &outvar = input(__c, yymmdd10.);
    else &outvar = .;
  end;
  format &outvar date9.;
%mend;

/*===============================================================
  1. DM core: randomized subjects only (exclude Screen Failures)
================================================================*/
data dm_core;
  set src.dm;

  /* Exclude screen failures */
  if upcase(arm) = "SCREEN FAILURE" then delete;

  keep studyid usubjid subjid siteid arm armcd age ageu sex race ethnic
       rfstdtc rfendtc dthfl;
run;

/*===============================================================
  2. SITEGR1 & basic treatment variables at subject level
================================================================*/
data adsl_demog;
  set dm_core;
  length sitegr1 $3 trt01p trt01a $20;
  length trt01pn trt01an 8;

  /* Pooled Site Group 1 – emulate CDISC pooling */
  if siteid in ("702","706","707","711","714","715","717") then
    sitegr1 = "900";
  else
    sitegr1 = siteid;

  trt01p  = arm;
  trt01a  = arm;  /* no difference between planned and actual */

  /* ARMN mapping (from pilot / define / ADSL examples) */
  select (strip(arm));
    when ("Placebo")                trt01pn = 0;
    when ("Xanomeline Low Dose")   trt01pn = 54;
    when ("Xanomeline High Dose")  trt01pn = 81;
    otherwise                       trt01pn = .;
  end;
  trt01an = trt01pn;   /* same numeric code for actual */

  label
    sitegr1  = "Pooled Site Group 1"
    arm      = "Description of Planned Arm"
    trt01p   = "Planned Treatment for Period 01"
    trt01pn  = "Planned Treatment for Period 01 (N)"
    trt01a   = "Actual Treatment for Period 01"
    trt01an  = "Actual Treatment for Period 01 (N)";
run;

/*===============================================================
  3. TRTSDT (SV VISITNUM=3) and TRTEDT (define-compliant)
     TRTDUR = TRTEDT - TRTSDT + 1
================================================================*/

/* 3.1 Get TRTSDT from SV (Visit 3 – first exposure) */
data sv_trt;
  set src.sv;
  where visitnum = 3;
  %iso_to_date(svstdtc, svstdt);
run;

proc sql;
  create table sv_trtsdt as
  select studyid, usubjid,
         min(svstdt) as trtsdt format=date9.
  from sv_trt
  group by studyid, usubjid;
quit;

/* 3.2 Get EX start/end dates and TRTEDT from last EX record */
data ex_dates;
  set src.ex;
  %iso_to_date(exstdtc, exstdt);
  %iso_to_date(exendtc, exendt);
run;

proc sql;
  create table ex_trtedt as
  select studyid, usubjid,
         max(exendt) as trtedt_ex format=date9.
  from ex_dates
  group by studyid, usubjid;
quit;

/* 3.3 Get discontinuation date from DS for TRTEDT fallback        */
/*     (DISPOSITION EVENT records only)                            */
/*data ds_trt_disp;
  set src.ds;
  if upcase(dscat) = "DISPOSITION EVENT";
  %iso_to_date(dsstdtc, dsstdt);
run;

proc sql;
  create table ds_trt_last as
  select studyid,
         usubjid,
         max(dsstdt)   as ds_discdt     format=date9.,
         max(dsdecod)  as dcdecod       length=40,
         max(visitnum) as ds_visnum_max
  from ds_trt_disp
  group by studyid, usubjid;
quit;*/

/* 3.4 RFENDT (study end date) – still used later, but not for TRTEDT */
data dm_end;
  set dm_core;
  %iso_to_date(rfendtc, rfendt);
run;

/* 3.5 Combine TRTSDT & TRTEDT (match CDISCPILOT01 ADSL)           */
/*     - TRTEDT = last EX.EXENDTC if available                     */
/*     - Otherwise TRTEDT = RFENDT (DM.RFENDTC)                    */
proc sql;
  create table adsl_trt as
  select a.studyid,
         a.usubjid,
         b.trtsdt,
         coalesce(c.trtedt_ex, e.rfendt) as trtedt format=date9.
  from dm_core      as a
  left join sv_trtsdt   as b
    on a.studyid = b.studyid and a.usubjid = b.usubjid
  left join ex_trtedt   as c
    on a.studyid = c.studyid and a.usubjid = c.usubjid
  left join dm_end      as e
    on a.studyid = e.studyid and a.usubjid = e.usubjid;
quit;

/* 3.6 Derive TRTDUR */
data adsl_trt;
  set adsl_trt;
  length trtdur 8;
  if n(trtsdt, trtedt) then trtdur = trtedt - trtsdt + 1;
  label
    trtsdt  = "Date of First Exposure to Treatment"
    trtedt  = "Date of Last Exposure to Treatment"
    trtdur  = "Duration of Treatment (days)";
run;

/*===============================================================
  4. CUMDOSE & AVGDD (as in define)
================================================================*/

/* 4.1 Merge in treatment info (ARMN) to adsl_trt */
proc sql;
  create table adsl_trt2 as
  select t.*, d.trt01pn, d.trt01an, d.arm
  from adsl_trt t
  left join adsl_demog d
    on t.studyid=d.studyid and t.usubjid=d.usubjid;
quit;

/* 4.2 Dosing intervals (Visit 4, 12 from SV) */
data sv_vis;
  set src.sv;
  %iso_to_date(svstdtc, svdt);
run;

proc sql;
  create table sv_v4_v12 as
  select studyid, usubjid,
         max(case when visitnum=4  then svdt end) as visit4dt  format=date9.,
         max(case when visitnum=12 then svdt end) as visit12dt format=date9.
  from sv_vis
  group by studyid, usubjid;
quit;

proc sql;
  create table adsl_dose_pre as
  select a.*, b.visit4dt, b.visit12dt
  from adsl_trt2 a
  left join sv_v4_v12 b
    on a.studyid=b.studyid and a.usubjid=b.usubjid;
quit;

data adsl_dose;
  set adsl_dose_pre;
  length cumdose avgdd 8;

  /* ARMN = 0 or 1: CUMDOSE = TRT01PN * TRTDUR */
  /* Placebo (0 mg) and Low Dose (54 mg): CUMDOSE = dose * TRTDUR */
if trt01pn in (0,54) then do;
  if n(trt01pn, trtdur) then cumdose = trt01pn * trtdur;
end;


  /* ARMN = 2 (81mg): 54–81–54 mg intervals */
  if trt01pn = 81 and n(trtsdt, trtedt) then do;
    length d1 d2 d3 8;
    d1 = .; d2 = .; d3 = .;

    /* Interval 1: TRTSDT → VISIT4DT (or TRTEDT if discontinued earlier) */
    if not missing(visit4dt) then
      d1 = max(0, min(visit4dt, trtedt) - trtsdt + 1);
    else
      d1 = 0;

    /* Interval 2: VISIT4DT → VISIT12DT (or TRTEDT if discontinued earlier) */
    if n(visit4dt, visit12dt) then
      d2 = max(0, min(visit12dt, trtedt) - max(visit4dt, trtsdt) + 0);
    else d2 = 0;

    /* Interval 3: VISIT12DT → TRTEDT */
    if not missing(visit12dt) then
      d3 = max(0, trtedt - max(visit12dt, trtsdt) + 0);
    else d3 = 0;

    cumdose = 54*d1 + 81*d2 + 54*d3;
  end;

  /* AVGDD = CUMDOSE / TRTDUR, rounded to 1 decimal as in CDISCPILOT01 */
if n(cumdose, trtdur) and trtdur>0 then
  avgdd = round(cumdose / trtdur, 0.1);


  label
    cumdose = "Cumulative Dose (as planned)"
    avgdd   = "Avg Daily Dose (as planned)";
run;

/*===============================================================
  5. Age, age groups, race coding
================================================================*/
data adsl_age;
  length agegr1 $5 agegr1n 8 racen 8;
  set adsl_demog;

  /* Age groups per define: 1=<65, 2=65-80, 3>80 */
  if age < 65 then do;
    agegr1  = "<65";
    agegr1n = 1;
  end;
  else if 65 <= age <= 80 then do;
    agegr1  = "65-80";
    agegr1n = 2;
  end;
  else if age > 80 then do;
    agegr1  = ">80";
    agegr1n = 3;
  end;

  /* RACEN based on RACE */
  select (upcase(race));
    when ("WHITE")                     racen = 1;
    when ("BLACK OR AFRICAN AMERICAN") racen = 2;
    when ("ASIAN")                     racen = 3;
    when ("AMERICAN INDIAN OR ALASKA NATIVE") racen = 6;
    when ("NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER") racen = 5;
    otherwise racen = .;
  end;

  label
    age     = "Age"
    agegr1  = "Pooled Age Group 1"
    agegr1n = "Pooled Age Group 1 (N)"
    ageu    = "Age Units"
    race    = "Race"
    racen   = "Race (N)";
run;

/*===============================================================
  6. Safety / ITT / Efficacy / Completer flags
================================================================*/

/* 6.1 ITT and safety base */
data adsl_flags_base;
  merge adsl_demog(in=a)
        adsl_trt(in=b)
        dm_end(in=c drop=ageu race ethnic);
  by studyid usubjid;
  if a;

  length ittfl saffl $1;
  length efffl comp8fl comp16fl comp24fl $1;
  length disconfl dsraefl dthfl_c $1;

  /* ITTFL: Y if ARMCD not blank */
  if not missing(armcd) then ittfl="Y";
  else ittfl="N";

  /* SAFFL: Y if ITTFL=Y and TRTSDT not missing */
  if ittfl="Y" and not missing(trtsdt) then saffl="Y";
  else saffl="N";

  dthfl_c = dthfl;

  label
    ittfl   = "Intent-To-Treat Population Flag"
    saffl   = "Safety Population Flag"
    dthfl_c = "Subject Died?";
run;

/* 6.2 EFFFL using QS (ACTOT & CIBIC with VISITNUM>3) */
data qs_eff;
  set src.qs;
  where qstestcd in ("ACTOT","CIBIC") and visitnum>3;
run;

proc sql;
  create table qs_eff_flags as
  select studyid, usubjid,
         (max(case when qstestcd="ACTOT" then 1 else 0 end) > 0) as has_actot,
         (max(case when qstestcd="CIBIC" then 1 else 0 end) > 0) as has_cibic
  from qs_eff
  group by studyid, usubjid;
quit;

data adsl_flags_eff;
  merge adsl_flags_base(in=a)
        qs_eff_flags(in=b);
  by studyid usubjid;
  if a;

  if saffl="Y" and has_actot=1 and has_cibic=1 then efffl="Y";
  else efffl="N";

  label efffl = "Efficacy Population Flag";
run;

/* 6.3 Comp flags using SV visit dates & RFENDT (ENDDT) */
data sv_comp;
  set src.sv;
  %iso_to_date(svstdtc, svdt);
run;

proc sql;
  create table sv_comp_dates as
  select studyid, usubjid,
         max(case when visitnum=8  then svdt end) as vis8dt  format=date9.,
         max(case when visitnum=10 then svdt end) as vis10dt format=date9.,
         max(case when visitnum=12 then svdt end) as vis12dt format=date9.
  from sv_comp
  group by studyid, usubjid;
quit;

proc sql;
  create table adsl_flags as
  select a.*, b.vis8dt, b.vis10dt, b.vis12dt
  from adsl_flags_eff a
  left join sv_comp_dates b
    on a.studyid=b.studyid and a.usubjid=b.usubjid;
quit;

data adsl_flags;
  set adsl_flags;
  length comp8fl comp16fl comp24fl $1;

  /* ENDDT in define corresponds to RFENDT */
  if not missing(vis8dt)  and rfendt >= vis8dt  then comp8fl  = "Y"; else comp8fl  = "N";
  if not missing(vis10dt) and rfendt >= vis10dt then comp16fl = "Y"; else comp16fl = "N";
  if not missing(vis12dt) and rfendt >= vis12dt then comp24fl = "Y"; else comp24fl = "N";

  label
    comp8fl  = "Completers of Week 8 Population Flag"
    comp16fl = "Completers of Week 16 Population Flag"
    comp24fl = "Completers of Week 24 Population Flag";
run;

/*===============================================================
  7. BMI / Height / Weight / Education / Disease duration
================================================================*/

/* 7.1 Baseline Height (Visit 1) and Weight (Visit 3) from VS */
data vs_base;
  set src.vs;
  %iso_to_date(vsdtc, vsdt);
run;

proc sql;
  create table vs_htwt as
  select studyid, usubjid,
         max(case when upcase(vstestcd)="HEIGHT" and visitnum=1 then vsstresn end) as heightbl,
         max(case when upcase(vstestcd)="WEIGHT" and visitnum=3 then vsstresn end) as weightbl
  from vs_base
  group by studyid, usubjid;
quit;

/* 7.2 Education from SC (Years of Education) */
data sc_years;
  set src.sc;

  if upcase(sctestcd) in ("YEARSEDU","EDUCYRS","EDLEVEL");

  length educlvl 8;

  if not missing(scstresn) then educlvl = scstresn;
  else if not missing(scorres) then educlvl = input(scorres, best12.);

  keep studyid usubjid educlvl;
run;

/* 7.3 Disease onset from MH (PRIMARY DIAGNOSIS) */
data mh_dis;
  set src.mh;
  if upcase(mhcat) = "PRIMARY DIAGNOSIS";
  %iso_to_date(mhstdtc, disonsdt);
  keep studyid usubjid disonsdt;
run;

/* 7.4 Visit 1 date from SV */
data sv_v1;
  set src.sv;
  if visitnum = 1;
  %iso_to_date(svstdtc, visit1dt);
  keep studyid usubjid visit1dt;
run;

/* 7.5 Build subject-level bio base */
proc sql;
  create table adsl_bio_base as
  select a.studyid,
         a.usubjid,
         v.heightbl,
         v.weightbl,
         s.educlvl,
         m.disonsdt,
         sv.visit1dt
  from dm_core as a
  left join vs_htwt  as v
    on a.studyid = v.studyid and a.usubjid = v.usubjid
  left join sc_years as s
    on a.studyid = s.studyid and a.usubjid = s.usubjid
  left join mh_dis   as m
    on a.studyid = m.studyid and a.usubjid = m.usubjid
  left join sv_v1    as sv
    on a.studyid = sv.studyid and a.usubjid = sv.usubjid;
quit;

/* 7.6 Derive BMI, duration of disease, and groups */
data adsl_bio;
  set adsl_bio_base;

  length bmibl 8 bmiblgr1 $6 durdis 8 durdsgr1 $4;

  if n(heightbl, weightbl) then do;
    heightbl = round(heightbl, 0.1);
    weightbl = round(weightbl, 0.1);

    bmibl = weightbl / ((heightbl / 100)**2);
    bmibl = round(bmibl, 0.1);
  end;
  else bmibl = .;

  if 0 < bmibl < 25 then bmiblgr1 = "<25";
  else if 25 <= bmibl < 30 then bmiblgr1 = "25-<30";
  else if bmibl >= 30 then bmiblgr1 = ">=30";
  else bmiblgr1 = "";

/* --- Disease duration path ----------------------------------------- */
if n(visit1dt, disonsdt) then do;
    /* CDISCPILOT01 ADSL uses: months = days * 12 / 365, rounded to 1 decimal */
    durdis = round( (visit1dt - disonsdt) * 12 / 365 , 0.1);
end;
else durdis = .;

/* Grouping based on fractional months */
if . < durdis < 12 then durdsgr1 = "<12";
else if durdis >= 12 then durdsgr1 = ">=12";
else durdsgr1 = "";


  label
    heightbl  = "Baseline Height (cm)"
    weightbl  = "Baseline Weight (kg)"
    bmibl     = "Baseline BMI (kg/m^2)"
    bmiblgr1  = "Pooled Baseline BMI Group 1"
    educlvl   = "Years of Education"
    disonsdt  = "Date of Onset of Disease"
    durdis    = "Duration of Disease (Months)"
    durdsgr1  = "Pooled Disease Duration Group 1"
    visit1dt  = "Date of Visit 1";
run;

/*===============================================================
  8. RFSTDTC / RFENDTC, VISNUMEN, RFENDT, DCDECOD, DCREASCD, MMSETOT
================================================================*/

/* 8.1 VISNUMEN using DS (Disposition Event) */
data ds_disp;
  set src.ds;
  if upcase(dscat) = "DISPOSITION EVENT";
  %iso_to_date(dsstdtc, dsstdt);
run;

proc sql;
  create table ds_vis as
  select studyid, usubjid,
         max(case
               when not missing(visitnum) then
                 (case when visitnum = 13 then 12 else visitnum end)
               else .
             end) as visnumen
  from ds_disp
  group by studyid, usubjid;
quit;

/* 8.2 DCDECOD & DCREASCD from DS (DISPOSITION EVENT) */
proc sql;
  create table ds_reason as
  select studyid, usubjid,
         max(dsstdt) as ds_lastdt format=date9.,
         max(dsdecod) as dcdecod length=40
  from ds_disp
  group by studyid, usubjid;
quit;

data ds_reason2;
  set ds_reason;
  length dcreascd $40;

  select (upcase(strip(dcdecod)));
    when ("COMPLETED")                        dcreascd = "Completed";
    when ("ADVERSE EVENT")                    dcreascd = "Adverse Event";
    when ("STUDY TERMINATED BY SPONSOR")      dcreascd = "Sponsor Decision";
    when ("LACK OF EFFICACY")                 dcreascd = "Lack of Efficacy";
    when ("WITHDRAWAL BY SUBJECT")            dcreascd = "Withdrew Consent";
    when ("DEATH")                            dcreascd = "Death";
    when ("LOST TO FOLLOW-UP")                dcreascd = "Lost to Follow-up";
    when ("PHYSICIAN DECISION")               dcreascd = "Physician Decision";
    when ("I/E NOT MET")                      dcreascd = "I/E Not Met";
    when ("PROTOCOL VIOLATION")               dcreascd = "Protocol Violation";
    otherwise                                 dcreascd = dcdecod;
  end;

  label
    dcdecod  = "Standardized Disposition Term"
    dcreascd = "Reason for Discontinuation";
run;

/* 8.3 MMSETOT: sum of MMSE scores */
data qs_mmse;
  set src.qs;

  if index(upcase(qscat), "MINI-MENTAL") > 0;

  mmse_val = qsstresn;
run;

proc sql;
  create table qs_mmse_sum as
  select studyid, usubjid,
         sum(mmse_val) as mmsetot
  from qs_mmse
  group by studyid, usubjid;
quit;

/*===============================================================
  9. FINAL MERGE: Build ADSL_DER with all 48 variables in order
================================================================*/
proc sql;
  create table adsl_der_pre as
  select a.studyid,
         a.usubjid,
         a.subjid,
         a.siteid,
         d.sitegr1,
         a.arm,
         d.trt01p,
         d.trt01pn,
         d.trt01a,
         d.trt01an,
         t.trtsdt,
         t.trtedt,
         t.trtdur,
         dose.avgdd,
         dose.cumdose,
         a.age,
         ag.agegr1,
         ag.agegr1n,
         a.ageu,
         ag.race,
         ag.racen,
         a.sex,
         a.ethnic,
         f.saffl,
         f.ittfl,
         f.efffl,
         f.comp8fl,
         f.comp16fl,
         f.comp24fl,
         /* DISCONFL, DSRAEFL, DTHFL */
         (case when dr.dcreascd ne "Completed" and dr.dcreascd ne "" then "Y"
               else "" end) as disconfl length=1,
         (case when dr.dcreascd = "Adverse Event" then "Y"
               else "" end) as dsraefl length=1,
         f.dthfl_c as dthfl length=1,
         bio.bmibl,
         bio.bmiblgr1,
         bio.heightbl,
         bio.weightbl,
         bio.educlvl,
         bio.disonsdt,
         bio.durdis,
         bio.durdsgr1,
         bio.visit1dt,
         a.rfstdtc,
         a.rfendtc,
         dv.visnumen,
         dm_end.rfendt,
         dr.dcdecod,
         dr.dcreascd,
         mm.mmsetot
  from dm_core     as a
  left join adsl_demog as d
    on a.studyid=d.studyid and a.usubjid=d.usubjid
  left join adsl_trt      as t
    on a.studyid=t.studyid and a.usubjid=t.usubjid
  left join adsl_dose     as dose
    on a.studyid=dose.studyid and a.usubjid=dose.usubjid
  left join adsl_age      as ag
    on a.studyid=ag.studyid and a.usubjid=ag.usubjid
  left join adsl_flags    as f
    on a.studyid=f.studyid and a.usubjid=f.usubjid
  left join adsl_bio      as bio
    on a.studyid=bio.studyid and a.usubjid=bio.usubjid
  left join ds_vis        as dv
    on a.studyid=dv.studyid and a.usubjid=dv.usubjid
  left join ds_reason2    as dr
    on a.studyid=dr.studyid and a.usubjid=dr.usubjid
  left join dm_end
    on a.studyid=dm_end.studyid and a.usubjid=dm_end.usubjid
  left join qs_mmse_sum   as mm
    on a.studyid=mm.studyid and a.usubjid=mm.usubjid
  order by a.studyid, a.usubjid;
quit;

/* 9.1 Ensure variable order matches CDISCPILOT01 ADSL exactly */
data src.adsl_der;
  length ageu $5 race $32 ethnic $22 rfstdtc rfendtc $20 dcdecod $27 dcreascd $18;

  retain
    STUDYID USUBJID SUBJID SITEID SITEGR1 ARM
    TRT01P TRT01PN TRT01A TRT01AN
    TRTSDT TRTEDT TRTDUR AVGDD CUMDOSE
    AGE AGEGR1 AGEGR1N AGEU RACE RACEN SEX ETHNIC
    SAFFL ITTFL EFFFL COMP8FL COMP16FL COMP24FL
    DISCONFL DSRAEFL DTHFL
    BMIBL BMIBLGR1 HEIGHTBL WEIGHTBL EDUCLVL
    DISONSDT DURDIS DURDSGR1 VISIT1DT
    RFSTDTC RFENDTC VISNUMEN RFENDT
    DCDECOD DCREASCD MMSETOT;
  set adsl_der_pre;

  label
    rfendt   = "Date of Discontinuation/Completion"
    disconfl = "Did the Subject Discontinue the Study?"
    dsraefl  = "Discontinued due to AE?"
    visnumen = "End of Trt Visit (Vis 12 or Early Term.)"
    mmsetot  = "MMSE Total";
run;

/*===============================================================
  10. Optional: Compare with original ADaM ADSL
================================================================*/
proc compare base=src.adsl compare=src.adsl_der
             criterion=1e-8 method=relative;
  id usubjid;
run;


/* If we use a more relaxed criterion on the variable durdis, 
it eliminates the forty  +/- 0.1 differences */
/*proc compare base=src.adsl compare=src.adsl_der
             method=absolute criterion=0.11;
  id usubjid;
  var durdis;
run;*/

