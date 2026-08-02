# Public private-CI hub continuation

The implementation is complete on `feature/public-private-ci-hub`.

Next operational steps:

1. open and merge the pull request into `main` after `Validate private CI hub` succeeds;
2. ensure `PRIVATE_REPOSITORIES_TOKEN` has read-only Contents access to `goanime-mobile`, `Zapzap`, and `SemogSite`;
3. create permanent branch `build/private-ci` from the merged `main`;
4. update only `triggers/private-ci.json` on that branch to request a connector-driven run;
5. inspect the public `Run private project CI` result and fix project-specific build failures without weakening the checkout or artifact restrictions.
