# MIB3 Sphinx RST Docblock Style Guide

All MATLAB docblocks in MIB3 use RST format compatible with
`sphinxcontrib-matlabdomain`.  This guide is the authoritative reference — follow
it when writing new functions or updating existing ones.

For build/install instructions see [`docs_api/README.md`](../docs_api/README.md).

---

## Complete Template

```matlab
function [out1, out2] = functionName(in1, in2, options)
% FUNCTIONNAME - One-line description (all-caps name, no function call in text).
%
% Syntax:
%   .. code-block:: matlab
%
%      [out1, out2] = obj.functionName(in1, in2)
%      [out1, out2] = obj.functionName(in1, in2, options)
%
% Optional longer description paragraph.  Separated from Syntax by a blank
% comment line.  May span multiple lines.
%
% Input Arguments:
%   - **in1** — [type] description
%   - **in2** — [type] description
%   - **options** *(optional)* — struct with fields:
%
%     - ``.fieldName`` — [type] description (default: ``defaultValue``)
%     - ``.another``  — [type] description
%
% Output Arguments:
%   - **out1** — [type] description
%   - **out2** — [type] description
%
% **Example 1** — short title describing what the example shows:
%
%   .. code-block:: matlab
%
%      result = obj.functionName(a, b);
%      disp(result);
%
% **Example 2** — another scenario:
%
%   .. code-block:: matlab
%
%      opts.fieldName = true;
%      result = obj.functionName(a, b, opts);
```

---

## Rules by Section

### Header line

```matlab
% FUNCTIONNAME - One-line description.
```

- Function name in **ALL CAPS**, then ` - `, then a short description sentence.
- The description must **not** repeat the function call — describe what the
  function does instead.
- If the description overflows one line, continue on the next line:
  ```matlab
  % FUNCTIONNAME - First part of a longer description that continues
  % on the next line.
  ```

---

### Syntax section

```matlab
% Syntax:
%   .. code-block:: matlab
%
%      [out1, out2] = functionName(arg1, arg2)
%      functionName(arg1, arg2, options)
```

- Always uses `.. code-block:: matlab` — **never** bare `::` followed by indented text.
- Show all meaningful calling forms (required args only, then with optional args).
- **No blank `%` line between `% Syntax:` and `%   .. code-block:: matlab`** — the
  absence of the blank line makes `Syntax:` a definition-list term in RST, which
  causes Sphinx to render it as a highlighted label rather than plain paragraph text.
- Code must be indented **3 spaces** inside the directive block (6 characters
  after `% `, which becomes 3 after RST stripping the leading `% `).
- For **class methods** (`function output = method(obj, arg1)`), use the `obj.`
  calling form in the code block — omit `obj` from the parameter list:
  ```matlab
  % Syntax:
  %   .. code-block:: matlab
  %
  %      obj.methodName(arg1, arg2)
  %      output = obj.methodName(arg1, arg2, options)
  ```
- **Do not use** `...` line continuation inside code blocks — the Pygments MATLAB
  lexer treats `...` followed by text as a comment, breaking syntax highlighting.
  Split long calls differently if needed.

---

### Description paragraph

Optional free-text block after Syntax, before Input Arguments.
Separated from adjacent sections by blank `%` lines.
Use this for background information, references, or caveats.

---

### Input Arguments

```matlab
% Input Arguments:
%   - **paramName** — [type] description
%   - **optionalParam** *(optional)* — [type] description (default: ``value``)
%   - **structParam** — struct with fields:
%
%     - ``.fieldName`` — [type] description (default: ``value``)
%     - ``.nested``   — [type] description
```

Key rules:

| Element | Syntax | Example |
|---------|--------|---------|
| Parameter name | `**bold**` | `**options**` |
| Optional marker | `*(optional)*` after name | `**opts** *(optional)*` |
| Type hint | `[brackets]` | `[logical]`, `[char]`, `[numeric]`, `[struct]` |
| Separator | plain hyphen `-` (U+002D) | `**x** - description` |
| Inline code / default | double backticks | `` ``true`` ``, `` ``'yxzct'`` `` |
| Struct field names | single backticks + dot | `` ``.fieldName`` `` |

**Struct fields must be preceded by a blank `%` line** so RST renders them as a
nested bullet list rather than a continuation of the parent bullet:

```matlab
%   - **options** — struct with fields:
%
%     - ``.fieldA`` — description       ← blank line above is required
%     - ``.fieldB`` — description
```

---

### Enum / multi-value parameters

When a parameter accepts specific string or numeric values, list them as
sub-bullets with the value in backticks:

```matlab
%   - **mode** — [char] operation mode:
%
%     - ``'show'`` — display only, no modifications
%     - ``'crop'`` — crop only
%     - ``'aug'``  — augment, then crop
```

---

### Output Arguments

Same format as Input Arguments:

```matlab
% Output Arguments:
%   - **out1** — [type] description
%   - **out2** — [type] description; ``[]`` when not applicable
```

---

### Usage / Examples

```matlab
% **Example 1** — short title describing the scenario:
%
%   .. code-block:: matlab
%
%      result = obj.functionName(input1, input2);
%      disp(result)
%
% **Example 2** — another scenario:
%
%   .. code-block:: matlab
%
%      opts.fieldName = true;
%      result = obj.functionName(input1, input2, opts);
```

- Examples appear **at the top level** — no enclosing `Usage:` section wrapper.
  Each example heading is `**Example N** — description:` with `N` starting at 1.
