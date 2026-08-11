# Microscopy Image Browser 3 (MIB3)

MIB3 is a MATLAB application for processing, segmentation, analysis and visualisation of
multidimensional (2D-4D) microscopy datasets.

It reads a wide range of microscopy formats, works with datasets larger than available memory
through virtual and big-data modes, and provides manual, semi-automatic and deep-learning based
segmentation tools.

- Project site and downloads: https://mib.helsinki.fi
- Developed at the University of Helsinki

## Requirements

- MATLAB R2026a or newer
- A compiled standalone version, which does not require a MATLAB licence, is distributed
  separately from https://mib.helsinki.fi

## Running from source

```matlab
cd mib
mib3
```

## Documentation

- User documentation: `docs/` (built with Zensical, also published at https://mib.helsinki.fi)
- API reference: `docs_api/` (built with Sphinx)
- Developer notes: `development/INDEX.md`

## Licence

MIB is distributed under different terms depending on the form in which you use it:

| Form | Licence |
|------|---------|
| **MATLAB source code** - this repository | [GNU General Public License v3 or later](LICENSE) |
| **Compiled standalone application** | Separate licence, see [MIB standalone licence](docs/docs/getting-started/licenses/license-mib-standalone.md) |
| **Bundled external packages** | Their own respective licences, see [external licences](docs/docs/getting-started/licenses/licenses-ext.md) |

The authoritative summary is at https://mib.helsinki.fi/license.html.

```
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty
of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see https://www.gnu.org/licenses.
```

Copyright (c) 2010-2026 Ilya Belevich, Merja Joensuu, Darshan Kumar, Helena Vihinen
and Eija Jokitalo.

## How to cite

If you use MIB in your research, please cite it. See
https://mib.helsinki.fi for the current citation.
