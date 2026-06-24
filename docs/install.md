# Building the User Documentation

MIB3 user documentation is built with **Zensical** (an MkDocs-based static site
generator).  This file covers environment setup, serving a live preview, and
producing a static build.

For building the Sphinx API reference see [`docs_api/install.md`](../docs_api/install.md).

---

## 1. Install Miniforge

Download and install **Miniforge** (tested with `Mambaforge-24.11.0-0-Windows-x86_64.exe`,
base Python 3.12).

All Mambaforge releases:
<https://github.com/conda-forge/miniforge/releases>

Run the installer and accept the defaults.

---

## 2. Create the Zensical environment

Open **Miniforge Prompt** (Start → Miniforge3 → Miniforge Prompt) and run:

```
conda create --prefix d:\Python\Miniforge3\envs\Zensical python=3.12
```

Replace `d:\Python\Miniforge3\envs\Zensical` with your preferred install path.

Activate the environment:

```
activate Zensical
```

---

## 3. Install packages

Install Zensical:

```
pip install zensical
```

Install Sphinx and the MATLAB domain (used for the API reference — see
[`docs_api/install.md`](../docs_api/install.md)):

```
pip install sphinx sphinxcontrib-matlabdomain sphinx-rtd-theme sphinx-immaterial
```

---

## 4. PyCharm configuration (optional)

Add the new environment as an interpreter:

1. **Settings → Project → Python Interpreter → Add Interpreter**
   Point it to `d:\Python\Miniforge3\envs\Zensical\python.exe`.
2. If the environment is not picked up by the terminal:
   - Close the current terminal.
   - Go to **Settings → Tools → Terminal**.
   - Enable **Activate virtualenv**.
   - Set **Shell path** to `powershell.exe`.
   - Open a new terminal.

Verify the active Python with:

```
where.exe python
```

---

## 5. Serve a live preview

From the `docs/` directory:

```
d:\Python\Miniforge3\envs\Zensical\Scripts\zensical serve
```

Open <http://localhost:8000> in a browser.  The page reloads automatically on
file changes.

Shorthand if Zensical is on `PATH`:

```
zensical serve
zensical serve -o   # opens the browser automatically
```

---

## 6. Build the static site

From the `docs/` directory:

```
d:\Python\Miniforge3\envs\Zensical\Scripts\zensical build
```

Output is written to `docs/site/`.  Do **not** edit files there — regenerate
as needed.

Shorthand if Zensical is on `PATH`:

```
zensical build
```
