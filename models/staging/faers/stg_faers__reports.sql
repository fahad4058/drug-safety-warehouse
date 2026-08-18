with source as (

    select * from {{ source('faers', 'events') }}

),

renamed as (

    select
        -- case identity and version
        safetyreportid as safety_report_id,
        cast(safetyreportversion as int) as safety_report_version,
        companynumb as company_number,
        authoritynumb as authority_number,

        -- the FDA's own duplicate flags, marking a case as a duplicate of a
        -- DIFFERENT safetyreportid. non-null on 28,780 of 144,000 rows (20%).
        -- carried through and never filtered here: excluding them is a mart
        -- decision, and the QUALIFY below cannot catch them because the ids differ.
        duplicate,
        reportduplicate as report_duplicate,

        -- classification
        reporttype as report_type,
        serious,
        seriousnessdeath as seriousness_death,
        seriousnesshospitalization as seriousness_hospitalization,
        seriousnesslifethreatening as seriousness_life_threatening,
        seriousnessdisabling as seriousness_disabling,
        seriousnesscongenitalanomali as seriousness_congenital_anomaly,
        seriousnessother as seriousness_other,
        fulfillexpeditecriteria as fulfill_expedite_criteria,

        -- geography, reporter, routing
        occurcountry as occur_country,
        primarysourcecountry as primary_source_country,
        primarysource.reportercountry as reporter_country,
        primarysource.qualification as reporter_qualification,
        primarysource.literaturereference as literature_reference,
        sender.senderorganization as sender_organization,
        sender.sendertype as sender_type,
        receiver.receiverorganization as receiver_organization,
        receiver.receivertype as receiver_type,

        -- patient scalars. onset age deliberately stays a string: it is
        -- meaningless without its E2B unit code (801 = year, 802 = month, ...),
        -- so normalising it is mart work, not a cast.
        patient.patientsex as patient_sex,
        patient.patientagegroup as patient_age_group,
        patient.patientonsetage as patient_onset_age,
        patient.patientonsetageunit as patient_onset_age_unit,
        patient.patientweight as patient_weight,
        patient.summary.narrativeincludeclinical as narrative_include_clinical,

        -- arrays carried through untouched; step 4 explodes them. `drugs` still
        -- holds medicinalproduct and openfda -- the two fields DESCRIBE truncates
        -- away, and the ones the drugsfda join depends on.
        patient.drug as drugs,
        patient.reaction as reactions,

        -- every row carries format code 102 (CCYYMMDD), measured across all
        -- 144,000, so one format string covers all three date fields.
        try_to_date(receiptdate, 'yyyyMMdd') as receipt_date,
        try_to_date(receivedate, 'yyyyMMdd') as receive_date,
        try_to_date(transmissiondate, 'yyyyMMdd') as transmission_date,

        -- landing metadata. _loaded_at and _batch_id both come from a single
        -- current_timestamp() folded once per COPY INTO, so they are constant
        -- across every file in a load and useless as an ordering key.
        cast(_pulled_at as timestamp) as _pulled_at,
        _loaded_at,
        _source_file,
        _batch_id

    from source

)

select *
from renamed
qualify row_number() over (
    partition by safety_report_id
    order by safety_report_version desc, _pulled_at desc, _source_file desc
) = 1