- When there is only one example, the number may be omitted: `**Example** — ...`.
- Blank `%` line before and after each `.. code-block:: matlab`.
- Code indented 3 spaces inside the directive.
- Use `%` for inline MATLAB comments inside code blocks (not `//`).
- Alternative for a single short example without a heading — use `Usage example:` as
  a label (as in `inputQuestDlg.m`):
  ```matlab
  % Usage example:
  %
  %   .. code-block:: matlab
  %
  %      result = obj.functionName(a, b);
  ```

---

### Notes and warnings

```matlab
%   .. note::
%      This function requires the BioFormats MATLAB toolbox.

%   .. warning::
%      Modifying ``obj.id`` directly may cause stale-panel issues in split-panel mode.
```

Use RST `.. note::` and `.. warning::` directives.
Content is indented **3 spaces** under the directive keyword.

---

## Common Pitfalls

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `Syntax:` not highlighted — renders as plain text | Blank `%` line between `% Syntax:` and `%   .. code-block::` | Remove the blank line so RST treats `Syntax:` as a definition-list term |
| Example not rendered as a code block | Missing blank `%` line before or after `.. code-block::` | Add blank `%` lines |
| `...` shown as a comment in code block | Pygments MATLAB lexer quirk | Avoid `...` in example code |
| Struct fields not indented as sub-list | Missing blank `%` line between parent bullet and field list | Add blank `%` line |
| Em dash `—` anywhere in a docblock | Banned repo-wide (root `CLAUDE.md`) | Replace with a plain hyphen `-` |
| `@b Heading` not rendered bold | Old Doxygen syntax | Replace with `**Heading**` |
| `@ Note:` not rendered | Old Doxygen syntax | Replace with `.. note::` directive |
| `[@em optional]` not rendered | Old Doxygen syntax | Replace with `*(optional)*` |
| Field listed as `.fieldName - desc` | Old Doxygen style | Replace with `` - ``.fieldName`` - desc `` |

---

## Converting from Doxygen

Quick mapping of old Doxygen tags to RST equivalents:

| Doxygen | RST |
|---------|-----|
| `@b text` | `**text**` |
| `@em text` | `*text*` |
| `[@em optional]` after param name | `*(optional)*` after bold name |
| `@li item` | `- item` |
| `@ Note:` | `.. note::` |
| `% Example N::` | `**Example N** — title:` at top level + blank line + `.. code-block:: matlab` |
| `.fieldName - description` | `` - ``.fieldName`` — description `` |
| Function call in header (`% FUNC - funcName(a,b).`) | Plain description (`% FUNC - What the function does.`) |

### Fixing indent levels in converted docblocks

Many Doxygen docblocks use flat bullet lists where sub-options should be nested. Sphinx requires **proper indentation levels** to render sub-lists correctly.

**RST Indent Rules:**

| Level | Content | Indent | Example |
|-------|---------|--------|---------|
| 1 | Top-level parameter | 3 spaces (`%   -`) | `%   - **param** — description` |
| 2 | Sub-option / struct field | 5 spaces (`%     -`) | `%     - ``'value'`` — description` |
| 3 | Sub-sub-option / field property | 7 spaces (`%       -`) | `%       - ``'item'`` — nested field` |

**Critical: Blank `%` lines are required** before and after every sub-list to signal RST that the sub-bullets are nested, not siblings:

```matlab
% Input Arguments:
%   - **param** — description
%
%     - ``'value1'`` — option 1          ← 5 spaces, and blank line above
%     - ``'value2'`` — option 2
%
%   - **nextParam** — ...                ← blank line above, back to 3 spaces
```

**Anti-pattern (WRONG) — all bullets at 3 spaces:**
```matlab
%   - **param** — description
%   - ``'value1'`` — option 1
%   - ``'value2'`` — option 2
%   - **nextParam** — ...
```
This renders as a flat list with 4 items; Sphinx warning: "Bullet list ends without a blank line; unexpected unindent".

**Common scenarios:**

1. **Parameter with value options** (e.g., `mode`, `type`, `layer`):
   ```matlab
   %   - **mode** — [char] operation mode:
   %
   %     - ``'show'`` — display only
   %     - ``'edit'`` — edit mode
   %     - ``'save'`` — save and close
   %
   ```

2. **Struct parameter with field list**:
   ```matlab
   %   - **options** — struct with fields:
   %
   %     - ``.fieldA`` — [type] description (default: `` ``value`` ``)
   %     - ``.fieldB`` — [type] description
   %
   ```

3. **Nested struct fields** (3-level nesting, e.g., `G.Nodes` struct with sub-fields):
   ```matlab
   %   - **G** — [graph] MATLAB graph object with properties:
   %
   %     - ``.Nodes`` — [table] node table with columns:
   %
   %       - ``Id`` — node identifier
   %       - ``label`` — node label string
   %
   %     - ``.Edges`` — [table] edge table
   %
   ```

**When converting flat Doxygen lists:**
1. Identify which items are sub-options vs. sibling parameters
2. Move sub-options from 3-space to 5-space indent
3. Add blank `%` lines before the first sub-option and after the last sub-option
4. For `'value' - desc` format, convert to `` ``'value'`` - desc `` with backticks
5. For `.field - desc` format, convert to `` ``.field`` - desc ``
6. If a Doxygen comment contains multiple paragraphs or a definition list followed by bullet list, insert blank `%` lines between sections to help RST parse the structure

---

## Canonical reference file

`mib/+utils/+dlgs/inputQuestDlg.m` is the canonical reference for the target
docblock style — fully converted, includes an options struct with sub-bullets and
a `Usage example:` code block.  When uncertain about formatting, compare against it.
