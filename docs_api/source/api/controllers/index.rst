controllers — UI Controllers
============================

.. currentmodule:: controllers

The ``+controllers`` package contains all UI controller classes.
:class:`controllers.MibController` is the root controller; it owns all
sub-controllers listed below.

Main controllers
----------------

.. toctree::
   :maxdepth: 1

   MibController
   MibRibbon
   MibImageDocument
   BatchProcessing

Panel controllers
-----------------

.. toctree::
   :maxdepth: 1

   MibActiveDataset
   MibDirContents
   MibSegmentation
   MibSelection
   MibRoi
   MibStatusBar
   MibQuickAccessBar

Dataset tool dialogs
--------------------

.. toctree::
   :maxdepth: 1

   BoundingBox
   DisplayAdjust
   CropDataset
   CropObjects
   ResampleDataset
   Snapshot

Segmentation tool dialogs
-------------------------

.. toctree::
   :maxdepth: 1

   Annotations
   Lines3dDialog
   MeasureTool
   Quantification
   QuantificationProperties

Deep learning
-------------

.. toctree::
   :maxdepth: 1

   MibDeep

Preferences and utilities
-------------------------

.. toctree::
   :maxdepth: 1

   Preferences
   WelcomeTips
