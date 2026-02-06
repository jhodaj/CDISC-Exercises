/**************************************************************************
Program:     derive_adae_from_sdtm_adsl.sas
Purpose:     Derive ADAE_DER from SDTM.AE + ADSL_DER (CDISCPILOT01 style)
Author:      Jezerca Hodaj
Environment: SAS OnDemand for Academics
Assumptions:
  - All SDTM XPTs have already been imported OR are available as XPTs.
  - ADSL_DER has already been created by derive_adsl_from_sdtm.sas and
    saved as SRC.ADSL_DER.
  - Official ADaM ADAE (for comparison) is available as SRC.ADAE.
**************************************************************************/


/* QC Note (ADAE vs CDISCPILOT01 ADAE)
   - Dataset: 1191 records, 55 variables
   - Result: 1186 records with all variables equal
             5 records with differences only in TRTEDT
   - Explanation:
       TRTEDT in ADAE_DER is taken directly from ADSL_DER.
       For subjects 01-705-1031 and 01-705-1303, ADSL_DER uses
       EX/DS-derived last-dose dates that differ from the
       CDISCPILOT01 ADSL TRTEDT values. All other variables
       (including ASTDT, ASTDTF, ASTDY, ADURN, TRTEMFL, AOCC*,
       CQ01NAM, AOCC01FL) match exactly.
*/


/*===============================================================
  STEP 0: Libraries
================================================================*/
libname src      "/home/u61146376/CDISC/DATASETS";

/* Official ADAE XPT (for comparison) – optional */
libname adae_xpt xport "/home/u61146376/CDISC/DATASETS/adae.xpt";

/* SDTM AE XPT (if needed) */
libname ae_xpt   xport "/home/u61146376/CDISC/DATASETS/ae.xpt";

/* If SDTM + ADAE are not yet in SRC, copy them */
proc copy in=adae_xpt out=src; run;   /* src.adae   */
proc copy in=ae_xpt   out=src; run;   /* src.ae     */

/*===============================================================
  STEP 1: Helper macro to convert ISO8601 dates
================================================================*/
%macro iso_to_date(invar, outvar);
  length &outvar 8;
  if not missing(&invar) then do;
    if length(&invar) >= 10 then
      &outvar = input(substr(&invar,1,10), yymmdd10.);
    else if length(&invar) = 7 then
      &outvar = input(cats(&invar,'-01'), yymmdd10.);
    else if length(&invar) = 4 then
      &outvar = input(cats(&invar,'-01-01'), yymmdd10.);
    else &outvar = .;
  end;
  else &outvar = .;
%mend iso_to_date;

/*===============================================================
  STEP 2: Bring in needed vars from ADSL_DER for ADAE
================================================================*/
data adsl_for_adae;
  set src.adsl_der;

  /* numeric RFSTDT from RFSTDTC if needed */
  length rfstdt 8;
  if missing(rfstdt) and not missing(rfstdtc) then do;
    %iso_to_date(rfstdtc, rfstdt);
  end;
  format rfstdt trtsdt trtedt date9.;

  length trta $200;
  trta  = trt01a;
  trtan = trt01an;

  keep studyid usubjid
       siteid
       age agegr1 agegr1n
       race racen sex
       saffl
       trtsdt trtedt rfstdt
       trta trtan;
run;

proc sort data=adsl_for_adae; by studyid usubjid; run;

/*===============================================================
  STEP 3: AE core from SDTM + core ADAE derivations
================================================================*/
proc sort data=src.ae out=ae_sdtm;
  by studyid usubjid aeseq;
run;

data ae_core;
  set ae_sdtm;
  by studyid usubjid aeseq;

  length astdt aendt 8 astdtf $1;

  /* ASTDT + ASTDTF per final logic */
  if not missing(aestdtc) and lengthn(aestdtc) >= 10 then do;
      astdt  = input(substr(aestdtc, 1, 10), yymmdd10.);
      astdtf = "";
  end;
  else if not missing(aestdtc) then do;
      %iso_to_date(aestdtc, astdt);
      astdtf = "D";   /* imputed */
  end;
  else do;
      astdt  = .;
      astdtf = "";
  end;

  if not missing(aeendtc) then do;
      %iso_to_date(aeendtc, aendt);
  end;
  else aendt = .;

  format astdt aendt date9.;

  keep studyid usubjid aeseq domain
       aespid aeterm aellt aelltcd aedecod aeptcd
       aehlgt aehlgtcd aehlt aehltcd aebodsys aebdsycd aesoc aesoccd
       aesev aeser aeacn aerel aeout aescAN aescong aesod
       aeshosp aeslife aesdisab aesdth
       astdt astdtf aendt aestdtc aeendtc aestdy aeendy;
