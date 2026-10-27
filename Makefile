# Explicit, not auto-detected: an empty test/install/ gives one clear make-time
# error instead of a pile of test failures.
PGXNTOOL_ENABLE_TEST_INSTALL = yes

include pgxntool/base.mk

#
# Test deps
#

test_core_files = $(wildcard $(TESTDIR)/core/*.sql)
testdeps: $(test_core_files)

# TEST_LOAD_SOURCE selects how test/install/load.sql installs trunklet, once and
# committed, for the whole test run:
#   - fresh (default): CREATE EXTENSION at the current version.
#   - update: CREATE EXTENSION at TEST_UPDATE_FROM, store a test language and
#     templates, then ALTER EXTENSION UPDATE to the current version and check
#     them (test/helpers/update_with_data.sql). The suite and its expected
#     output are the same, so a pass means the updated install behaves like a
#     fresh one.
# The settings reach load.sql as placeholder GUCs via PGOPTIONS, which the psql
# processes pg_regress spawns inherit. Both are always exported so load.sql can
# fail if they didn't propagate; test_update_from is only read in update mode.
# There is no `existing` mode: trunklet has no pg_upgrade job.
TEST_LOAD_SOURCE ?= fresh
ifeq ($(filter $(TEST_LOAD_SOURCE),fresh update),)
$(error TEST_LOAD_SOURCE must be 'fresh' or 'update', got '$(TEST_LOAD_SOURCE)')
endif
TEST_UPDATE_FROM ?= 0.2.0
export PGOPTIONS := $(PGOPTIONS) -c trunklet.test_load_mode=$(TEST_LOAD_SOURCE) -c trunklet.test_update_from=$(TEST_UPDATE_FROM)

# Recurses so the PGOPTIONS export above is re-evaluated with update set.
.PHONY: test-update
test-update:
	$(MAKE) test TEST_LOAD_SOURCE=update

# Diffs every extension member's definition, comments and ACLs between a fresh
# install and one updated from TEST_UPDATE_FROM; see bin/compare_fresh_vs_update.
.PHONY: compare-fresh-vs-update
compare-fresh-vs-update: install
	bin/compare_fresh_vs_update $(TEST_UPDATE_FROM)
