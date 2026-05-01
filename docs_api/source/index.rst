MIB3 — Microscopy Image Browser 3
==================================

.. image:: https://img.shields.io/github/license/Ajaxels/MIB3
   :alt: MIT License

**MIB3** is a MATLAB application for interactive processing, segmentation, and
visualization of 2-D to 4-D microscopy datasets.  It runs as a MATLAB script or
as a compiled standalone Windows application built on the AppContainer framework
(ribbon UI, docked document panels).

- **Author:** Ilya Belevich, University of Helsinki
- **Source:** `github.com/Ajaxels/MIB3 <https://github.com/Ajaxels/MIB3>`_

Architecture overview
---------------------

MIB3 follows an **MVC** pattern implemented with MATLAB packages:

.. list-table::
   :header-rows: 1
   :widths: 20 80

   * - Package
     - Purpose
   * - ``+models``
     - Central application state (:class:`models.MibModel`); fires events that controllers observe.
   * - ``+controllers``
     - UI controllers — ribbon, panels, tools, dialogs.
   * - ``+views``
     - App Designer ``.mlapp`` components and the main :class:`views.MibView` window.
   * - ``+core``
     - Dataset and image data classes; undo, labels, annotations.
   * - ``+io``
     - Image I/O factory (loaders and savers for all supported formats).
   * - ``+utils``
     - Dialogs, defaults, deep-learning helpers, and standalone utility functions.
   * - ``+deepmib``
     - Supporting functions for DeepMIB

.. toctree::
   :maxdepth: 2
   :caption: API Reference

   api/core/index
   api/models
   api/controllers/index
   api/views/index
   api/io/index
   api/utils/index
   api/deepmib/deepmib

