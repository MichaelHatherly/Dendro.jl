#!/usr/bin/env bash
# Fixtures for the bash half of the pack Dendro ships.
#
# A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
# must not be, so the near-miss written beside each rule is as much of the test as the match
# is. This file is deliberately bad shell and lives under `test/` for that reason: `src/` is
# what the dogfood gate scans.

# --- banner_comment ---

# dendro-expect: banner_comment
# ========================================

# dendro-expect: banner_comment
# ----------------------------------------

# --- A rule with a title in it is a heading and stays ---

# --- unreachable_branch ---

repeats_a_condition() {
    if [ "$1" -gt 0 ]; then  # dendro-expect: unreachable_branch
        echo one
    elif [ "$1" -gt 0 ]; then
        echo two
    else
        echo three
    fi
}

repeats_a_later_condition() {
    if [ "$1" -gt 0 ]; then  # dendro-expect: unreachable_branch
        echo one
    elif [ "$2" -gt 0 ]; then
        echo two
    elif [ "$2" -gt 0 ]; then
        echo three
    fi
}

tests_two_things() {
    if [ "$1" -gt 0 ]; then
        echo one
    elif [ "$2" -gt 0 ]; then
        echo two
    else
        echo three
    fi
}
