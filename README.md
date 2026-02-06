## CDISC Pilot ADaM Derivations in SAS: ADSL, ADAE, ADTTE (TTDE)
This repository contains SAS programs demonstrating derivation of core ADaM datasets using the CDISC SDTM/ADaM Pilot Project data:
```
• ADSL (Subject-Level Analysis Dataset)
• ADAE (Adverse Events Analysis Dataset)
• ADTTE for Time to First Dermatologic Event (PARAMCD=TTDE)
The ADTTE program also includes validation against the official pilot ADTTE using PROC COMPARE.
Source data: CDISC SDTM/ADaM Pilot Project
https://github.com/cdisc-org/sdtm-adam-pilot-project/tree/master

## What this shows
•	Practical ADaM-style derivations in SAS
•	Linking subject-level data (ADSL) to event-level data (ADAE)
•	Building a time-to-event endpoint (TTDE) from AE + subject-level dates
•	QC/validation using PROC COMPARE
```

---

## Repository Structure
```
.
├── README.md
├── programs/
│   ├── 01_derive_adsl.sas
│   ├── 02_derive_adae.sas
│   └── 03_derive_adtte_ttde.sas
└── data/                      # optional (you can keep these local instead)
    ├── adsl.xpt
    ├── adae.xpt
    ├── adtte.xpt
    ├── .
    ├── .
    ├── .
    └── vs.xpt

```

## How to run
### Prerequisites
•	SAS (Base SAS or SAS OnDemand for Academics)
•	XPT files available locally:
   o	adsl.xpt, adae.xpt, and adtte.xpt (official reference for ADTTE QC)
### Run order
1.	Run programs/01_derive_adsl.sas
2.	Run programs/02_derive_adae.sas
3.	Run programs/03_derive_adtte_ttde.sas

#### What to review after running
•	Derived datasets in your output library (e.g., SRC.*)
•	QC tables produced by PROC COMPARE


## Program overview
```
1) ADSL derivation (01_derive_adsl.sas)
 - Derives subject-level analysis variables (one row per subject) used downstream.
 - Typical content includes demographics, key reference/treatment dates, and analysis flags.
 - Compares it to the official pilot ADSL using PROC COMPARE.
2) ADAE derivation (02_derive_adae.sas)
 - Derives analysis AE records and aligns them to ADSL by USUBJID.
 - Typical content includes AE descriptors, analysis dates/days, and treatment-emergent logic.
 - Compares it to the official pilot ADAE using PROC COMPARE.
3) ADTTE TTDE derivation (03_derive_adtte_ttde.sas)
 - Derives an ADTTE-like time-to-event dataset for:
•	PARAMCD = TTDE — Time to First Dermatologic Event and compares it to the official pilot ADTTE using PROC COMPARE.

```

## 1. Objective

The goal is to recreate the **ADTTE Time-to-First Dermatologic Event (TTDE)** dataset from:

- `ADAE` – Adverse Events
- `ADSL` – Subject-Level Analysis Dataset

and to compare the derived dataset with an **official ADTTE** (provided as an XPT file).

## 2. Derivation Logic
The derivation follows these main steps (mirroring the define.xml):

### 2.1 Libraries & Imports
1.	Assign SAS libraries (e.g. src) and XPORT locations.
2.	Use PROC COPY to import:
   -	adae.xpt → src.adae
   -	adsl.xpt → src.adsl
   -	adtte.xpt → src.adtte (official reference)
  
### 2.2 Merge ADAE + ADSL Core Variables
Create ADAE1 by left-joining ADAE to ADSL by USUBJID and keeping:
-	Subject-level variables (STUDYID, SITEID, AGE, SEX, RACE, TRTSDT, TRTEDT, RFSTDTC, RFENDTC, TRT01*, etc.)
-	AE-level variables (AEDECOD, AEBODSYS, TRTEMFL, ASTDT, AENDT, AESEQ)
  
### 2.3 Identify Dermatologic Events
From ADAE1, create ADAE_DERM:
  - Keep only treatment-emergent AEs:
TRTEMFL = "Y"

•	Flag as dermatologic if:
   o AEBODSYS contains "DERMAT" or "SKIN", or
   o AEDECOD contains terms such as:
       -    APPLICATION SITE
       -    ERYTHEMA 
       -    PRURITUS
       -    RASH
       -	URTICARIA
       -	DERMATITIS
       -	BLISTER
       -	ALOPECIA
       -	HYPERHIDROSIS
       -	SKIN IRRITATION
       -	SKIN EXFOLIATION
       -	SKIN ULCER
       -	ACTINIC KERATOSIS
       -	DRUG ERUPTION
You can think of this as the working definition of a dermatologic AE.

### 2.4 First Dermatologic AE per Subject
    1.	Sort ADAE_DERM by:
    2.	BY USUBJID ASTDT AESEQ;
    3.	Create FIRST_DERM containing only:
    4.	IF FIRST.USUBJID;
This gives one row per subject, corresponding to the first dermatologic AE chronologically.

### 2.5 Derive ADT, AVAL, CNSR (Events)
Merge FIRST_DERM with ADSL and:

• Convert RFSTDTC and RFENDTC to SAS dates (RFSTDT, RFENDT).
• Convert ASTDT to a numeric date (ASTDT_NUM) if needed.
• Set origin date:
   o STARTDT = RFSTDT