run;

/* Merge AE + ADSL info */
data adae_der_pre;
  merge ae_core       (in=a)
        adsl_for_adae (in=b);
  by studyid usubjid;
  if a;

  /* ASTDY/AENDY per RFSTDT */
  length astdy aendy 8;
  if not missing(astdt) and not missing(rfstdt) then do;
    if astdt >= rfstdt then astdy = astdt - rfstdt + 1;
    else                    astdy = astdt - rfstdt;
  end;
  else astdy = .;

  if not missing(aendt) and not missing(rfstdt) then do;
    if aendt >= rfstdt then aendy = aendt - rfstdt + 1;
    else                    aendy = aendt - rfstdt;
  end;
  else aendy = .;

  /* ADURN/ADURU – only when ASTDT not imputed */
  length adurn 8 aduru $10;
  if not missing(aendt) and not missing(astdt) and astdtf = "" then do;
      adurn = aendt - astdt + 1;
      aduru = "DAY";
  end;
  else do;
      adurn = .;
      aduru = "";
  end;

  /* TRTEMFL per define: ASTDT >= TRTSDT > . */
  length trtemfl $1;
  if not missing(astdt)
     and not missing(trtsdt)
     and astdt >= trtsdt
  then trtemfl = "Y";
  else trtemfl = "N";

  /* Analysis seq = AESEQ */
  length aseq 8;
  aseq = aeseq;
run;

/*===============================================================
  STEP 4: AOCC flags + CQ01NAM/AOCC01FL (as we finalized)
================================================================*/
/* 4.1 AOCCFL: 1st occurrence of any TE AE */
proc sort data=adae_der_pre(where=(trtemfl = "Y"))
          out=adae_te_any;
  by studyid usubjid astdt aeseq;
run;

data occ_any;
  set adae_te_any;
  by studyid usubjid astdt aeseq;
  length aoccfl $1;
  if first.usubjid then aoccfl = "Y";
  else aoccfl = "";
  keep studyid usubjid aeseq aoccfl;
run;

/* 4.2 AOCCSFL: 1st occurrence of SOC (AEBODSYS) per subject */
proc sort data=adae_der_pre(where=(trtemfl = "Y"))
          out=adae_te_soc;
  by studyid usubjid aebodsys astdt aeseq;
run;

data occ_soc;
  set adae_te_soc;
  by studyid usubjid aebodsys astdt aeseq;
  length aoccsfl $1;
  if first.aebodsys then aoccsfl = "Y";
  else aoccsfl = "";
  keep studyid usubjid aeseq aoccsfl;
run;

/* 4.3 AOCCPFL: 1st occurrence of PT within SOC per subject */
proc sort data=adae_der_pre(where=(trtemfl = "Y"))
          out=adae_te_pt;
  by studyid usubjid aebodsys aedecod astdt aeseq;
run;

data occ_pt;
  set adae_te_pt;
  by studyid usubjid aebodsys aedecod astdt aeseq;
  length aoccpfl $1;
  if first.aedecod then aoccpfl = "Y";
  else aoccpfl = "";
  keep studyid usubjid aeseq aoccpfl;
run;

/* 4.4 AOCC02FL: 1st serious TE AE per subject */
proc sort data=adae_der_pre(where=(trtemfl = "Y" and aeser = "Y"))
          out=adae_te_ser_any;
  by studyid usubjid astdt aeseq;
run;

data occ_ser_any;
  set adae_te_ser_any;
  by studyid usubjid astdt aeseq;
  length aocc02fl $1;
  if first.usubjid then aocc02fl = "Y";
  else aocc02fl = "";
  keep studyid usubjid aeseq aocc02fl;
run;

/* 4.5 AOCC03FL: 1st serious TE AE per SOC per subject */
proc sort data=adae_der_pre(where=(trtemfl = "Y" and aeser = "Y"))
          out=adae_te_ser_soc;
  by studyid usubjid aebodsys astdt aeseq;
run;

