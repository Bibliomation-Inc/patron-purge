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
        u.id AS patron_id,
        u.home_ou,
        u.expire_date,
        o.shortname AS library_shortname
    FROM actor.usr u
    JOIN permission.grp_tree g ON u.profile = g.id
    JOIN actor.org_unit o ON u.home_ou = o.id
    WHERE u.deleted = FALSE
      -- Exclude already purged patrons
      AND u.usrname NOT LIKE '%PURGED%'
      AND u.first_given_name NOT LIKE '%PURGED%'
      AND u.family_name NOT LIKE '%PURGED%'
      -- Only include patron-level permission groups (children of group 2)
      AND g.parent = 2
),

expired_patrons AS (
    -- Filter to patrons expired for longer than the threshold
    SELECT 
        pb.patron_id,
        pb.home_ou,
        pb.expire_date,
        pb.library_shortname
    FROM patron_base pb
    CROSS JOIN config c
    WHERE pb.expire_date < (NOW() - c.expiration_threshold)
),

purge_eligible AS (
    -- Apply all purge criteria filters
    SELECT 
        ep.patron_id,
        ep.home_ou,
        ep.expire_date,
        ep.library_shortname
    FROM expired_patrons ep
    CROSS JOIN config c
    
    -- Criterion: No lost items (status = 3 is "Lost")
    WHERE NOT EXISTS (
        SELECT 1
        FROM action.all_circulation ac
        JOIN asset.copy cp ON cp.id = ac.target_copy
        WHERE ac.usr = ep.patron_id
          AND cp.status = 3
    )
    
    -- Criterion: No circulation activity within inactivity threshold
    AND NOT EXISTS (
        SELECT 1
        FROM action.all_circulation ac
        WHERE ac.usr = ep.patron_id
          AND ac.xact_finish > (NOW() - c.inactivity_threshold)
    )
    
    -- Criterion: No hold requests within inactivity threshold
    AND NOT EXISTS (
        SELECT 1
        FROM action.hold_request hr
        WHERE hr.usr = ep.patron_id
          AND hr.request_time > (NOW() - c.inactivity_threshold)
    )
    
    -- Criterion: No outstanding bills (open billable transactions)
    AND NOT EXISTS (
        SELECT 1
        FROM money.billable_xact bx
        WHERE bx.usr = ep.patron_id
          AND bx.xact_finish IS NULL
    )
)

-- ============================================================================
-- OUTPUT
-- ============================================================================
-- Returns all purge-eligible patrons with relevant details for review

SELECT 
    pe.patron_id,
    pe.library_shortname,
    pe.expire_date,
    EXTRACT(YEAR FROM AGE(NOW(), pe.expire_date))::INT AS years_expired
FROM purge_eligible pe
ORDER BY pe.library_shortname, pe.expire_date;

ROLLBACK;
