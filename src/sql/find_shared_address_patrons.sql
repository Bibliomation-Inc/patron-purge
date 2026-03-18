/*
 * Bibliomation Patron Purge - Find Deleted Patrons With Shared Addresses
 * 
 * Identifies deleted (but not yet purged) patrons whose addresses are
 * referenced by other users' mailing_address or billing_address fields.
 *
 * These patrons cannot be purged by actor.usr_delete() because dropping
 * their address records would violate foreign key constraints on actor.usr.
 *
 * Usage: Run by purge_deleted_patrons.pl to exclude these patrons from purge.
 */

BEGIN;

SELECT DISTINCT patron.id AS patron_id
FROM actor.usr AS patron
JOIN actor.usr_address AS addr ON addr.usr = patron.id
WHERE patron.deleted = TRUE
  AND patron.usrname NOT LIKE '%PURGED%'
  AND patron.first_given_name NOT LIKE '%PURGED%'
  AND patron.family_name NOT LIKE '%PURGED%'
  -- Address is referenced by another user's billing or mailing address
  AND EXISTS (
      SELECT 1
      FROM actor.usr AS other_user
      WHERE other_user.id <> patron.id
        AND (other_user.mailing_address = addr.id OR other_user.billing_address = addr.id)
  );

ROLLBACK;
