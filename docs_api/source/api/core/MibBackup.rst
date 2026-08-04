MibBackup
=========

.. currentmodule:: core

Undo history for the open datasets. A single instance lives on
:class:`models.MibModel` as ``obj.Backup``; entries are written by
:func:`models.MibModel.backup` and replayed by :func:`models.MibModel.undo`
(the :kbd:`Ctrl+Z` shortcut). History depth comes from *Preferences → Backup and
undo* (``max_steps``, and ``max3d_steps`` for 3-D entries).

.. code-block:: matlab

   obj.mibModel.backup('selection', 0);        % 2-D: current slice only
   obj.mibModel.backup('labels', 1);           % 3-D: whole volume
   obj.mibModel.backup('modelLayers', 1);      % whole segmentation layers

Calling ``undo()`` with no index toggles between the last two states (undo →
redo → undo); ``undo(index)`` navigates to a specific point in the history.

Backup types
------------

The first argument of :func:`models.MibModel.backup` selects what is captured.

.. list-table::
   :header-rows: 1
   :widths: 18 42 40

   * - Type
     - What is stored
     - What ``undo`` restores
   * - ``'image'``
     - Pixel snapshot of the image layer plus its metadata dictionary and
       ``viewPort``
     - Pixels, metadata, colour-channel count and viewport
   * - ``'selection'``
     - Pixel snapshot of the selection layer
     - The selection layer
   * - ``'mask'``
     - Pixel snapshot of the mask layer
     - The mask layer; sets ``maskExist``
   * - ``'labels'``
     - Pixel snapshot of the model layer (``'model'`` is accepted as an alias
       for MIB2 compatibility)
     - The model layer; sets ``modelExist``
   * - ``'everything'``
     - Raw packed ``uint8`` of a type-63 layer — model, mask and selection in
       one array. Substituted automatically, see below
     - All three layers at once
   * - ``'modelLayers'``
     - Copies of the ``labels``, ``selection`` and ``mask`` layer **objects**,
       plus ``maskExist``, ``modelExist`` and the selected material
     - The three layer objects, *including the model type*, material names and
       colours
   * - ``'annotations'``
     - Label texts, values and positions from :class:`core.Annotations`
     - The full annotation list
   * - ``'measurements'``
     - ``measure.Data`` from :class:`core.Measurements`
     - The measurements table
   * - ``'lines3d'``
     - A copy of the :class:`core.Lines3D` object
     - The skeleton / lines object
   * - ``'mibDataset'``
     - Deep copy of the whole :class:`core.MibDataset` — image, all layers,
       ROIs, annotations, lines, measurements and every value property
     - The entire dataset container (replaces ``obj.I{id}`` and fires
       ``NewDataset``)

Choosing a type
---------------

* Editing pixels of one layer → the matching layer type (``'selection'``,
  ``'mask'``, ``'labels'``, ``'image'``). Cheapest and most precise.
* Replacing the labels layer with one of a **different model type**
  (63 ↔ 255 / 65535 / 4294967295, or an indexed-object model) →
  ``'modelLayers'``. A pixel snapshot cannot be written back once the type
  changed, because a type-63 layer keeps mask and selection in bits 7-8 of
  ``obj.labels`` while the larger types keep them as standalone layers. Used by
  :func:`models.MibModel.convertModel` and
  :func:`models.MibModel.stitchModelInstances`.
* Rewriting the whole container (dimensions, orientation, ROIs and pixels at
  once) → ``'mibDataset'``.

.. note::
   ``'modelLayers'`` and ``'mibDataset'`` both rely on MATLAB copy-on-write, so
   neither duplicates memory when the entry is created. The difference is what
   the entry keeps alive afterwards: ``'mibDataset'`` pins the image array as
   well, so a later edit of the image forks it. ``'modelLayers'`` also restores
   in a narrower way — it assigns three layer handles on the existing dataset,
   whereas ``'mibDataset'`` swaps the dataset handle itself and rolls back the
   image, ROIs and annotations along with the model.

Automatic substitutions
-----------------------

* ``'model'`` → ``'labels'``.
* For a :class:`core.MibLabels63` model, ``'selection'``, ``'mask'`` and
  ``'labels'`` → ``'everything'``, because all three layers share one array.

When a backup is skipped
------------------------

:func:`models.MibModel.backup` returns silently — no entry is created — when:

* the undo system is switched off (``Backup.enableSwitch == 0``);
* the dataset is in **Virtual** mode and a model layer type was requested;
* ``'modelLayers'`` was requested for a non-**Standard** dataset;
* a 3-D entry was requested while ``max3d_steps == 0``;
* the dataset is 5-D (``depth > 1`` **and** ``time > 1``) and no explicit
  ``.x/.y/.z/.t`` range was given;
* ``enableSelection == 0`` for a model layer type;
* ``'mask'`` was requested but no mask exists.

Storage options
---------------

``backup(type, switch3d, getDataOptions)`` — ``switch3d`` is ``0`` for the
current 2-D slice and ``1`` for the whole 3-D volume (a ``.z`` range covering a
single slice forces ``0``). ``getDataOptions`` accepts:

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Field
     - Meaning
   * - ``.id``
     - Dataset container index; defaults to the active dataset
   * - ``.blockModeSwitch``
     - Store only the currently visible block; overrides ``.x`` / ``.y``
   * - ``.x`` / ``.y`` / ``.z`` / ``.t``
     - ``[min, max]`` ranges of the region to store
   * - ``.roiId``
     - Restrict to a ROI — ``[]`` current, ``0`` all shown, index for one,
       missing or negative for the full dataset
   * - ``.magFactor``
     - Pyramid level to capture at; filled in automatically for Virtual and
       BigData datasets
   * - ``.LinkedData`` / ``.LinkedVariable``
     - Extra state to travel with the entry (e.g. the SAM segmenter point
       list); ``.LinkedVariable.<Field>`` names the variable as seen from
       ``mibController``

Model-type safety
-----------------

Every pixel-layer entry is stamped with the model type it was captured at
(``storeOptions.modelType``). If the live labels layer has since changed type,
:func:`models.MibModel.undo` converts the layer back before applying the
snapshot and stores the current layers as a ``'modelLayers'`` entry for redo, so
neither direction reinterprets packed bits as material indices.

Class reference
---------------

.. autoclass:: MibBackup
   :members:
   :undoc-members:
   :show-inheritance:
