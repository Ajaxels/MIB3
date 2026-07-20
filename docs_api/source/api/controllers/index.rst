controllers — UI Controllers
============================

.. currentmodule:: controllers

The ``+controllers`` package contains all UI controller classes.
:class:`controllers.MibController` is the root controller that owns all
sub-controllers listed below.

Application core
----------------

Controllers that build and run the main MIB window.

.. toctree::
   :maxdepth: 1

   MibController
   MibRibbon
   MibImageDocument

Docked panels
-------------

Always-visible panels embedded in the main window.

.. toctree::
   :maxdepth: 1

   MibActiveDataset
   MibDirContents
   MibSegmentation
   MibSelection
   MibRoi
   MibStatusBar
   MibQuickAccessBar

Batch automation
----------------

Script-driven processing of multiple datasets.

.. toctree::
   :maxdepth: 1

   BatchProcessing

Image processing tools
----------------------

Dialogs that modify pixel data: contrast, filters, arithmetic, and colour.

.. toctree::
   :maxdepth: 1

   ContrastClahe
   ContrastNormalization
   DisplayAdjust
   ImageArithmetics
   ImageFilters
   MorphOpsImages
   WhiteBalance

Dataset management tools
------------------------

Dialogs for organizing, transforming, and exporting datasets.

.. toctree::
   :maxdepth: 1

   Alignment
   BoundingBox
   ChunkingExport
   ChunkingImport
   CropDataset
   CropObjects
   DatasetInfo
   MakeMovie
   RenameRestore
   RenameShuffle
   ResampleDataset
   Snapshot
   Stitching
   StitchingInspector

Segmentation tools
------------------

Dialogs for creating, editing, and analysing segmentation layers.

.. toctree::
   :maxdepth: 1

   Annotations
   ContentAwareFill
   DebrisRemoval
   GlobalThresholding
   Graphcut
   ImageFrame
   Lines3dDialog
   MeasureTool
   MembranePixClassifier
   MorphOps
   ObjectSeparator
   Quantification
   QuantificationProperties
   Stereology
   WoundHealing

Deep learning
-------------

Neural-network training, prediction, and evaluation.

.. toctree::
   :maxdepth: 1

   MibDeep

Preferences and utilities
-------------------------

Application settings, 3D rendering, and informational dialogs.

.. toctree::
   :maxdepth: 1

   About
   ActionLog
   Preferences
   VolRenApp
   VolRenAppViewer
   UpdateCheck
   WelcomeTips
