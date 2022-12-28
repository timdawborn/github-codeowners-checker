#!/usr/bin/env python3
import argparse
import csv
import io
import os
import re
import subprocess
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Generator, List, Optional, TYPE_CHECKING, TextIO

POSSIBLE_CODEOWNERS_FILE_DIRECTORIES: List[Path] = list(map(Path, ['.', '.github', 'docs']))

if TYPE_CHECKING:
  import _csv


class File:
  name: str
  is_dir: bool
  parent: Optional['File']
  children: List['File']

  owners: Optional[List[str]]

  def __init__(self, name: str, *, is_dir: bool = False):
    if '/' in name:
      raise ValueError(f'Name cannot contain "/", got {name!r}')
    self.name = name
    self.is_dir = is_dir
    self.parent = None
    self.children = []
    self.owners = None

  def add_child(self, child: 'File') -> None:
    assert child.parent is None
    assert len(child.children) == 0

    # Parent the child.
    child.parent = self
    self.children.append(child)

  def find_ownership_roots(self) -> Generator['File', None, None]:
    if self.is_dir:
      # If the whole subtree from myself down has a consistent owner, output this node and do not
      # recurse further down this subtree.
      if self.is_subtree_ownership_consistent():
        yield self
      else:
        for child in sorted(self.children, key=lambda f: f.name):
          yield from child.find_ownership_roots()
    else:
      # If we reached a regular file, our search was not pruned at a higher level, so we must
      # have an distinct owner from our siblings.
      yield self

  def get_child(self, name: str) -> Optional['File']:
    for child in self.children:
      if child.name == name:
        return child
    return None

  def get_path(self) -> str:
    parts: List[str] = []
    f: Optional[File] = self
    while f is not None:
      parts.append(f.name)
      f = f.parent
    parts.reverse()
    return '/'.join(parts)

  def is_subtree_ownership_consistent(self) -> bool:
    # Prefer a BFS over a DFS (recursive) search here as its more likely that siblings will have
    # different owners as opposed to descendants, allowing us to bail faster.
    todo = [self]

    while todo:
      file = todo.pop(0)
      if file.owners != self.owners:
        return False
      if file.is_dir:
        for child in file.children:
          todo.append(child)

    return True

  def set_owners(self, owners: List[str]) -> None:
    self.owners = owners
    if self.is_dir:
      for child in self.children:
        child.set_owners(owners)

  def walk(self) -> Generator['File', None, None]:
    yield self
    if self.is_dir:
      for child in self.children:
        yield from child.walk()

  def __str__(self) -> str:
    return self.name

  def __repr__(self) -> str:
    return f'{self.__class__.__name__}(name={self.name!r}, is_dir={self.is_dir!r})'


class Filesystem:
  root: File

  def __init__(self) -> None:
    self.root = File('', is_dir=True)

  def create_file(self, path: str) -> None:
    if path.startswith('/'):
      raise ValueError(f'Provided path value must not start with a directory separator(got {path!r})')
    if path.endswith('/'):
      raise ValueError(f'Provided path value must not end in a directory separator (got {path!r})')

    # Upsert the directory structure until the file.
    # This is essentially doing a `mkdir -p`.
    d = self.root
    parts = path.split('/')
    while len(parts) != 1:
      part = parts.pop(0)

      next_d = d.get_child(part)
      if next_d is None:
        next_d = File(part, is_dir=True)
        d.add_child(next_d)
      elif not next_d.is_dir:
        raise Exception(f'Looking up {part!r} of {path!r} and found something that is not a directory. This should not happen.')

      d = next_d

    # Create the file.
    part = parts[0]
    f = d.get_child(part)
    if f is not None:
      raise Exception(f'Looking up {part!r} of {path!r} and found that it already exists. This should not happen.')
    f = File(part)
    d.add_child(f)

  def find_ownership_roots(self) -> Generator['File', None, None]:
    yield from self.root.find_ownership_roots()

  def walk(self) -> Generator[File, None, None]:
    yield from self.root.walk()


class CodeownersPattern:
  pattern: str
  regex: re.Pattern

  def __init__(self, pattern: str) -> None:
    self.pattern = pattern

    # There is an implicit globstar at the start if no alternative is specified.
    if not pattern.startswith('/') and not pattern.startswith('**'):
      pattern = '**/' + pattern
    pattern = pattern.lstrip('/')

    # A trailing slash indicates the matching node must be a directory.
    require_directory = False
    if pattern.endswith('/'):
      require_directory = True
      pattern = pattern.rstrip('/')

    regex = io.StringIO()
    regex.write('^')
    prev_wrote_slash = False
    for part in pattern.split('/'):
      if not prev_wrote_slash:
        regex.write('/')
      prev_wrote_slash = False

      if part == '':
        pass
      elif part == '**':
        regex.write(r'([^/]+/)*')
        prev_wrote_slash = True
      else:
        for c in part:
          if c == '*':
            regex.write(r'[^/]*')
          elif c == '?':
            regex.write(r'[^/]')
          else:
            regex.write(re.escape(c))

    if require_directory:
      regex.write('($|/)')

    self.regex = re.compile(regex.getvalue())

  def matches(self, file: File) -> bool:
    m = self.regex.match(file.get_path())
    return m is not None

  def __str__(self) -> str:
    return f'Pattern({self.pattern} => {self.regex.pattern})'

  def __repr__(self) -> str:
    return str(self)