data occ_ser_soc;
  set adae_te_ser_soc;
  by studyid usubjid aebodsys astdt aeseq;
  length aocc03fl $1;
  if first.aebodsys then aocc03fl = "Y";
  else aocc03fl = "";
  keep studyid usubjid aeseq aocc03fl;
run;

/* 4.6 AOCC04FL: 1st serious TE AE per PT within SOC per subject */
proc sort data=adae_der_pre(where=(trtemfl = "Y" and aeser = "Y"))
          out=adae_te_ser_pt;
  by studyid usubjid aebodsys aedecod astdt aeseq;
run;

data occ_ser_pt;
  set adae_te_ser_pt;
  by studyid usubjid aebodsys aedecod astdt aeseq;
  length aocc04fl $1;
  if first.aedecod then aocc04fl = "Y";
  else aocc04fl = "";
  keep studyid usubjid aeseq aocc04fl;
run;

/* 4.7 CQ01NAM / AOCC01FL: dermatologic query, 1st TE derm AE per subject */

proc sort data=adae_der_pre out=adae_cq;
  by studyid usubjid astdt aeseq;
run;

data occ_cq;
  set adae_cq;
  by studyid usubjid astdt aeseq;

  length cq01nam $19 aocc01fl $1;
  length dec_upper bod_upper $200;
  dec_upper = upcase(coalescec(aedecod, ""));
  bod_upper = upcase(coalescec(aebodsys, ""));

  /* --- CQ01NAM per define --- */
  if  index(dec_upper, "APPLICATION")  > 0 or
      index(dec_upper, "DERMATITIS")  > 0 or
      index(dec_upper, "ERYTHEMA")    > 0 or
      index(dec_upper, "BLISTER")     > 0
  then cq01nam = "DERMATOLOGIC EVENTS";

  else if bod_upper = "SKIN AND SUBCUTANEOUS TISSUE DISORDERS"
       and dec_upper not in ("COLD SWEAT", "HYPERHIDROSIS", "ALOPECIA")
  then cq01nam = "DERMATOLOGIC EVENTS";

  else cq01nam = "";

  /* --- AOCC01FL: 1st TE derm event per subject --- */
  retain seen_derm;
  if first.usubjid then seen_derm = 0;

  aocc01fl = "";

  if cq01nam ne "" and trtemfl = "Y" and seen_derm = 0 then do;
    aocc01fl = "Y";
    seen_derm = 1;
  end;

  keep studyid usubjid aeseq cq01nam aocc01fl;
run;

/* Make sure all datasets are sorted by the merge keys */
proc sort data=adae_der_pre; by studyid usubjid aeseq; run;
proc sort data=occ_any;      by studyid usubjid aeseq; run;
proc sort data=occ_soc;      by studyid usubjid aeseq; run;
proc sort data=occ_pt;       by studyid usubjid aeseq; run;
proc sort data=occ_ser_any;  by studyid usubjid aeseq; run;
proc sort data=occ_ser_soc;  by studyid usubjid aeseq; run;
proc sort data=occ_ser_pt;   by studyid usubjid aeseq; run;
proc sort data=occ_cq;       by studyid usubjid aeseq; run;

/* Now do the merge */
data adae_der;
  merge adae_der_pre
        occ_any
        occ_soc
        occ_pt
        occ_ser_any
        occ_ser_soc
        occ_ser_pt
        occ_cq;
  by studyid usubjid aeseq;
run;

