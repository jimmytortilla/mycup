#!/usr/bin/env bash
set -euo pipefail

echo "=== MyCup Zola fix script ==="

# Must be run from the directory that contains zola.toml
if [[ ! -f zola.toml ]]; then
  echo "Error: zola.toml not found. Run this script from the directory that contains zola.toml."
  exit 1
fi

SITE_DIR="$(pwd)"
GIT_ROOT="$(git rev-parse --show-toplevel)"

echo "Site directory: $SITE_DIR"
echo "Git root:       $GIT_ROOT"
echo

# ---------- 1. Fix the theme ----------
echo "=== Fixing theme ==="
if [[ -d themes/catcrew ]]; then
  echo "Removing broken theme entry..."
  git rm --cached -r themes/catcrew 2>/dev/null || true
  rm -rf themes/catcrew
fi

echo "Adding catcrew as a proper submodule..."
git submodule add https://git.colorized.life/demo.catcrew.studio.git themes/catcrew || {
  echo "Submodule add failed (may already exist). Continuing..."
}

# ---------- 2. Flatten structure if nested ----------
if [[ "$SITE_DIR" != "$GIT_ROOT" ]]; then
  echo
  echo "=== Flattening nested structure ==="
  echo "Moving site files up to git root..."
  
  # Move everything except .git and the script itself
  shopt -s dotglob
  for item in *; do
    [[ "$item" == "fix-mycup.sh" ]] && continue
    [[ "$item" == ".git" ]] && continue
    if [[ -e "$GIT_ROOT/$item" && "$item" != "themes" ]]; then
      echo "Warning: $item already exists in parent — skipping move of $item"
      continue
    fi
    mv -n "$item" "$GIT_ROOT/" 2>/dev/null || true
  done
  shopt -u dotglob

  # Clean up empty site dir if possible
  cd "$GIT_ROOT"
  rmdir "$SITE_DIR" 2>/dev/null || echo "(Left the old directory — it may not be empty)"
  SITE_DIR="$GIT_ROOT"
else
  echo "Already at git root — no flattening needed."
fi

cd "$GIT_ROOT"

# ---------- 3. Proper .gitignore ----------
echo
echo "=== Creating .gitignore ==="
cat > .gitignore << 'GITIGNORE'
# Zola
public/
.zola_cache/

# OS / editor
.DS_Store
*.swp
*~
.vscode/
.idea/

# Env
.env
.env.*
GITIGNORE

# Remove the wrongly named gitignore if it exists
rm -f gitignore mycup/gitignore 2>/dev/null || true

# ---------- 4. GitHub Actions workflow ----------
echo
echo "=== Adding GitHub Actions workflow ==="
mkdir -p .github/workflows

cat > .github/workflows/deploy.yml << 'WORKFLOW'
name: Build and deploy Zola site

on:
  push:
    branches: [main]

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build Zola + upload Pages artifact
        uses: getzola/github-pages@066755243e69f508fd1a74739fbf1a65f656c790
        with:
          zola_version: v0.23.4
          working_directory: .

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
WORKFLOW

# ---------- 5. Commit & push ----------
echo
echo "=== Committing and pushing ==="
git add -A
git status

echo
read -p "Commit and push these changes? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  git commit -m "Fix catcrew theme as submodule, flatten structure, add Pages deploy workflow" || echo "Nothing to commit"
  git push -u origin main
  echo
  echo "Done!"
  echo
  echo "Next steps on GitHub:"
  echo "1. Go to Settings → Pages"
  echo "2. Under 'Build and deployment' → Source, select 'GitHub Actions'"
  echo "3. The workflow will run and your site should appear at:"
  echo "   https://jimmytortilla.github.io/mycup/"
else
  echo "Skipped commit/push. Review changes with 'git status' and commit manually when ready."
fi

echo
echo "=== Script finished ==="
