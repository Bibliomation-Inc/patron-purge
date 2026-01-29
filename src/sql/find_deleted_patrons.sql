/*
 * Bibliomation Patron Purge - Find Deleted But Not Purged Patrons
 * 
 * This script identifies patrons who have been marked as deleted but have not
 * yet had their personal information purged from the system.
 *
 * A patron is considered "purged" when their identifying information
 * (usrname, first_given_name, family_name) contains "PURGED".
 *
 * Usage: Run this script to generate a list of deleted patrons needing purge.
 *        Review the results before taking any action.
 */

BEGIN;

-- ============================================================================
-- MAIN QUERY
-- ============================================================================

SELECT 
    patron.id AS patron_id,
    org_unit.shortname AS library_shortname,
    patron.expire_date,
    patron.create_date,
    EXTRACT(YEAR FROM AGE(NOW(), patron.expire_date))::INT AS years_expired
FROM actor.usr AS patron
JOIN actor.org_unit AS org_unit ON patron.home_ou = org_unit.id
WHERE patron.deleted = TRUE
  -- Exclude already purged patrons
  AND patron.usrname NOT LIKE '%PURGED%'
  AND patron.first_given_name NOT LIKE '%PURGED%'
  AND patron.family_name NOT LIKE '%PURGED%'
ORDER BY org_unit.shortname, patron.expire_date;

ROLLBACK;