/*===============================================================
  STEP 5: Final ADAE_DER and ADAE_DER_55, then PROC COMPARE
================================================================*/
data src.adae_der_55;
  /* ---- Force lengths to match official ADAE ---- */
  length
    TRTA     $20
    TRTAN       8
    ASTDTF   $1
    ADURN       8
    ADURU    $3
    AETERM   $46
    AELLT    $46
    AEDECOD  $46
    AEHLT    $8
    AEHLGT   $9
    AESOC    $67
    AEACN    $1
    AEOUT    $26
    TRTEMFL  $1
    AOCCFL   $1
    AOCCSFL  $1
    AOCCPFL  $1
    AOCC02FL $1
    AOCC03FL $1
    AOCC04FL $1
    CQ01NAM  $19
    AOCC01FL $1
  ;

  set src.adae_der;

  /* ---- Labels aligned to WORK.ADAE_BASE_ALIGN ---- */
  label
    TRTA     = "Actual Treatment"
    TRTAN    = "Actual Treatment (N)"
    ASTDTF   = "Analysis Start Date Imputation Flag"
    ADURN    = "AE Duration (N)"
    ADURU    = "AE Duration Units"
    AETERM   = "Reported Term for the Adverse Event"
    AELLT    = "Lowest Level Term"
    AEDECOD  = "Dictionary-Derived Term"
    AEHLT    = "High Level Term"
    AEHLGT   = "High Level Group Term"
    AESOC    = "Primary System Organ Class"
    AEACN    = "Action Taken with Study Treatment"
    AEOUT    = "Outcome of Adverse Event"
    TRTEMFL  = "Treatment Emergent Analysis Flag"
    AOCCFL   = "1st Occurrence of Any AE Flag"
    AOCCSFL  = "1st Occurrence of SOC Flag"
    AOCCPFL  = "1st Occurrence of Preferred Term Flag"
    AOCC02FL = "1st Occurrence 02 Flag for Serious"
    AOCC03FL = "1st Occurrence 03 Flag for Serious SOC"
    AOCC04FL = "1st Occurrence 04 Flag for Serious PT"
    CQ01NAM  = "Customized Query 01 Name"
    AOCC01FL = "1st Occurrence 01 Flag for CQ01"
  ;

  /* ---- Ensure CDISC-only ADaM vars exist (safety) ---- */
  /* (They’re already covered above, but leaving this comment just for clarity) */

  /* ---- Force all 55 CDISC ADAE vars to exist & have order ---- */
  retain 
    STUDYID SITEID USUBJID TRTA TRTAN 
    AGE AGEGR1 AGEGR1N 
    RACE RACEN SEX SAFFL 
    TRTSDT TRTEDT 
    ASTDT ASTDTF ASTDY 
    AENDT AENDY ADURN ADURU 
    AETERM AELLT AELLTCD AEDECOD AEPTCD 
    AEHLT AEHLTCD AEHLGT AEHLGTCD 
    AEBODSYS AESOC AESOCCD 
    AESEV AESER 
    AESCAN AESCONG AESDISAB AESDTH 
    AESHOSP AESLIFE AESOD 
    AEREL AEACN AEOUT AESEQ 
    TRTEMFL 
    AOCCFL AOCCSFL AOCCPFL 
    AOCC02FL AOCC03FL AOCC04FL 
    CQ01NAM AOCC01FL
  ;

  /* Drop everything else so this dataset has *only* these 55 vars */
  keep 
    STUDYID SITEID USUBJID TRTA TRTAN 
    AGE AGEGR1 AGEGR1N 
    RACE RACEN SEX SAFFL 
    TRTSDT TRTEDT 
    ASTDT ASTDTF ASTDY 
    AENDT AENDY ADURN ADURU 
    AETERM AELLT AELLTCD AEDECOD AEPTCD 
    AEHLT AEHLTCD AEHLGT AEHLGTCD 
    AEBODSYS AESOC AESOCCD 
    AESEV AESER 
    AESCAN AESCONG AESDISAB AESDTH 
    AESHOSP AESLIFE AESOD 
    AEREL AEACN AEOUT AESEQ 
    TRTEMFL 
    AOCCFL AOCCSFL AOCCPFL 
    AOCC02FL AOCC03FL AOCC04FL 
    CQ01NAM AOCC01FL;
run;


/*===============================================================
  STEP 6: ALIGN & COMPARE: CDISC ADAE vs derived 55-var ADAE
================================================================*/

/* 1) Sort both ADAE sources */
proc sort data=src.adae        out=adae_base_sorted;
  by usubjid aeseq;
run;

proc sort data=src.adae_der_55 out=adae_der_sorted;
  by usubjid aeseq;
run;

/* 2) IDs present in both */
data ids_both;
  merge adae_base_sorted(in=a keep=usubjid aeseq)
        adae_der_sorted(in=b keep=usubjid aeseq);
  by usubjid aeseq;
  if a and b;
run;

/* 3) Subset each to matching IDs only */
data adae_base_align;
  merge adae_base_sorted(in=a)
        ids_both        (in=i);
  by usubjid aeseq;
  if a and i;
run;

data adae_der_align;
  merge adae_der_sorted(in=b)
        ids_both       (in=i);
  by usubjid aeseq;
  if b and i;
run;

proc compare base=src.adae compare=src.adae_der_55
             criterion=1e-8 method=relative;
  id usubjid aeseq;
run;
