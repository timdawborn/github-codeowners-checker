# github-codeowners-checker
Simple script for outputting the codeowners for every ownership root in a git repository using the rules in the GitHub codeowners file.

Help / usage:
```
$ ./github-codeowners-checker --help
usage: github-codeowners-checker [-h] -i INPUT [-I] [-o OUTPUT] [-f {txt,csv}]

Finds file paths that do not have explicit codeowners set..

options:
  -h, --help            show this help message and exit
  -i INPUT, --input INPUT
                        Path to the git repository to check codeowners for.
  -I, --ignore-default-codeowners
                        Whether default codeowner rules (`*`) should be ignored.
  -o OUTPUT, --output OUTPUT
                        Path to write the results to. Defaults to stdout.
  -f {txt,csv}, --output-format {txt,csv}
                        How the output should be formatted.
```

Minimal invocation:
```
$ python3 github-codeowners-checker.py -i <path-to-repository-root>
```
