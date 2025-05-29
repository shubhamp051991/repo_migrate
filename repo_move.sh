#!/bin/bash
set -e
#
# Git Migration Script with Skip CI
# --------------------------------
# Simple script that keeps workflows but uses skip-ci to prevent running

# Configuration (edit these values)
MONOLITH_REPO="https://github.com/EliLillyCo/lusa-aiassistant-datascience.git"  # Change this
TEMP_DIR="./migration_temp"
CONFIG_FILE="migration_config.json"

# Create temp directory
mkdir -p "$TEMP_DIR"

# Process each project from config file
cat "$CONFIG_FILE" | jq -c '.projects[]' | while read -r project; do
    # Get basic project info
    PROJECT_NAME=$(echo "$project" | jq -r '.name')
    PROJECT_FOLDER=$(echo "$project" | jq -r '.folder')
    NEW_REPO=$(echo "$project" | jq -r '.new_repo')
    BRANCHES=$(echo "$project" | jq -r '.branches | join(" ")')
    
    echo "Processing project: $PROJECT_NAME"
    echo "  Folder: $PROJECT_FOLDER"
    echo "  Target repo: $NEW_REPO"
    echo "  Branches: $BRANCHES"

    # Collect workflow paths
    WORKFLOW_PATHS=$(echo "$project" | jq -r '.workflows[].source_repo_path')
    
    # Process each branch separately
    for branch in $BRANCHES; do
        echo "  Processing branch: $branch"
        
        # Create branch directory
        BRANCH_DIR="$TEMP_DIR/$PROJECT_NAME/$branch"
        rm -rf "$BRANCH_DIR"
        mkdir -p "$BRANCH_DIR"
        cd "$BRANCH_DIR"
        
        # Clone monolith and checkout specific branch
        git clone -b "$branch" --single-branch "$MONOLITH_REPO" source
        cd source || { echo "❌ cd failed, stopping."; exit 1; }
        
        # Create paths file for git-filter-repo
        echo "$PROJECT_FOLDER" > paths.txt
        for wf_path in $WORKFLOW_PATHS; do
            echo "$wf_path" >> paths.txt
        done
        
        echo "  Filter paths:"
        cat paths.txt
        
        # Extract both the project folder and .github directory
        git-filter-repo --paths-from-file paths.txt --path-rename "$PROJECT_FOLDER/:" --force
        
        # Verify the result
        echo "  Repository contents after filtering:"
        ls -la
        
        if [ -d ".github" ]; then
            echo "  .github directory exists after filtering"
            ls -la .github/
            
            # Create a README explaining the workflows are for manual triggers only
            echo "# Workflow Notes" > .github/README.md
            echo "" >> .github/README.md
            echo "The GitHub Actions workflows in this repository are configured for manual triggering only." >> .github/README.md
            echo "To run a workflow, use the 'Run workflow' button in the Actions tab." >> .github/README.md
            
            git add .github/README.md
            
            # Commit the README with skip ci flag
            git commit -m "Add workflow README [skip ci]" || echo "  No README to commit"
        else
            echo "  WARNING: .github directory not found after filtering"
        fi
        
        # Force push to target repo with skip ci flag
        git remote add target "$NEW_REPO"
        echo "  Force pushing branch $branch to target repository..."
        git push -f target HEAD:$branch -o ci.skip
        
        # Go back to starting directory
        cd ../../..
    done
    
    echo "Completed migration for $PROJECT_NAME"
    echo ""
done

echo "All migrations completed"
