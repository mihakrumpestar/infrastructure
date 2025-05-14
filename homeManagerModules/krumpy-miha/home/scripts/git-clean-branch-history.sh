#!/usr/bin/env bash

# Set script to exit if any command fails
set -e

# Function to ask for confirmation
confirm() {
    echo -e "\nAre you sure you want to proceed? (y/n) "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            echo -e "\nOperation aborted.\n"
            exit 1
            ;;
    esac
}

# Check if a branch name was passed as an argument
if [[ -z "$1" ]]; then
    echo -e "\nBranch name not provided. Usage: $0 <branch_name>\n"
    exit 1
fi

branch_name=$1

# Ask for confirmation
confirm

# Ensure the branch exists before proceeding
if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
    echo -e "\nBranch '$branch_name' does not exist. Please provide a valid branch name.\n"
    exit 1
fi

# Checkout the branch
echo -e "\nChecking out branch '$branch_name'..."
git checkout "$branch_name"

# Verify that the checkout was successful
if [ "$(git symbolic-ref --short -q HEAD)" != "$branch_name" ]; then
    echo -e "\nFailed to checkout branch '$branch_name'. Operation aborted.\n"
    exit 1
fi

# Start the git operations
echo -e "\nStarting operations on branch '$branch_name'...\n"

git checkout --orphan temp
git add -A
git commit -m 'Clean history'
git branch -D "$branch_name"
git branch -m "$branch_name"
git push -f origin "$branch_name"

git branch --set-upstream-to=origin/"$branch_name" "$branch_name"
git gc --aggressive --prune=all

# Print out the final commands
echo -e "\nTo get changes on other systems with this repo, run the following commands on them:"
echo "git fetch --all"
echo -e "git reset --hard origin/$branch_name\n"
