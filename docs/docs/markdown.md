# Zensical documentation framework

For full documentation visit [zensical.org](https://zensical.org).

## Commands

* `zensical serve` - Start the live-reloading docs server (localhost:8000)
* `zensical serve -o` - Start server and open browser automatically
* `zensical build` - Build the documentation site to `html/`
* `zensical -h` - Print help message and exit

??? example "Run example"
    
    - Run powershell
    - Navigate to `docs` subfolder of MIB project
    - Run `c:\Python\Miniforge\envs\mkdocs\Scripts\zensical serve` to start the server, replace the path with the actual path to the proper python environment
    - Open `http://localhost:8000` in browser

## Links

* [Zensical documentation](https://zensical.org/docs/)
* [Setup](https://zensical.org/docs/setup/basics/)
* [Authoring](https://zensical.org/docs/authoring/)
* [Customization](https://zensical.org/docs/customization/)
* [Icons search](https://squidfunk.github.io/mkdocs-material/reference/icons-emojis)

## Installation

### 1. Install Miniforge

Download and install [Miniforge](https://github.com/conda-forge/miniforge/releases) (tested with
`Mambaforge-24.11.0-0-Windows-x86_64.exe`, base Python 3.12) and accept the default settings.

### 2. Create the Zensical environment

Open **Miniforge Prompt** (Start → Miniforge3 → Miniforge Prompt) and create a new environment,
replacing the path with your preferred location:

```
conda create --prefix d:\Python\Miniforge3\envs\Zensical python=3.12
activate Zensical
```

### 3. Install packages

```
pip install zensical
```

Optionally, install Sphinx and the MATLAB domain, which are used to build the API reference
(`docs_api/`, see [API reference installation](api.md#installation)):

```
pip install sphinx sphinxcontrib-matlabdomain sphinx-rtd-theme sphinx-immaterial
```

To update Zensical later:

```
d:\Python\Miniforge3\envs\Zensical\Scripts\python.exe -m pip install --upgrade zensical
```

### 4. PyCharm configuration (optional)

1. **Settings → Project → Python Interpreter → Add Interpreter** and point it to
   `d:\Python\Miniforge3\envs\Zensical\python.exe`
2. If the terminal does not pick up the environment: close the terminal, open
   **Settings → Tools → Terminal**, enable **Activate virtualenv**, set **Shell path** to
   `powershell.exe` and open a new terminal

Check which Python is active with `where.exe python`

### 5. Generate the documentation

Run the commands from the `docs` subfolder of the MIB project, replacing the path with the location
of your Zensical environment.

Build the static site into `docs/html/`:

```
d:\Python\Miniforge3\envs\Zensical\Scripts\zensical build
```

Start the live-reloading preview at [http://localhost:8000](http://localhost:8000):

```
d:\Python\Miniforge3\envs\Zensical\Scripts\zensical serve
```

!!! note

    Do not edit files in `docs/html/`, they are overwritten on every build.

## Project layout

    zensical.toml    # The configuration file (TOML format).
    docs
     |----/assets/          # Folder for images etc
     |        logo.png      # Logo image
     |----/css/             # Folder for styles
     |        styles.css    # CSS styles
     |-index.md             # The documentation homepage.
     |-documentation.md     # Another page
       ...                 # Other markdown pages, images and other files.

Text with icons: :octicons-gear-16: or in color as :octicons-gear-16:{.orange-color} or :fontawesome-brands-youtube:{.red-color}  
icons search from<br>
[https://squidfunk.github.io/mkdocs-material/reference/icons-emojis](https://squidfunk.github.io/mkdocs-material/reference/icons-emojis)

# Header 1 - Title `#`
## Header 2 `##`
### Header 3 `###`
<div class="h3-like">h3-like not listed in the table of contents</div>  `div class="h3-like">h3-like not listed in the table of contents</div>` 
#### Header 4 `####`
##### Header 5 `#####`
###### Header 6 `#####`
