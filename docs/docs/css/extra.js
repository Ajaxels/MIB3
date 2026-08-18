// requires addition of
// extra_javascript:
//   - javascripts/extra.js
// into mkdocs.yml

// GLightbox options, merged by the theme into its own defaults when it creates
// the lightbox for {.on-glb} images.
//
// selector: null disables GLightbox's built-in click handling. The theme calls
// setElements() with the anchors it collected and binds its own click -> openAt(n),
// but GLightbox has already bound its own click -> open(anchor) via the default
// ".glightbox" selector. Entries built by setElements() carry no "node" property,
// so GLightbox's getElementIndex(anchor) always fails and its handler falls back
// to slide 0. One click then opens two slides: slide 0 and the one clicked, both
// keeping the "current" class, both laid out in flow - the first image on the page
// appears next to whichever image was clicked.
window.GLightboxOptions = {selector: null};

// generate a tooltip balloon
document.addEventListener("DOMContentLoaded", function() {
  const helpElements = document.querySelectorAll("[data-help]");

  helpElements.forEach(element => {
    let balloon;

    element.addEventListener("mouseover", function(e) {
      balloon = document.createElement("div");
      balloon.className = "help-balloon";

      // Add optional title bar if data-help-title exists
      const titleText = element.getAttribute("data-help-title");
      if (titleText) {
        const titleBar = document.createElement("div");
        titleBar.className = "title-bar";
        titleBar.textContent = titleText;
        balloon.appendChild(titleBar);
      }

      // Add main help text
      const helpText = document.createElement("div");
      helpText.textContent = element.getAttribute("data-help");
      balloon.appendChild(helpText);

      // Position balloon
      const rect = element.getBoundingClientRect();
      balloon.style.position = "absolute";
      balloon.style.left = `${rect.left + window.scrollX}px`;
      balloon.style.top = `${rect.bottom + window.scrollY + 5}px`;

      document.body.appendChild(balloon);
    });

    element.addEventListener("mouseout", function() {
      if (balloon) {
        balloon.remove();
        balloon = null;
      }
    });
  });
});