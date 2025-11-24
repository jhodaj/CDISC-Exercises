# ADTTE Derivation: Time to First Dermatologic Event

This project shows how to derive an ADTTE-like analysis dataset dataset from the ADAE and ADSL datasets.
Time-to-First Dermatologic Event, `TTDE` from CDISC ADAE and ADSL datasets using SAS. 

The data are from this repository:  https://github.com/cdisc-org/sdtm-adam-pilot-project/tree/master

It is designed as a reproducible example of:

- Deriving time-to-event endpoints from AE + subject-level data  
- Implementing logic described in a define.xml-like specification  
- Validating a derived ADTTE against an “official” ADTTE using `PROC COMPARE`

---

## 1. Objective

The goal is to recreate the **ADTTE Time-to-First Dermatologic Event (TTDE)** dataset from:

- `ADAE` – Adverse Events
- `ADSL` – Subject-Level Analysis Dataset

and to compare the derived dataset with an **official ADTTE** (provided as an XPT file).

The main parameter:

- **`PARAMCD = TTDE`**  
  *Time to First Dermatologic Event*

---

## 2. Files in This Repository

Example structure:

```text
.
├── derive_adtte_from_adae.sas    # Main derivation program
├── CDISC/
│   └── DATASETS/
│       ├── adae.xpt              # ADAE in XPT format
│       ├── adsl.xpt              # ADSL in XPT format
│       └── adtte.xpt             # Official ADTTE (for QC)
└── README.md

```

## 3. Derivation Logic (High-Level)
The derivation follows these main steps (mirroring the define.xml):
3.1 Libraries & Imports
1.	Assign SAS libraries (e.g. src) and XPORT locations.
2.	Use PROC COPY to import:
-	adae.xpt → src.adae
-	adsl.xpt → src.adsl
-	adtte.xpt → src.adtte (official reference)
3.2 Merge ADAE + ADSL Core Variables
Create ADAE1 by left-joining ADAE to ADSL by USUBJID and keeping:
-	Subject-level variables (STUDYID, SITEID, AGE, SEX, RACE, TRTSDT, TRTEDT, RFSTDTC, RFENDTC, TRT01*, etc.)
-	AE-level variables (AEDECOD, AEBODSYS, TRTEMFL, ASTDT, AENDT, AESEQ)
3.3 Identify Dermatologic Events
From ADAE1, create ADAE_DERM:
  - Keep only treatment-emergent AEs:
TRTEMFL = "Y"
•	Flag as dermatologic if:
o	AEBODSYS contains "DERMAT" or "SKIN", or
o	AEDECOD contains terms such as:
-	APPLICATION SITE
-	ERYTHEMA
-	PRURITUS
-	RASH
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
3.4 First Dermatologic AE per Subject
1.	Sort ADAE_DERM by:
2.	BY USUBJID ASTDT AESEQ;
3.	Create FIRST_DERM containing only:
4.	IF FIRST.USUBJID;
This gives one row per subject, corresponding to the first dermatologic AE chronologically.
3.5 Derive ADT, AVAL, CNSR (Events)
Merge FIRST_DERM with ADSL and:
•	Convert RFSTDTC and RFENDTC to SAS dates (RFSTDT, RFENDT).
•	Convert ASTDT to a numeric date (ASTDT_NUM) if needed.
•	Set origin date:
o	STARTDT = RFSTDT
•	Set treatment duration:
o	TRTDUR = TRTSDT – TRTEDT + 1
Then apply the event/censor rule per define-style logic:
•	If ASTDT_NUM is non-missing and
ASTDT_NUM ≥ TRTSDT:
o	ADT = ASTDT_NUM
o	CNSR = 0
o	EVNTDESC = "Dematologic Event Occured"
o	SRCDOM = "ADAE", SRCVAR = "ASTDT", SRCSEQ = AESEQ
•	Else:
o	ADT = RFENDT
o	CNSR = 1
o	EVNTDESC = "Study Completion Date"
o	SRCDOM = "ADSL", SRCVAR = "RFENDT", SRCSEQ = .
Finally:
•	AVAL = ADT – STARTDT + 1
•	Set parameter metadata:
o	PARAMCD = "TTDE"
o	PARAM = "Time to First Dermatologic Event"
This dataset is called ADTTE_EVENTS.
3.6 Derive Censored Records (No Derm AE)
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
3.7 Combine & Align
•	Combine ADTTE_EVENTS and CENSORED2 into:
o	SRC.ADTTE_DERIVED
•	Reorder and relabel variables to match CDISC ADTTE structure:
o	SRC.ADTTE_ALIGNED_FINAL
________________________________________
4. Validation (QC)
The derived ADTTE is compared with the official ADTTE using PROC COMPARE:
proc compare base=src.adtte
             compare=src.adtte_aligned_final
             criterion=1E-8
             listall
             out=src.compare_final
             outbase outcomp outdiff;
  id studyid usubjid paramcd;
  title "Final Validation: Derived ADTTE vs Official ADTTE";
run;
Additional QC:
•	PROC FREQ for CNSR
•	PROC MEANS for AVAL and TRTDUR
These checks verify that:
•	Event vs censoring flags line up
•	Time-to-event values are consistent
•	Variable structure matches the official ADTTE
________________________________________
5. How to Run
5.1 Prerequisites
•	SAS environment (e.g. SAS OnDemand for Academics or Base SAS)
•	XPORT files for:
o	ADAE (adae.xpt)
o	ADSL (adsl.xpt)
o	ADTTE (adtte.xpt – official, for comparison)
5.2 Steps
1.	Upload the XPT files to the path used in the program (e.g. /home/.../CDISC/DATASETS).
2.	Upload derive_adtte_from_adae.sas to your SAS environment.
3.	Open the program and adjust library paths if needed.
4.	Submit the program.
5.	Review:
o	SRC.ADTTE_ALIGNED_FINAL
o	SRC.COMPARE_FINAL
o	Log and PROC outputs
________________________________________
6. Notes & Limitations
•	The dermatologic event definition is based on a set of AEBODSYS and AEDECOD substrings; in a real study this would come from the clinical/statistical analysis plan or sponsor specifications.
•	This project focuses on a single parameter (TTDE) and a single event type (dermatologic AEs); extending to other TTE endpoints would follow a similar pattern.
•	Minor differences may still occur if the original ADTTE used slightly different inclusion/exclusion rules for AEs (e.g. seriousness, toxicity grade, additional MedDRA groupings).
________________________________________
7. Contact / Author
•	Author: Jezerca Hodaj
•	Topic: Time-to-Event Derivation from ADAE/ADSL (Dermatologic Events)
Feel free to open an issue or fork this repo if you’d like to extend the derivation to additional parameters or event types.

---



