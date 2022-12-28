# github-codeowners-checker
Simple script for outputting the codeowners for every ownership root in a git repository using the rules in the GitHub codeowners file.

Help / usage:
```bash
$ ./github-codeowners-checker --help
```

Usage:
```bash
$ ./github-codeowners-checker -p <path-to-repository-root>
```

You can also tell the ownership checker to ignore the default codeowner rule (`*`) if it exists via the `-i` flag.
This is useful if you want to see what the ownership model is without considering default owners.
