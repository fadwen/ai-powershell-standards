# Attribution profiles

The installer writes `.github/powershell-attribution.md` into a project when the project does not
have one, and never changes it afterwards. The content comes from this folder:

- `profiles/<owner>.md` when the project's GitHub owner has a profile. The owner is read from the
  project's `origin` remote, or given with the installer's `-Owner` parameter. The match ignores
  letter case, as GitHub does.
- `template.md` otherwise: the same file with every value empty, for the project to fill in.

To add a profile, copy `template.md` to `profiles/<owner>.md` and fill in the values.

Agents apply the file as DOC-18 in `standards/rules/powershell-help.md` describes.
