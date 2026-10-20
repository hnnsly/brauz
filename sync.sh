#!/bin/bash
# Syncs Brauz with upstream Search using a topical branch and manual PR workflow.
#
#   ./sync.sh
#
# Replays fork commits onto upstream/main, keeping CHANGELOG.md as upstream has it.
# Verifies build and tests with the external Xcode toolchain. Never modifies main
# and never pushes. See DOCS/FORK.md.
set -euo pipefail

cd "$(dirname "$0")"

# Required external Xcode toolchain.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  DEVELOPER_DIR="/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer"
fi
if [ ! -d "$DEVELOPER_DIR" ]; then
  echo "Mount /Volumes/pet30-a first: Xcode lives there." >&2
  exit 1
fi
export DEVELOPER_DIR

# Reject detached HEAD.
BRANCH="$(git symbolic-ref --short -q HEAD || true)"
if [ -z "$BRANCH" ]; then
  echo "Detached HEAD state is not supported. Switch to a branch first." >&2
  exit 1
fi

# Reject in-progress git operations.
REBASE_MERGE="$(git rev-parse --git-path rebase-merge)"
REBASE_APPLY="$(git rev-parse --git-path rebase-apply)"
MERGE_HEAD="$(git rev-parse --git-path MERGE_HEAD)"
CHERRY_PICK_HEAD="$(git rev-parse --git-path CHERRY_PICK_HEAD)"
REVERT_HEAD="$(git rev-parse --git-path REVERT_HEAD)"
BISECT_LOG="$(git rev-parse --git-path BISECT_LOG)"
if [ -e "$REBASE_MERGE" ] || [ -e "$REBASE_APPLY" ] || \
   [ -e "$MERGE_HEAD" ] || [ -e "$CHERRY_PICK_HEAD" ] || \
   [ -e "$REVERT_HEAD" ] || [ -e "$BISECT_LOG" ]; then
  echo "A git operation is already in progress. Finish or abort it before running ./sync.sh." >&2
  exit 1
fi

# Reject dirty working tree.
if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree is not clean. Commit or stash changes before syncing." >&2
  exit 1
fi

# Verify remote identity locally.
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
UPSTREAM_URL="$(git remote get-url upstream 2>/dev/null || true)"

case "${ORIGIN_URL%.git}" in
  git@github.com:hnnsly/brauz|https://github.com/hnnsly/brauz|ssh://git@github.com/hnnsly/brauz) ;;
  *) echo "Remote 'origin' must point to github.com/hnnsly/brauz." >&2; exit 1 ;;
esac

case "${UPSTREAM_URL%.git}" in
  git@github.com:driceroland/Search|https://github.com/driceroland/Search|ssh://git@github.com/driceroland/Search) ;;
  *) echo "Remote 'upstream' must point to github.com/driceroland/Search." >&2; exit 1 ;;
esac

git fetch -q upstream
git fetch -q origin

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Never modify main. On main, create a topical sync branch.
if [ "$BRANCH" = "main" ]; then
  BACKUP_REF="backup/main-$TIMESTAMP"
  git tag "$BACKUP_REF" main
  echo "Created backup ref '$BACKUP_REF'."

  SYNC_BRANCH="sync/upstream-$TIMESTAMP"
  git checkout -b "$SYNC_BRANCH" main
  echo "Created topical branch '$SYNC_BRANCH' from main."
  BRANCH="$SYNC_BRANCH"
else
  echo "Continuing on topical branch '$BRANCH'."
fi

behind="$(git rev-list --count "$BRANCH..upstream/main")"

if [ "$behind" -gt 0 ]; then
  BACKUP_REF="backup/${BRANCH//\//-}-$TIMESTAMP"
  git tag "$BACKUP_REF" "$BRANCH"
  echo "Created backup ref '$BACKUP_REF'."
  echo "$behind commit(s) behind upstream/main. Rebasing '$BRANCH' onto upstream/main..."

  set +e
  git rebase upstream/main -x 'git checkout upstream/main -- CHANGELOG.md && git commit -q --amend --no-edit --allow-empty'
  rebase_status=$?
  set -e

  if [ "$rebase_status" -ne 0 ]; then
    if ! [ -e "$REBASE_MERGE" ] && ! [ -e "$REBASE_APPLY" ]; then
      echo "git rebase failed to start." >&2
      exit 1
    fi

    while [ -e "$REBASE_MERGE" ] || [ -e "$REBASE_APPLY" ]; do
      conflicted="$(git diff --name-only --diff-filter=U)"
      had_conflicts=false
      if [ -n "$conflicted" ]; then
        had_conflicts=true
        if echo "$conflicted" | grep -qx "CHANGELOG.md"; then
          git checkout upstream/main -- CHANGELOG.md
          git add CHANGELOG.md
          conflicted="$(git diff --name-only --diff-filter=U)"
        fi
      fi

      if [ "$had_conflicts" = true ] && [ -z "$conflicted" ]; then
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
        echo "Rebase stopped with conflict." >&2
        if [ -n "$commit" ]; then
          echo "Commit: $commit" >&2
        fi
        if [ -n "$conflicted" ]; then
          echo "Conflicted files:" >&2
          echo "$conflicted" >&2
        else
          echo "Rebase stopped with no conflicted files (exec failure or empty commit)." >&2
        fi
        echo "" >&2
        echo "Rebase state retained for primary resolution." >&2
        echo "Resolve conflicts, stage with 'git add', run 'git rebase --continue', and rerun ./sync.sh." >&2
        echo "Or run 'git rebase --abort' to return to '$BACKUP_REF'." >&2
        exit 1
      fi
    done
  fi
else
  echo "Branch '$BRANCH' is up to date with upstream/main."
fi

# Verification with external Xcode toolchain.
echo "Verifying with Xcode toolchain at $DEVELOPER_DIR..."
DEVELOPER_DIR="$DEVELOPER_DIR" swift test
DEVELOPER_DIR="$DEVELOPER_DIR" swift build -c release
DEVELOPER_DIR="$DEVELOPER_DIR" ./build.sh

fork_commits="$(git rev-list --count "upstream/main..$BRANCH")"
echo ""
echo "Brauz has $fork_commits fork commit(s) on top of Search."
echo "Sync and verification succeeded for '$BRANCH'."
echo ""
echo "To publish, push the topical branch to origin:"
echo "  git push -u origin $BRANCH"
echo ""
echo "Then create a pull request against main:"
echo "  gh pr create --base main --head $BRANCH --title \"Sync with upstream Search\" --body \"Rebased onto upstream/main.\""