class CodeownersRule:
  pattern: CodeownersPattern
  owners: List[str]

  def __init__(self, pattern: CodeownersPattern, owners: List[str]) -> None:
    self.pattern = pattern
    self.owners = owners

  def matches(self, file: File) -> bool:
    return self.pattern.matches(file)


class Codeowners:
  RE_COMMENT = re.compile(r'#.*')

  rules: List[CodeownersRule]

  def __init__(self, path: Path, *, ignore_default_codeowners: bool = False) -> None:
    self.rules = []

    with open(path) as f:
      for n, line in enumerate(f, start=1):
        # Strip comments.
        line = self.RE_COMMENT.sub('', line).strip()
        if not line:
          continue

        pattern, *owners = line.split()
        if pattern == '*' and ignore_default_codeowners:
          continue
        rule = CodeownersRule(pattern=CodeownersPattern(pattern), owners=owners)
        self.rules.append(rule)

  def get_codeowners(self, file: File) -> Optional[List[str]]:
    # Order is important; the last matching pattern takes the most precedence.
    matched_rule = None
    for rule in self.rules:
      if rule.matches(file):
        matched_rule = rule

    return None if matched_rule is None else matched_rule.owners


class OutputFormatter(ABC):
  output_file: TextIO

  def __init__(self, output_file: TextIO) -> None:
    self.output_file = output_file

  @abstractmethod
  def write_result(self, file: File) -> None:
    pass


class CsvOutputFormatter(OutputFormatter):
  writer: '_csv._writer'

  def __init__(self, output_file: TextIO) -> None:
    super().__init__(output_file)
    self.writer = csv.writer(self.output_file)
    self.writer.writerow(['File path', 'Has codeowners defined?', 'Codeowners'])

  def write_result(self, file: File) -> None:
    row = [file.get_path()]
    if file.owners is None:
      row.append('False')
    else:
      row.append('True')
      row.extend(sorted(file.owners))
    self.writer.writerow(row)


class TxtOutputFormatter(OutputFormatter):
  def write_result(self, file: File) -> None:
    if file.owners is None:
      ownership = 'No codeowners.'
    elif len(file.owners) == 0:
      ownership = 'Explicitly no codeowners set.'
    else:
      ownership = ', '.join(sorted(file.owners))
    print(f'{file.get_path()}: {ownership}')


OUTPUT_FORMATTERS = {
  'csv': CsvOutputFormatter,
  'txt': TxtOutputFormatter,
}


def load_codeowners_file(ignore_default_codeowners: bool) -> Codeowners:
  # Attempt to locate the GitHub codeowners file.
  for d in POSSIBLE_CODEOWNERS_FILE_DIRECTORIES:
    path = d / 'CODEOWNERS'
    if path.exists():
      break
  else:
    raise Exception('Failed to find CODEOWNERS file.')

  return Codeowners(path, ignore_default_codeowners=ignore_default_codeowners)


def find_comitted_paths() -> List[str]:
  output = subprocess.check_output(['git', 'ls-files'], text=True)
  return output.strip().split('\n')


def main(
    ignore_default_codeowners: bool,
    output_formatter: OutputFormatter,
) -> None:
  codeowners = load_codeowners_file(ignore_default_codeowners)

  fs = Filesystem()
  for path in find_comitted_paths():
    fs.create_file(path)

  for f in fs.walk():
    owners = codeowners.get_codeowners(f)
    if owners is not None:
      f.set_owners(owners)

  for f in fs.find_ownership_roots():
    output_formatter.write_result(f)


if __name__ == '__main__':
  parser = argparse.ArgumentParser(description='Finds file paths that do not have explicit codeowners set..')
  parser.add_argument('-i', '--input', required=True, help='Path to the git repository to check codeowners for.')
  parser.add_argument('-I', '--ignore-default-codeowners', action='store_true', help='Whether default codeowner rules (`*`) should be ignored.')
  parser.add_argument('-o', '--output', default='/dev/stdout', help='Path to write the results to. Defaults to stdout.')
  parser.add_argument('-f', '--output-format', choices=['txt', 'csv'], default='txt', help='How the output should be formatted.')
  args = parser.parse_args()

  # Change directory to the git repository.
  os.chdir(args.input)

  # Open the output file for writing.
  with open(args.output, 'w') as fout:
    # Construct the desired output formatter.
    klass = OUTPUT_FORMATTERS[args.output_format]
    output_formatter = klass(fout)

    # Kick off the main logic.
    main(args.ignore_default_codeowners, output_formatter)
