#!/bin/bash

set -e

git init

# Nested history: each branch is created from the previous branch's tip,
# so every parent tip is an ancestor of its child.
git checkout -b master
git commit --allow-empty -m "master.1"

git checkout -b a
git commit --allow-empty -m "a.1"

git checkout -b b
git commit --allow-empty -m "b.1"

git checkout -b c
git commit --allow-empty -m "c.1"

PREV=""
for b in master a b c; do
    if [[ ! -z "$PREV" ]]; then
        git config branch.$b.chain default
        git config branch.$b.parentBranch $PREV
        git config branch.$b.branchPoint $(git rev-parse $PREV)
    fi
    PREV=$b
done

# Advance master after the chain exists, so every chain branch is stale.
git checkout master
git commit --allow-empty -m "master.2"
git checkout c
