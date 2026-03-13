/*
 * Bibliomation Patron Purge - Manual Test Queries
 * 
 * Run these queries BEFORE and AFTER the purge to verify that only the
 * intended patrons were affected. The counts for tests 1-3 should remain
 * unchanged after the purge. Test 4 should increase by the expected amount.
 *
 * Usage: Run the combined query and record the results before the purge.
 *        After the purge, run again and compare.
 */

-- ============================================================================
-- COMBINED TEST RESULTS
-- All tests in one query using CTEs for easy comparison
-- ============================================================================

WITH
-- TEST 1: Count of patrons expiring in less than 5 years
-- EXPECTED: This count should NOT change after the purge
test_1_not_expired AS (
    SELECT 
        1 AS test_num,
        'Patrons expiring in less than 5 years' AS test_description,
        'Should NOT change' AS expected_behavior,
        COUNT(*)::TEXT AS result
    FROM actor.usr AS patron
    WHERE patron.deleted = FALSE
      AND patron.usrname NOT LIKE '%PURGED%'
      AND patron.expire_date >= (NOW() - INTERVAL '5 years')
),

-- TEST 2: Count of patrons with activity in the last 5 years
-- EXPECTED: This count should NOT change after the purge
test_2_recent_activity AS (
    SELECT 
        2 AS test_num,
        'Patrons with circulation activity in last 5 years' AS test_description,
        'Should NOT change' AS expected_behavior,
        COUNT(DISTINCT patron.id)::TEXT AS result
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
      )
),

-- TEST 3: Count of patrons NOT in purge-eligible permission groups
-- EXPECTED: This count should NOT change after the purge
test_3_protected_groups AS (
    SELECT 
        3 AS test_num,
        'Patrons NOT in purge-eligible permission groups' AS test_description,
        'Should NOT change' AS expected_behavior,
        COUNT(*)::TEXT AS result
    FROM actor.usr AS patron
    JOIN permission.grp_tree AS perm_group ON patron.profile = perm_group.id
    WHERE patron.deleted = FALSE
      AND patron.usrname NOT LIKE '%PURGED%'
      -- NOT a child of group 2 (standard patron groups) OR is group 121 (PL Staff)
      AND (perm_group.parent <> 2 OR perm_group.id = 121)
),

-- TEST 4: Count of all purged patrons
-- EXPECTED: This count SHOULD INCREASE by the expected purge amount
test_4_total_purged AS (
    SELECT 
        4 AS test_num,
        'Total purged patrons' AS test_description,
        'Should INCREASE by purge count' AS expected_behavior,
        COUNT(*)::TEXT AS result
    FROM actor.usr AS patron
    WHERE patron.usrname LIKE '%PURGED%'
       OR patron.first_given_name LIKE '%PURGED%'
       OR patron.family_name LIKE '%PURGED%'
)

-- Combine all test results into one table
SELECT test_num, test_description, expected_behavior, result
FROM test_1_not_expired
UNION ALL
SELECT test_num, test_description, expected_behavior, result
FROM test_2_recent_activity
UNION ALL
SELECT test_num, test_description, expected_behavior, result
FROM test_3_protected_groups
UNION ALL
SELECT test_num, test_description, expected_behavior, result
FROM test_4_total_purged
ORDER BY test_num;


-- ============================================================================
-- BONUS: Summary by library for purged patrons
-- Useful for reporting and verification by member library
-- (Kept separate due to different output structure)
-- ============================================================================

SELECT 
    org_unit.shortname AS library_shortname,
    COUNT(*) AS purged_patron_count
FROM actor.usr AS patron
JOIN actor.org_unit AS org_unit ON patron.home_ou = org_unit.id
WHERE patron.usrname LIKE '%PURGED%'
   OR patron.first_given_name LIKE '%PURGED%'
   OR patron.family_name LIKE '%PURGED%'
GROUP BY org_unit.shortname
ORDER BY org_unit.shortname;
