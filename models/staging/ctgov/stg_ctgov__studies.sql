with source as (

    select * from {{ source('ctgov', 'studies') }}

),

renamed as (

    select
        -- identification
        protocolSection.identificationModule.nctId as nct_id,
        protocolSection.identificationModule.acronym,
        protocolSection.identificationModule.briefTitle as brief_title,
        protocolSection.identificationModule.officialTitle as official_title,
        protocolSection.identificationModule.orgStudyIdInfo.id as org_study_id,
        protocolSection.identificationModule.organization.fullName as organization_name,
        protocolSection.identificationModule.organization.class as organization_class,
        protocolSection.identificationModule.nctIdAliases as nct_id_aliases,

        -- sponsorship
        protocolSection.sponsorCollaboratorsModule.leadSponsor.name as lead_sponsor_name,
        protocolSection.sponsorCollaboratorsModule.leadSponsor.class as lead_sponsor_class,
        protocolSection.sponsorCollaboratorsModule.collaborators,

        -- design
        protocolSection.designModule.studyType as study_type,
        protocolSection.designModule.phases,
        protocolSection.designModule.enrollmentInfo.count as enrollment_count,
        protocolSection.designModule.enrollmentInfo.type as enrollment_type,
        protocolSection.designModule.designInfo.allocation,
        protocolSection.designModule.designInfo.interventionModel as intervention_model,
        protocolSection.designModule.designInfo.primaryPurpose as primary_purpose,
        protocolSection.designModule.designInfo.maskingInfo.masking,

        -- arrays carried through untouched; step 4 explodes them
        protocolSection.conditionsModule.conditions,
        protocolSection.conditionsModule.keywords,
        protocolSection.armsInterventionsModule.armGroups as arm_groups,
        protocolSection.armsInterventionsModule.interventions,

        -- status
        protocolSection.statusModule.overallStatus as overall_status,
        protocolSection.statusModule.lastKnownStatus as last_known_status,
        protocolSection.statusModule.whyStopped as why_stopped,
        protocolSection.statusModule.expandedAccessInfo.hasExpandedAccess as has_expanded_access,

        -- a cross-reference to a DIFFERENT, expanded-access study that this
        -- interventional cohort excludes. never join it as if it were nct_id.
        protocolSection.statusModule.expandedAccessInfo.nctId as expanded_access_ref_nct_id,

        -- dates: ~40% arrive as YYYY-MM, so try day precision, then fall back to month
        coalesce(
            try_to_date(protocolSection.statusModule.startDateStruct.date, 'yyyy-MM-dd'),
            try_to_date(protocolSection.statusModule.startDateStruct.date, 'yyyy-MM')
        ) as start_date,
        protocolSection.statusModule.startDateStruct.type as start_date_type,
        case
            when protocolSection.statusModule.startDateStruct.date is null then null
            when length(protocolSection.statusModule.startDateStruct.date) = 7 then 'month'
            else 'day'
        end as start_date_precision,

        coalesce(
            try_to_date(protocolSection.statusModule.primaryCompletionDateStruct.date, 'yyyy-MM-dd'),
            try_to_date(protocolSection.statusModule.primaryCompletionDateStruct.date, 'yyyy-MM')
        ) as primary_completion_date,
        protocolSection.statusModule.primaryCompletionDateStruct.type as primary_completion_date_type,
        case
            when protocolSection.statusModule.primaryCompletionDateStruct.date is null then null
            when length(protocolSection.statusModule.primaryCompletionDateStruct.date) = 7 then 'month'
            else 'day'
        end as primary_completion_date_precision,

        coalesce(
            try_to_date(protocolSection.statusModule.completionDateStruct.date, 'yyyy-MM-dd'),
            try_to_date(protocolSection.statusModule.completionDateStruct.date, 'yyyy-MM')
        ) as completion_date,
        protocolSection.statusModule.completionDateStruct.type as completion_date_type,
        case
            when protocolSection.statusModule.completionDateStruct.date is null then null
            when length(protocolSection.statusModule.completionDateStruct.date) = 7 then 'month'
            else 'day'
        end as completion_date_precision,

        -- registry-generated, measured at 0% month precision; same defensive cast anyway
        coalesce(
            try_to_date(protocolSection.statusModule.studyFirstPostDateStruct.date, 'yyyy-MM-dd'),
            try_to_date(protocolSection.statusModule.studyFirstPostDateStruct.date, 'yyyy-MM')
        ) as study_first_post_date,
        coalesce(
            try_to_date(protocolSection.statusModule.lastUpdatePostDateStruct.date, 'yyyy-MM-dd'),
            try_to_date(protocolSection.statusModule.lastUpdatePostDateStruct.date, 'yyyy-MM')
        ) as last_update_post_date,
        coalesce(
            try_to_date(protocolSection.statusModule.resultsFirstPostDateStruct.date, 'yyyy-MM-dd'),
            try_to_date(protocolSection.statusModule.resultsFirstPostDateStruct.date, 'yyyy-MM')
        ) as results_first_post_date,

        -- landing metadata
        cast(_pulled_at as timestamp) as _pulled_at,
        _loaded_at,
        _source_file,
        _batch_id

    from source

)

select *
from renamed
qualify row_number() over (partition by nct_id order by _pulled_at desc) = 1
