# Uploading Oculus to GitHub

This folder holds everything for the public repository.

| Item | What it is | Where it goes |
|---|---|---|
| `repo/` | The cleaned source, 31 files, 27 MB | The repository itself |
| `release/Oculus-1.1.dmg` | The installable app, 13 MB | A GitHub Release, as an attached file |
| `RELEASE-NOTES.md` | Text for the release description | Pasted into the release |

The DMG does not go inside the repository. Attach it to a release in step 3.

## 1. Clear out the old repository

The existing `mattvigil-cyber/Oculus` dates from September and predates the cleanup. Delete it at
`https://github.com/mattvigil-cyber/Oculus/settings`, at the bottom of the page under Danger Zone.

## 2. Create the new repository and push

On github.com, click **New**. Name it `Oculus`, set it to Public, and leave every "add a file"
option unticked so it starts empty.

Then in Terminal:

```
cd ~/Library/CloudStorage/GoogleDrive-mattvigil@gmail.com/My\ Drive/Claude\ Projects/Experiments/Oculus/github-upload/repo
git init -b main
git add .
git commit -m "Oculus 1.1"
git remote add origin https://github.com/mattvigil-cyber/Oculus.git
git push -u origin main
```

If the push asks for a password, GitHub wants a personal access token there, not your account
password. The simplest route is the GitHub CLI: run `gh auth login` once, then push again.

No Terminal? On the empty repository page, click **uploading an existing file** and drag in the
contents of `repo/`. Press Cmd+Shift+Period in Finder first so the hidden `.gitignore` shows.

## 3. Publish the release

1. On the repository page, click **Releases**, then **Draft a new release**.
2. Under **Choose a tag**, type `v1.1` and pick **Create new tag**.
3. Title it `Oculus 1.1`.
4. Paste the contents of `RELEASE-NOTES.md` into the description.
5. Drag `release/Oculus-1.1.dmg` into the attachments box and wait for the upload to finish.
6. Click **Publish release**.

## What was left out on purpose

- The bond lexicon. It sits in `lexicons-private/` in the main project folder.
- The `drift` folder, the `.bak` backups, build output and local tooling.
- The link to the hosted copy, and the contact email in the Mac README.

## Still open

- **License.** The repository has none, so nobody has permission to reuse the code. Add an MIT
  license if you want people to build on it.
- **Before you publish the release**, open the DMG once and launch the app from it. Nobody has
  mounted this image yet.
- **After the push**, keep working in the main project folder, not in `repo/`. This folder is a
  snapshot for the first upload.
