# zuyaml: Parse and Emit YAML 1.2

Converts between YAML 1.2 and ordinary R objects using a bundled copy of
the 'cyaml' C11 parser and emitter, so there is no system dependency and
no runtime dependency beyond R itself. Ambiguous YAML features are
handled strictly and predictably: duplicate keys are refused by default,
the YAML 1.2 core schema is followed so that yes and no resolve as
strings, and integers beyond double precision are preserved rather than
silently rounded. A stream of documents and a sequence are different
things, and the interface keeps them apart. Input size, nesting depth
and the number of values materialised are all bounded, which makes the
parser usable on untrusted input.

## See also

Useful links:

- <https://github.com/pedrobtz/zuyaml>

- <https://pedrobtz.github.io/zuyaml/>

- Report bugs at <https://github.com/pedrobtz/zuyaml/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- Andrew Sampson (author of the bundled cyaml library) \[contributor,
  copyright holder\]
