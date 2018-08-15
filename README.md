# Merge Conflict Catcher

## Usage

At the moment, the checker script can only be used for one repository at a time (see **Todo** section below).

1. **Setup**
    1. Clone or download the repo.
    1. Copy the Swift script to a place where it's easy to access:
    ```
    cp ./MergeConflictCatcher/main.swift ~/Developer/checkForMergeConflicts.swift
    ```
    1. Open `checkForMergeConflicts.swift` and edit the customizable section at the top:
        1. Check the remote name and default branch to make sure they match your repository.
        1. Add the branches you want to check to the array, using the samples as reference. You can specify just the branch name if the branch will merge into your default branch, or you can specify the branch name and its parent branch name.
1. **Run the checker**
    1. `cd` into the repository you want to check.
    1. Execute the Swift script.
1. **Update as needed**
    1. Remove branches from the Swift script as needed when they are merged.

## It's completely safe

As a matter of principle, the tool **does not modify your branches**. It only performs merges on a detached HEAD, as per the pseudocode below:

```bash
# The only thing the script does that has any permanent effect is this `git fetch`.
git fetch --jobs=5 --recurse-submodules

for branch in branches {
    # Checkout a detached HEAD.
    git checkout --detach branch
    # Check for upstream changes on this branch and fast-forward to the latest version.
    git merge --ff-only origin/branch
    # Test the merge.
    git merge --no-edit origin/parent-branch
    if mergeFailed {
       git merge --abort
    }
}

if someMergeFailed {
    # Reset to the first failed merge, so you can fix the conflict.
    git checkout first-conflicting-branch
    git submodule update --init --recursive
} else {
    git checkout default-branch
}
```

## Todo

- Add support for multiple repositories if possible.
    1. Add a `Repo` struct of some kind that takes an absolute path (must start with `/`) and contains a list of `Branch`es to merge.
    1. `cd` to each repo and test all the branches as usual. This might not work depending on whether the `cd` persists across `Process` invocations. This also means we might have to lose support for returning you to the first conflict automaticallly, since I doubt the final `cd` to the repository with the conflict would persist outside the Swift script execution.
