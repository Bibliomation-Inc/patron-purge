# Bibliomation Patron Purge

This repository contains scripts and documentation for purging patron records from the Evergreen integrated library system. The scripts are designed to help server administrators efficiently remove inactive or outdated patron accounts while ensuring data integrity and compliance with privacy regulations.

## Criteria for Purging Patrons

The criteria for purging patrons was decided by the Bibliomation ILS Steering Committee.

Patrons are eligible for purging if they meet the following conditions:

- No bills on their account
- No lost items associated with their account
- Expired for > 5 years
- No activity (checkouts, renewals, holds, etc.) for > 5 years