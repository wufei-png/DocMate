# Fill DocMate Catalog Descriptions

Copy this prompt into your own agent and provide the actual path to your
installed `docmate.catalog.json`.

```text
Fill missing DocMate repository descriptions in the docmate.catalog.json file I provide.

Rules:
- Read the docmate.catalog.json file from the path I provide. If I did not provide a path, ask for the exact path before doing anything else.
- Before writing any change, create a backup beside the catalog file using the same filename with a timestamp suffix, for example docmate.catalog.json.backup-YYYYMMDD-HHMMSS.
- Only modify repos[].description. Do not modify any other field.
- Keep the existing repo order. Write the final JSON with 2-space indentation.
- Skip any repo that already has a non-empty description.
- For repos with missing or empty descriptions, use repos[].path to inspect the local project.
- If a repo path does not exist, is not a directory, or cannot be read, skip that repo and report the reason. Do not guess.
- Prefer shallow project evidence: README files, docs entry points, package.json, pyproject.toml, go.mod, Cargo.toml, and similar top-level project metadata.
- If shallow metadata is not enough, inspect the top-level directory structure and a small number of obvious entry files.
- Do not deeply traverse source code, run tests, or use network sources for this task.
- Keep each Chinese description within 80 Chinese characters and each English description within 140 characters.
- Validate that the updated catalog is valid JSON after writing it.

Final response:
- Report the catalog path.
- Report the backup path.
- Report how many descriptions were updated and how many repos were skipped.
- List each updated repo name with its new description.
- List skipped repos with reasons.
- Remind me that after verifying the updated catalog, I may delete the backup file.
```
