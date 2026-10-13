#!/bin/bash
# Syncs Brauz with upstream Search by rebasing main on upstream/main.
#
#   ./sync.sh
#
# Keeps the fork's commits linear on top of upstream, each with
# CHANGELOG.md exactly as upstream has it (DOCS/FORK.md, rule 8).
# Never pushes. See DOCS/FORK.md, "Syncing with upstream".
set -euo pipefail

cd "$(dirname "$0")"

# Xcode lives on an external drive; SwiftUI macros require the full Xcode toolchain.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  DEVELOPER_DIR="/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer"
fi
if [ ! -d "$DEVELOPER_DIR" ]; then
  echo "Mount /Volumes/pet30-a first: Xcode lives there." >&2
  exit 1
fi
export DEVELOPER_DIR

# Guard against in-progress rebases, wrong branches, or dirty state.
REBASE_MERGE="$(git rev-parse --git-path rebase-merge)"
REBASE_APPLY="$(git rev-parse --git-path rebase-apply)"
if [ -e "$REBASE_MERGE" ] || [ -e "$REBASE_APPLY" ]; then
  echo "A rebase is in progress: finish it with 'git rebase --continue' (or undo with 'git rebase --abort'), then run ./sync.sh again." >&2
  exit 1
fi

BRANCH="$(git branch --show-current)"
if [ "$BRANCH" != "main" ]; then
  echo "Current branch is '$BRANCH', expected 'main'. Switch to main first." >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree is not clean. Commit or stash changes before syncing." >&2
  exit 1
fi

git fetch -q upstream
git fetch -q origin

behind="$(git rev-list --count main..upstream/main)"

if [ "$behind" -eq 0 ]; then
  if [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]; then
    echo "Brauz is up to date with Search and pushed."
    exit 0
  fi
  # behind == 0 but main differs from origin/main:
  # re-run after manual conflict resolution, continue to verification.
else
  echo "$behind commit(s) behind upstream/main:"
  git log --oneline main..upstream/main

  git tag -f pre-sync-backup main
  echo "Tagged pre-sync-backup. 'git reset --hard pre-sync-backup' undoes the sync."

  set +e
  git rebase upstream/main -x 'git checkout upstream/main -- CHANGELOG.md && git commit -q --amend --no-edit --allow-empty'
  rebase_status=$?
  set -e

  if [ "$rebase_status" -ne 0 ]; then
    if ! [ -e "$REBASE_MERGE" ] && ! [ -e "$REBASE_APPLY" ]; then
      echo "git rebase failed." >&2
      exit 1
    fi
    while [ -e "$REBASE_MERGE" ] || [ -e "$REBASE_APPLY" ]; do
      conflicted="$(git diff --name-only --diff-filter=U)"
      if [ "$conflicted" = "CHANGELOG.md" ]; then
        git checkout upstream/main -- CHANGELOG.md
        git add CHANGELOG.md
        set +e
        GIT_EDITOR=true git rebase --continue
        continue_status=$?
        set -e
        if [ "$continue_status" -ne 0 ] && ! [ -e "$REBASE_MERGE" ] && ! [ -e "$REBASE_APPLY" ]; then
          echo "git rebase --continue failed." >&2
          exit 1
        fi
      else
        commit="$(git log -1 --format='%h %s' REBASE_HEAD 2>/dev/null || git log -1 --format='%h %s' HEAD 2>/dev/null || true)"
        if [ -n "$commit" ]; then
          echo "$commit" >&2
        fi
        if [ -n "$conflicted" ]; then
          echo "$conflicted" >&2
        else
          echo "Rebase stopped with no conflicted files (exec failure or empty commit)." >&2
        fi
        echo "Resolve them, 'git add' them, 'git rebase --continue', then run ./sync.sh again; or 'git rebase --abort' to go back." >&2
        exit 1
      fi
    done
  fi
fi

# Verification
mkdir -p build
if ! swift test > build/sync-test.log 2>&1; then
  grep 'Test Case .* failed' build/sync-test.log >&2 || true
  echo "Tests failed: see build/sync-test.log" >&2
  exit 1
fi

if ! ./build.sh; then
  exit 1
fi

fork_commits="$(git rev-list --count upstream/main..main)"
echo "Brauz has $fork_commits fork commit(s) on top of Search."
echo "Publish:"
echo "  git push --force-with-lease origin main"
