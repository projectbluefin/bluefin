# Contribution workflow

## Work states

Issues and pull requests move through the repository's configured lifecycle.
The automation and labels are the source of truth; use the issue-lifecycle skill
for command details.

## Safe change flow

1. Identify the source-of-truth files.
2. Select the smallest matching skill.
3. Make one focused change.
4. Run the relevant validation.
5. Update the matching documentation when a reusable fact changes.
6. Open a pull request targeting `testing`; normal feature work must not target `main`.

## Documentation changes

Documentation-only changes still use the normal review path. They should not
trigger expensive image builds unless a workflow path filter says otherwise.

## Boundaries

Do not bypass review, signing, branch, or verification protections merely to
make a workflow appear green. Escalate a blocked trust or policy gate with the
relevant run and source path.
