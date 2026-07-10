# Zensical documentation framework

For full documentation visit [zensical.org](https://zensical.org).

## Commands

* `zensical serve` - Start the live-reloading docs server (localhost:8000)
* `zensical serve -o` - Start server and open browser automatically
* `zensical build` - Build the documentation site to `site/`
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

* Create a new virtual environment
* Install Zensical, type in the console:
```
    >> pip install zensical
```
* Start the live-reloading docs server: `zensical serve`

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
