#!/bin/bash

set -e

git init

# Nested history like linear-chain, but with a file change on the bottom
# branch that conflicts with a later commit on master.
git checkout -b master
echo "master base" > shared.txt
git add shared.txt
git commit -m "master.1"

git checkout -b a
echo "a change" > shared.txt
git add shared.txt
git commit -m "a.1"

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

# Advance master with a conflicting change to shared.txt.
git checkout master
echo "master conflict" > shared.txt
git add shared.txt
git commit -m "master.2"
git checkout c
