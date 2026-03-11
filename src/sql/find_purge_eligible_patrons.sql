/*
 * Bibliomation Patron Purge - Find Eligible Patrons
 * 
 * This script identifies patrons eligible for purging based on the following criteria:
 *   1. No bills on their account
 *   2. No lost items associated with their account
 *   3. Expired for > 5 years
 *   4. No activity (checkouts, renewals, holds, etc.) for > 5 years
 *
 * Usage: Run this script to generate a list of patron IDs eligible for purging.
 *        Review the results before taking any action.
 */

BEGIN;

-- ============================================================================
-- MAIN QUERY
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
-- Adjust these values as needed for your institution's policies.

WITH config AS (
    -- Centralized configuration for easy maintenance
    SELECT 
        INTERVAL '5 years' AS expiration_threshold,
        INTERVAL '5 years' AS inactivity_threshold
),

patron_base AS (
    -- Find all patrons who are potentially eligible for purging
    -- Excludes already purged patrons and system accounts
    SELECT 
        patron.id AS patron_id,
        patron.home_ou,
        patron.expire_date,
        org_unit.shortname AS library_shortname,
        perm_group.name AS permission_group
    FROM actor.usr AS patron
    JOIN permission.grp_tree AS perm_group ON patron.profile = perm_group.id
    JOIN actor.org_unit AS org_unit ON patron.home_ou = org_unit.id
    WHERE patron.deleted = FALSE
      -- Exclude already purged patrons
      AND patron.usrname NOT LIKE '%PURGED%'
      AND patron.first_given_name NOT LIKE '%PURGED%'
      AND patron.family_name NOT LIKE '%PURGED%'
      -- Only include patron-level permission groups (children of group 2)
      AND perm_group.parent = 2
      -- Exclude permission group with id 121 (PL Staff)
      AND perm_group.id <> 121
),

expired_patrons AS (
    -- Filter to patrons expired for longer than the threshold
    SELECT 
        patron_base.patron_id,
        patron_base.home_ou,
        patron_base.expire_date,
        patron_base.library_shortname,
        patron_base.permission_group
    FROM patron_base
    CROSS JOIN config
    WHERE patron_base.expire_date < (NOW() - config.expiration_threshold)
),

purge_eligible AS (
    -- Apply all purge criteria filters
    SELECT 
        expired_patrons.patron_id,
        expired_patrons.home_ou,
        expired_patrons.expire_date,
        expired_patrons.library_shortname,
        expired_patrons.permission_group
    FROM expired_patrons
    CROSS JOIN config
    
    -- Criterion: No lost items (status = 3 is "Lost")
    WHERE NOT EXISTS (
        SELECT 1
        FROM action.all_circulation AS circulation
        JOIN asset.copy AS item_copy ON item_copy.id = circulation.target_copy
        WHERE circulation.usr = expired_patrons.patron_id
          AND item_copy.status = 3
    )
    
    -- Criterion: No circulation activity within inactivity threshold
    AND NOT EXISTS (
        SELECT 1
        FROM action.all_circulation AS circulation
        WHERE circulation.usr = expired_patrons.patron_id
          AND circulation.xact_finish > (NOW() - config.inactivity_threshold)
    )
    
    -- Criterion: No hold requests within inactivity threshold
    AND NOT EXISTS (
        SELECT 1
        FROM action.hold_request AS hold_request
        WHERE hold_request.usr = expired_patrons.patron_id
          AND hold_request.request_time > (NOW() - config.inactivity_threshold)
    )
    
    -- Criterion: No outstanding bills (open billable transactions)
    AND NOT EXISTS (
        SELECT 1
        FROM money.billable_xact AS billable_xact
        WHERE billable_xact.usr = expired_patrons.patron_id
          AND billable_xact.xact_finish IS NULL
    )
)

-- ============================================================================
-- OUTPUT
-- ============================================================================
-- Returns all purge-eligible patrons with relevant details for review

SELECT 
    purge_eligible.patron_id,
    purge_eligible.library_shortname,
    purge_eligible.permission_group,
    purge_eligible.expire_date,
    EXTRACT(YEAR FROM AGE(NOW(), purge_eligible.expire_date))::INT AS years_expired
FROM purge_eligible
ORDER BY purge_eligible.library_shortname, purge_eligible.expire_date;

ROLLBACK;
