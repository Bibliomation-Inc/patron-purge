/*
 * Bibliomation Patron Purge - Manual Test Queries
 * 
 * Run these queries BEFORE and AFTER the purge to verify that only the
 * intended patrons were affected. The counts for tests 1-3 should remain
 * unchanged after the purge. Test 4 should increase by the expected amount.
 *
 * Usage: Run each query and record the results before the purge.
 *        After the purge, run again and compare.
 */

-- ============================================================================
-- CONFIGURATION (must match find_purge_eligible_patrons.sql)
-- ============================================================================

-- Using the same thresholds as the main purge script
-- Adjust if your institution's policies differ

-- ============================================================================
-- TEST 1: Count of patrons expiring in less than 5 years
-- EXPECTED: This count should NOT change after the purge
-- These patrons are not eligible for purging
-- ============================================================================

SELECT 
    'Patrons expiring in less than 5 years' AS test_description,
    COUNT(*) AS patron_count
FROM actor.usr AS patron
WHERE patron.deleted = FALSE
  AND patron.usrname NOT LIKE '%PURGED%'
  AND patron.expire_date >= (NOW() - INTERVAL '5 years');


-- ============================================================================
-- TEST 2: Count of patrons with activity in the last 5 years
-- EXPECTED: This count should NOT change after the purge
-- These patrons are not eligible for purging due to recent activity
-- ============================================================================

SELECT 
    'Patrons with circulation activity in last 5 years' AS test_description,
    COUNT(DISTINCT patron.id) AS patron_count
FROM actor.usr AS patron
WHERE patron.deleted = FALSE
  AND patron.usrname NOT LIKE '%PURGED%'
  AND (
      -- Has recent circulation activity
      EXISTS (
          SELECT 1
          FROM action.all_circulation AS circulation
          WHERE circulation.usr = patron.id
            AND circulation.xact_finish > (NOW() - INTERVAL '5 years')
      )
      -- OR has recent hold requests
      OR EXISTS (
          SELECT 1
          FROM action.hold_request AS hold_request
          WHERE hold_request.usr = patron.id
            AND hold_request.request_time > (NOW() - INTERVAL '5 years')
      )
  );


-- ============================================================================
-- TEST 3: Count of patrons NOT in purge-eligible permission groups
-- EXPECTED: This count should NOT change after the purge
-- These patrons are excluded because they are staff or other protected groups
-- ============================================================================

SELECT 
    'Patrons NOT in purge-eligible permission groups' AS test_description,
    COUNT(*) AS patron_count
FROM actor.usr AS patron
JOIN permission.grp_tree AS perm_group ON patron.profile = perm_group.id
WHERE patron.deleted = FALSE
  AND patron.usrname NOT LIKE '%PURGED%'
  -- NOT a child of group 2 (standard patron groups) OR is group 121 (PL Staff)
  AND (perm_group.parent <> 2 OR perm_group.id = 121);


-- ============================================================================
-- TEST 4: Count of all purged patrons
-- EXPECTED: This count SHOULD INCREASE by the expected purge amount
-- Record before purge, then verify the increase matches expectations
-- ============================================================================

SELECT 
    'Total purged patrons' AS test_description,
    COUNT(*) AS patron_count
FROM actor.usr AS patron
WHERE patron.usrname LIKE '%PURGED%'
   OR patron.first_given_name LIKE '%PURGED%'
   OR patron.family_name LIKE '%PURGED%';


-- ============================================================================
-- BONUS: Summary by library for purged patrons
-- Useful for reporting and verification by member library
-- ============================================================================

SELECT 
    'Purged patrons by library' AS test_description,
    org_unit.shortname AS library_shortname,
    COUNT(*) AS patron_count
FROM actor.usr AS patron
JOIN actor.org_unit AS org_unit ON patron.home_ou = org_unit.id
WHERE patron.usrname LIKE '%PURGED%'
   OR patron.first_given_name LIKE '%PURGED%'
   OR patron.family_name LIKE '%PURGED%'
GROUP BY org_unit.shortname
ORDER BY org_unit.shortname;
