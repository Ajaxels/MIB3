# Welcome to MkDocs

For full documentation visit [mkdocs.org](https://www.mkdocs.org).

## Commands

* `mkdocs new [dir-name]` - Create a new project; or `mkdocs new` in the current folder
* `mkdocs serve` - Start the live-reloading docs server.
* `mkdocs build` - Build the documentation site.
* `mkdocs -h` - Print help message and exit.
* youtube tutorial: [:fontawesome-brands-youtube:{.red-color}](https://www.youtube.com/watch?v=xlABhbnNrfI)

## Links 

* [Setup](https://squidfunk.github.io/mkdocs-material/setup/) 
* [Reference docs](https://squidfunk.github.io/mkdocs-material/reference/)
* [Icons search](https://squidfunk.github.io/mkdocs-material/reference/icons-emojis)

## Installation

* Create a new virtual environment
* Install mkdocs, type in the console:
```
	>> pip install mkdocs
	>> pip install mkdocs-material
    >> pip install mkdocs-glightbox
```
* Start the live-reloading docs server: `mkdocs serve`


## Project layout

    mkdocs.yml    # The configuration file.
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