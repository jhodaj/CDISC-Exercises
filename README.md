# ADTTE Derivation: Time to First Dermatologic Event

This project shows how to derive an ADTTE-like analysis dataset dataset from the ADAE and ADSL datasets.
Time-to-First Dermatologic Event, `TTDE` from CDISC ADAE and ADSL datasets using SAS.

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

Adjust this section to match your actual repo layout.

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