•	Set treatment duration:
   o	TRTDUR = TRTSDT – TRTEDT + 1


Then apply the event/censor rule per define-style logic:

• If ASTDT_NUM is non-missing and ASTDT_NUM ≥ TRTSDT:
   o ADT = ASTDT_NUM
   o CNSR = 0
   o EVNTDESC = "Dematologic Event Occured"
   o SRCDOM = "ADAE", SRCVAR = "ASTDT", SRCSEQ = AESEQ
• Else:
   o ADT = RFENDT
   o CNSR = 1
   o EVNTDESC = "Study Completion Date"
   o SRCDOM = "ADSL", SRCVAR = "RFENDT", SRCSEQ = .


Finally:

• AVAL = ADT – STARTDT + 1
• Set parameter metadata:
   o PARAMCD = "TTDE"
   o PARAM = "Time to First Dermatologic Event"

This dataset is called ADTTE_EVENTS.

### 2.6 Derive Censored Records (No Derm AE)
For subjects who never appear in ADAE_DERM:
•	Start from ADSL and derive:
   o	STARTDT = RFSTDT
   o	ADT = RFENDT
   o	CNSR = 1
   o	EVNTDESC = "Study Completion Date"
   o	PARAMCD = "TTDE"
   o	PARAM = "Time to First Dermatologic Event"
   o	AVAL = ADT – STARTDT + 1

This dataset is called CENSORED2.

### 2.7 Combine & Align
•	Combine ADTTE_EVENTS and CENSORED2 into:
   o	SRC.ADTTE_DERIVED
•	Reorder and relabel variables to match CDISC ADTTE structure:
   o	SRC.ADTTE_ALIGNED_FINAL
________________________________________
## 3. Validation (QC)
The derived ADTTE is compared with the official ADTTE using PROC COMPARE:
```
proc compare base=src.adtte
             compare=src.adtte_aligned_final
             criterion=1E-8
             listall
             out=src.compare_final
             outbase outcomp outdiff;
  id studyid usubjid paramcd;
  title "Final Validation: Derived ADTTE vs Official ADTTE";
run;
```
________________________________________
## 4. Notes & Limitations
   •	The dermatologic event definition is based on a set of AEBODSYS and AEDECOD substrings; in a real study this would come from the clinical/statistical analysis plan or sponsor specifications. 
   •	This project focuses on a single parameter (TTDE) and a single event type (dermatologic AEs); extending to other TTE endpoints would follow a similar pattern.
   •	Minor differences may still occur if the original ADTTE used slightly different inclusion/exclusion rules for AEs (e.g. seriousness, toxicity grade, additional MedDRA groupings).

### 1. Why ADT and AVAL have 8 mismatches
From your summary table of the eight subjects with ADT mismatches, you’ve basically shown that: 
MISMATCHES-BY-USUBJID
   •	In most subjects, our rule
“first dermatologic, treatment-emergent AE with ASTDT ≥ TRTSDT, otherwise censor at RFENDT”
reproduces the official ADTTE.
   •	For 8 specific USUBJIDs, the sponsor appears to:
       o	sometimes use RFENDTC (RFENDT) as ADT (e.g., certain DCDECOD patterns like PROTOCOL VIOLATION or STUDY TERMINATED BY SPONSOR), or
       o	sometimes use a particular AE date (e.g. APPLICATION SITE ERYTHEMA, PRURITUS, SINUS BRADYCARDIA) even when that date is before TRTSDT or when there are other derm AEs.
Because AVAL = ADT – STARTDT + 1, every ADT mismatch automatically creates a mismatch in AVAL for those same 8 records; nothing wrong with the AVAL logic, it’s just inherited from ADT.
       o From these specific 8 USUBJID, for three of them the ADT has started when a skin related adverse event happened, therefore the CNSR, EVNTDSCR, SRCDOM, SRCVAR are correctly derived. For the 5 remaining USUBJID, because of the above reasons, we have mismatches.

### 2. Why SRCSEQ is off (8 + 2)
What I noticed about SRCSEQ is:
We’re currently taking SRCSEQ = AESEQ from the row you used to derive ADT (i.e., FIRST_DERM).
But:
1.	For the 8 ADT mismatches, our derivation and the CDISC aren’t even using the same ADAE row to drive the event date, so:
   o	our SRCSEQ points to our “event row”
   o	their SRCSEQ points to their “event row”
→ 8 SRCSEQ mismatches that are just a consequence of the ADT disagreement.
2.	Plus 2 extra mismatches where:
   o	ADT actually does match between our ADTTE and the official one, but
   o	there are multiple ADAE rows with that same ASTDT for the subject, and
   o	our code, by default, picks the first AESEQ for that date, while the theirs seems to pick a different one (maybe different AEDECOD, seriousness, severity, etc.).
So you get:
       •	8 SRCSEQ mismatches that are “downstream of ADT differences”, and
       •	2 SRCSEQ mismatches that are “tie-breaking differences when multiple AESEQ share the same date”.

________________________________________
## 5. Contact / Author
   •	Author: Jezerca Hodaj
   •	Topic: CDISC-style SDTM --> ADaM
Feel free to open an issue or fork this repo if you’d like to extend the derivation to additional parameters or event types.

---



